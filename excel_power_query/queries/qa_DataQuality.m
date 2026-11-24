// Data-quality checks: what Power Query found in the raw exports, next to what the Python pipeline
// (src/clean_data.py -> docs/data_quality_log.md) found in the same files. Every row should say "OK".
let
    Canonical_Regions = {"London", "South East", "Midlands", "North West", "Yorkshire & North East", "Scotland"},
    Canonical_Sources = {"Web", "Web (Business)", "Inbound Call", "Referral", "Outbound Call", "Door-to-Door", "Partner"},
    Product_Names = stg_Products[product_name],

    LeadsRaw = fnReadCsv("crm_leads_export.csv"),
    LeadsDistinct = Table.Distinct(LeadsRaw),
    LeadsNoTests = Table.SelectRows(
        LeadsDistinct,
        each not Text.Contains([lead_id], "TEST") and [assigned_rep_id] <> "R999" and [region] <> "Test"
    ),
    OppRaw = fnReadCsv("crm_opportunities_export.csv"),
    OppNoTests = Table.SelectRows(OppRaw, each not Text.Contains([opp_id], "TEST") and [rep_id] <> "R999"),
    Count = (t as table, condition as function) as number => Table.RowCount(Table.SelectRows(t, condition)),

    Checks = #table(
        type table [table_name = text, issue = text, rows_power_query = Int64.Type, rows_python = Int64.Type, action = text],
        {
            {"leads", "Exact duplicate rows (double export)", Table.RowCount(LeadsRaw) - Table.RowCount(LeadsDistinct), 924, "removed"},
            {"leads", "Test records", Table.RowCount(LeadsDistinct) - Table.RowCount(LeadsNoTests), 5, "removed"},
            {"leads", "created_date in dd/mm/yyyy format", Count(LeadsNoTests, each Text.Contains([created_date], "/")), 1602, "parsed as day-first"},
            {"leads", "Non-standard region labels", Count(LeadsNoTests, each not List.Contains(Canonical_Regions, [region])), 4596, "mapped via map_Region"},
            {"leads", "Non-standard lead_source labels", Count(LeadsNoTests, each not List.Contains(Canonical_Sources, [lead_source])), 3547, "mapped via map_LeadSource"},
            {"leads", "Unmapped region or source after cleaning", Count(stg_Leads, each [region] = null or [lead_source] = null), 0, "must be 0"},
            {"opportunities", "Test records", Table.RowCount(OppRaw) - Table.RowCount(OppNoTests), 5, "removed"},
            {"opportunities", "mrr_gbp stored as text with £", Count(OppNoTests, each Text.Contains([mrr_gbp], Character.FromNumber(163))), 1472, "symbol stripped"},
            {"opportunities", "product_name casing differs from catalogue", Count(OppNoTests, each not List.Contains(Product_Names, [product_name])), 879, "matched case-insensitively"},
            {"opportunities", "discount_pct outside 0-50%", List.Sum(fact_Opportunities[discount_recovered]), 54, "recovered from list price vs net MRR"},
            {"opportunities", "Lost with blank lost_reason", Count(OppNoTests, each [outcome] = "Lost" and [lost_reason] = ""), 1434, "set to Not recorded"},
            {"opportunities", "close_date earlier than created_date", List.Sum(fact_Opportunities[date_error]), 36, "flagged, excluded from cycle time"},
            {"opportunities", "Final clean rows", Table.RowCount(fact_Opportunities), 28847, "loaded to tblOpportunities"},
            {"leads", "Final clean rows", Table.RowCount(stg_Leads), 77005, "connection only"}
        }
    ),
    AddedStatus = Table.AddColumn(Checks, "status", each if [rows_power_query] = [rows_python] then "OK" else "CHECK", type text)
in
    AddedStatus
