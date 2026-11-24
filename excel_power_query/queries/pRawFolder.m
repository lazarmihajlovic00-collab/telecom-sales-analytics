// Folder that holds the raw CSV exports. Read from the named cell DataFolder on the Settings sheet,
// which works out <repo>\data\raw\ from wherever the workbook is saved (or holds a path typed in by hand).
let
    Source = Excel.CurrentWorkbook(){[Name = "DataFolder"]}[Content]{0}[Column1],
    Folder = Text.Trim(Text.From(Source)),
    WithSlash = if Text.EndsWith(Folder, "\") then Folder else Folder & "\"
in
    WithSlash
