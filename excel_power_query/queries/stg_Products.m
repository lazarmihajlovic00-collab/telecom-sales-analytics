// Product catalogue, with a lower-case key so CRM product names can be matched regardless of casing.
let
    Source = fnReadCsv("product_catalogue.csv"),
    TypedPrice = Table.TransformColumnTypes(Source, {{"list_mrr_gbp", type number}}, "en-US"),
    AddedKey = Table.AddColumn(TypedPrice, "product_key", each Text.Lower([product_name]), type text)
in
    AddedKey
