// Reads one raw export as text columns (UTF-8, comma separated, first row = headers).
// Every column stays text here; each query types its own columns with an explicit en-US culture,
// so "25.0" parses the same on a PC with Serbian or any other regional settings.
(fileName as text) as table =>
let
    Source = Csv.Document(
        File.Contents(pRawFolder & fileName),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    PromotedHeaders = Table.PromoteHeaders(Source, [PromoteAllScalars = true])
in
    PromotedHeaders
