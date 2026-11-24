// HR export of sales reps, without the system test user.
let
    Source = fnReadCsv("hr_sales_reps.csv"),
    RemovedTestUser = Table.SelectRows(Source, each [rep_id] <> "R999" and [team] <> "Test"),
    ParsedDates = Table.TransformColumns(
        RemovedTestUser,
        {{"hire_date", fnParseDate, type nullable date}, {"leave_date", fnParseDate, type nullable date}}
    )
in
    ParsedDates
