// CRM opportunity export -> clean fact table, enriched with lead, product and rep attributes.
// Loaded to the Opportunities sheet as table tblOpportunities; all PivotTables read from it.
let
    Source = fnReadCsv("crm_opportunities_export.csv"),
    // 1. Remove test records and any repeated opp_id.
    RemovedTests = Table.SelectRows(Source, each not Text.Contains([opp_id], "TEST") and [rep_id] <> "R999"),
    RemovedDuplicateIds = Table.Distinct(RemovedTests, {"opp_id"}),
    // 2. Dates.
    ParsedDates = Table.TransformColumns(
        RemovedDuplicateIds,
        {
            {"created_date", fnParseDate, type nullable date},
            {"quote_sent_date", fnParseDate, type nullable date},
            {"credit_check_date", fnParseDate, type nullable date},
            {"close_date", fnParseDate, type nullable date},
            {"install_date", fnParseDate, type nullable date},
            {"cancel_date", fnParseDate, type nullable date},
            {"activation_date", fnParseDate, type nullable date}
        }
    ),
    // 3. Numbers: ~5% of mrr_gbp values arrive as text like "£32.00". Strip the symbol, then parse with en-US culture.
    CleanedNumbers = Table.TransformColumns(
        ParsedDates,
        {
            {"mrr_gbp", each Number.FromText(Text.Replace(_, Character.FromNumber(163), ""), "en-US"), type number},
            {"discount_pct", each Number.FromText(_, "en-US"), type number},
            {"contract_months", each Int64.From(Number.FromText(_, "en-US")), Int64.Type}
        }
    ),
    // 4. Product names have inconsistent casing ("fibre 500"): match the catalogue case-insensitively.
    AddedProductKey = Table.AddColumn(CleanedNumbers, "product_key", each Text.Lower([product_name]), type text),
    MergedProducts = Table.NestedJoin(
        Table.RemoveColumns(AddedProductKey, {"product_name"}),
        {"product_key"}, stg_Products, {"product_key"}, "product", JoinKind.LeftOuter
    ),
    ExpandedProducts = Table.ExpandTableColumn(MergedProducts, "product", {"product_id", "product_name", "list_mrr_gbp"}),
    // 5. 54 discounts are impossible (150, 100, -10). The true value is recoverable exactly from list price vs net MRR.
    AddedDiscount = Table.AddColumn(
        ExpandedProducts, "discount_clean",
        each if [discount_pct] >= 0 and [discount_pct] <= 50 then [discount_pct]
             else Number.Round((1 - [mrr_gbp] / [list_mrr_gbp]) * 100, 0),
        type number
    ),
    AddedDiscountRecovered = Table.AddColumn(
        AddedDiscount, "discount_recovered",
        each if [discount_pct] >= 0 and [discount_pct] <= 50 then 0 else 1, Int64.Type
    ),
    ReplacedDiscount = Table.RenameColumns(
        Table.RemoveColumns(AddedDiscountRecovered, {"discount_pct"}), {{"discount_clean", "discount_pct"}}
    ),
    AddedDiscountBand = Table.AddColumn(ReplacedDiscount, "discount_band", each Text.From([discount_pct]) & "%", type text),
    // 6. Lost deals with no reason keep counting in every rate, under an explicit label.
    AddedLostReason = Table.AddColumn(
        AddedDiscountBand, "lost_reason_clean",
        each if [outcome] = "Lost" and ([lost_reason] = null or [lost_reason] = "") then "Not recorded"
             else if [lost_reason] = "" then null else [lost_reason],
        type nullable text
    ),
    ReplacedLostReason = Table.RenameColumns(
        Table.RemoveColumns(AddedLostReason, {"lost_reason"}), {{"lost_reason_clean", "lost_reason"}}
    ),
    // 7. Flag (do not delete) deals that close before they were created: kept for win/loss, not usable for cycle time.
    AddedDateError = Table.AddColumn(
        ReplacedLostReason, "date_error",
        each if [close_date] <> null and [close_date] < [created_date] then 1 else 0, Int64.Type
    ),
    // 8. Enrich: lead source, segment and region from the lead (inner join drops orphans); team and channel from HR.
    MergedLeads = Table.NestedJoin(AddedDateError, {"lead_id"}, stg_Leads, {"lead_id"}, "lead", JoinKind.Inner),
    ExpandedLeads = Table.ExpandTableColumn(MergedLeads, "lead", {"lead_source", "segment", "region"}),
    MergedReps = Table.NestedJoin(ExpandedLeads, {"rep_id"}, stg_Reps, {"rep_id"}, "rep", JoinKind.LeftOuter),
    ExpandedReps = Table.ExpandTableColumn(MergedReps, "rep", {"team", "channel"}),
    // 9. Flags and calendar fields for the PivotTables.
    AddedIsClosed = Table.AddColumn(ExpandedReps, "is_closed", each if [outcome] = "Won" or [outcome] = "Lost" then 1 else 0, Int64.Type),
    AddedIsWon = Table.AddColumn(AddedIsClosed, "is_won", each if [outcome] = "Won" then 1 else 0, Int64.Type),
    AddedCloseYear = Table.AddColumn(AddedIsWon, "close_year", each if [close_date] = null then null else Date.Year([close_date]), type nullable number),
    AddedCloseQuarter = Table.AddColumn(
        AddedCloseYear, "close_quarter",
        each if [close_date] = null then null
             else Text.From(Date.Year([close_date])) & "-Q" & Text.From(Date.QuarterOfYear([close_date])),
        type nullable text
    ),
    AddedTcv = Table.AddColumn(AddedCloseQuarter, "tcv_gbp", each Number.Round([mrr_gbp] * [contract_months], 2), type number),
    AddedSalesCycle = Table.AddColumn(
        AddedTcv, "sales_cycle_days",
        each if [date_error] = 0 and [close_date] <> null then Duration.Days([close_date] - [created_date]) else null,
        type nullable number
    ),
    AddedCancelled = Table.AddColumn(
        AddedSalesCycle, "is_cancelled_pre_install",
        each if [order_status] = "Cancelled before install" then 1 else 0, Int64.Type
    ),
    // 10. Final column order and types.
    Selected = Table.SelectColumns(
        AddedCancelled,
        {
            "opp_id", "lead_id", "rep_id", "team", "channel", "lead_source", "segment", "region",
            "product_id", "product_name", "list_mrr_gbp", "discount_pct", "discount_band", "discount_recovered",
            "mrr_gbp", "contract_months", "tcv_gbp", "created_date", "close_date", "close_year", "close_quarter",
            "outcome", "stage", "lost_reason", "is_closed", "is_won", "date_error", "sales_cycle_days",
            "install_date", "order_status", "is_cancelled_pre_install", "activation_date"
        }
    ),
    TypedText = Table.TransformColumnTypes(
        Selected,
        {
            {"opp_id", type text}, {"lead_id", type text}, {"rep_id", type text}, {"team", type text},
            {"channel", type text}, {"lead_source", type text}, {"segment", type text}, {"region", type text},
            {"product_id", type text}, {"product_name", type text}, {"outcome", type text}, {"stage", type text},
            {"order_status", type text}
        }
    )
in
    TypedText
