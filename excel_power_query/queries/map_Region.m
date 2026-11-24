// Mapping table: every region spelling found in the CRM export (lower-case, trimmed) -> one of 6 canonical regions.
let
    Source = #table(
        type table [raw_label = text, region_clean = text],
        {
            {"london", "London"}, {"greater london", "London"},
            {"south east", "South East"}, {"south-east", "South East"}, {"se", "South East"},
            {"midlands", "Midlands"}, {"the midlands", "Midlands"},
            {"north west", "North West"}, {"north-west", "North West"}, {"nw", "North West"},
            {"yorkshire & north east", "Yorkshire & North East"}, {"yorkshire and north east", "Yorkshire & North East"},
            {"yorks & ne", "Yorkshire & North East"},
            {"scotland", "Scotland"}
        }
    )
in
    Source
