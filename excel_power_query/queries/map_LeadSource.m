// Mapping table: every lead-source spelling found in the CRM export (lower-case, trimmed) -> one of 7 canonical sources.
let
    Source = #table(
        type table [raw_label = text, lead_source_clean = text],
        {
            {"web", "Web"}, {"website", "Web"},
            {"web (business)", "Web (Business)"},
            {"inbound call", "Inbound Call"}, {"inbound", "Inbound Call"},
            {"referral", "Referral"},
            {"outbound call", "Outbound Call"}, {"outbound", "Outbound Call"},
            {"door-to-door", "Door-to-Door"}, {"door to door", "Door-to-Door"}, {"d2d", "Door-to-Door"},
            {"partner", "Partner"}
        }
    )
in
    Source
