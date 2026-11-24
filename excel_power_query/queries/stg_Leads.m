// CRM lead export -> one clean row per lead.
let
    Source = fnReadCsv("crm_leads_export.csv"),
    // 1. The export was run twice for part of the period: drop exact duplicate rows.
    RemovedDuplicates = Table.Distinct(Source),
    // 2. Remove test records created by the CRM admin.
    RemovedTests = Table.SelectRows(
        RemovedDuplicates,
        each not Text.Contains([lead_id], "TEST") and [assigned_rep_id] <> "R999" and [region] <> "Test"
    ),
    // 3. ISO + UK (dd/mm/yyyy) dates -> real dates.
    ParsedDate = Table.TransformColumns(RemovedTests, {{"created_date", fnParseDate, type date}}),
    // 4. Standardise region and lead source labels with the two mapping queries (merge = lookup).
    AddedKeys = Table.AddColumn(
        Table.AddColumn(ParsedDate, "region_key", each Text.Lower(Text.Trim([region])), type text),
        "source_key", each Text.Lower(Text.Trim([lead_source])), type text
    ),
    MergedRegion = Table.NestedJoin(AddedKeys, {"region_key"}, map_Region, {"raw_label"}, "map_r", JoinKind.LeftOuter),
    ExpandedRegion = Table.ExpandTableColumn(MergedRegion, "map_r", {"region_clean"}),
    MergedSource = Table.NestedJoin(ExpandedRegion, {"source_key"}, map_LeadSource, {"raw_label"}, "map_s", JoinKind.LeftOuter),
    ExpandedSource = Table.ExpandTableColumn(MergedSource, "map_s", {"lead_source_clean"}),
    // 5. Keep the clean columns under their original names.
    RemovedRaw = Table.RemoveColumns(ExpandedSource, {"region", "lead_source", "region_key", "source_key"}),
    Renamed = Table.RenameColumns(RemovedRaw, {{"region_clean", "region"}, {"lead_source_clean", "lead_source"}}),
    Selected = Table.SelectColumns(
        Renamed,
        {"lead_id", "created_date", "lead_source", "segment", "region", "assigned_rep_id", "lead_status"}
    )
in
    Selected
