// The CRM system writes ISO dates (yyyy-mm-dd); ~2% of lead rows came from a manual UK import as dd/mm/yyyy.
// Both are parsed explicitly, so 03/04/2025 is always 3 April, never 4 March. Blank -> null.
// Anything else raises an error instead of being guessed.
(value as nullable text) as nullable date =>
let
    s = if value = null then "" else Text.Trim(value),
    Result =
        if s = "" then null
        else if Text.Length(s) = 10 and Text.Middle(s, 4, 1) = "-" then
            #date(Number.FromText(Text.Start(s, 4)), Number.FromText(Text.Middle(s, 5, 2)), Number.FromText(Text.End(s, 2)))
        else if Text.Length(s) = 10 and Text.Middle(s, 2, 1) = "/" then
            #date(Number.FromText(Text.End(s, 4)), Number.FromText(Text.Middle(s, 3, 2)), Number.FromText(Text.Start(s, 2)))
        else error Error.Record("Unrecognised date", "Expected yyyy-mm-dd or dd/mm/yyyy", s)
in
    Result
