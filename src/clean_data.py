"""
Clean the raw CRM / billing / HR exports into analysis-ready tables.

Principle: never silently "fix" a value we cannot verify. Every rule below either
(a) standardises something unambiguous, (b) recovers a value from another trusted field,
or (c) FLAGS the record and excludes it only from the metric it would distort.
Every rule and its row count is written to docs/data_quality_log.md.

Run:  python src/clean_data.py
"""
import numpy as np, pandas as pd
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW, CLEAN = ROOT / "data" / "raw", ROOT / "data" / "clean"; CLEAN.mkdir(parents=True, exist_ok=True)
AS_OF = pd.Timestamp("2026-08-31")
log = []
def note(table, rule, n, action): log.append((table, rule, int(n), action))

def parse_dates(s):
    """ISO (yyyy-mm-dd) is the system format; ~2% of lead rows arrive as dd/mm/yyyy from a manual import."""
    s = s.fillna("").astype(str).str.strip()
    iso = pd.to_datetime(s.where(s.str.match(r"^\d{4}-\d{2}-\d{2}$")), format="%Y-%m-%d", errors="coerce")
    uk = pd.to_datetime(s.where(s.str.match(r"^\d{2}/\d{2}/\d{4}$")), format="%d/%m/%Y", errors="coerce")
    return iso.fillna(uk), int(s.str.match(r"^\d{2}/\d{2}/\d{4}$").sum())

REGION_MAP = {"london": "London", "greater london": "London", "south east": "South East", "south-east": "South East",
              "se": "South East", "midlands": "Midlands", "the midlands": "Midlands", "north west": "North West",
              "north-west": "North West", "nw": "North West", "yorkshire & north east": "Yorkshire & North East",
              "yorkshire and north east": "Yorkshire & North East", "yorks & ne": "Yorkshire & North East",
              "scotland": "Scotland"}
SOURCE_MAP = {"web": "Web", "website": "Web", "web (business)": "Web (Business)", "inbound call": "Inbound Call",
              "inbound": "Inbound Call", "referral": "Referral", "outbound call": "Outbound Call", "outbound": "Outbound Call",
              "door-to-door": "Door-to-Door", "door to door": "Door-to-Door", "d2d": "Door-to-Door", "partner": "Partner"}

# ------------------------------------------------------------------ reps
reps = pd.read_csv(RAW / "hr_sales_reps.csv")
test_reps = reps.rep_id.eq("R999") | reps.team.eq("Test")
note("reps", "Test/system user (R999 'Test User')", test_reps.sum(), "removed")
reps = reps[~test_reps].copy()
for c in ["hire_date", "leave_date"]: reps[c], _ = parse_dates(reps[c])

# ------------------------------------------------------------------ leads
leads = pd.read_csv(RAW / "crm_leads_export.csv", dtype=str)
n0 = len(leads)
dups = leads.duplicated(); note("leads", "Exact duplicate rows (double export)", dups.sum(), "removed")
leads = leads[~dups]
test = leads.lead_id.str.contains("TEST") | leads.assigned_rep_id.eq("R999") | leads.region.eq("Test")
note("leads", "Test records (lead_id contains TEST / rep R999)", test.sum(), "removed")
leads = leads[~test].copy()
leads["created_date"], n_uk = parse_dates(leads.created_date)
note("leads", "created_date in dd/mm/yyyy format", n_uk, "parsed explicitly as day-first (UK import)")
raw_reg = leads.region.str.strip().str.lower()
note("leads", "Non-standard region labels (case/spelling/abbreviation)", (leads.region != raw_reg.map(REGION_MAP)).sum(),
     "mapped to 6 canonical regions")
leads["region"] = raw_reg.map(REGION_MAP)
raw_src = leads.lead_source.str.strip().str.lower()
note("leads", "Non-standard lead_source labels", (leads.lead_source != raw_src.map(SOURCE_MAP)).sum(),
     "mapped to 7 canonical sources")
leads["lead_source"] = raw_src.map(SOURCE_MAP)
assert leads.region.notna().all() and leads.lead_source.notna().all(), "unmapped label - extend the maps"
assert leads.lead_id.is_unique
leads["lead_month"] = leads.created_date.dt.to_period("M").astype(str)
leads["is_converted"] = (leads.lead_status == "Converted").astype(int)

# ------------------------------------------------------------------ products
products = pd.read_csv(RAW / "product_catalogue.csv")

# ------------------------------------------------------------------ opportunities
opp = pd.read_csv(RAW / "crm_opportunities_export.csv", dtype=str)
test = opp.opp_id.str.contains("TEST") | opp.rep_id.eq("R999")
note("opportunities", "Test records", test.sum(), "removed"); opp = opp[~test].copy()
dups = opp.opp_id.duplicated(); note("opportunities", "Duplicate opp_id", dups.sum(), "removed"); opp = opp[~dups]
date_cols = ["created_date", "quote_sent_date", "credit_check_date", "close_date", "install_date", "cancel_date", "activation_date"]
for c in date_cols: opp[c], _ = parse_dates(opp[c])
cur = opp.mrr_gbp.str.contains("£", na=False)
note("opportunities", "mrr_gbp stored as text with '£' symbol", cur.sum(), "stripped symbol, cast to numeric")
opp["mrr_gbp"] = pd.to_numeric(opp.mrr_gbp.str.replace("£", "", regex=False))
pmap = {n.lower(): n for n in products.product_name}
note("opportunities", "product_name casing inconsistent with catalogue", (opp.product_name != opp.product_name.str.lower().map(pmap)).sum(),
     "matched to catalogue case-insensitively")
opp["product_name"] = opp.product_name.str.lower().map(pmap)
opp = opp.merge(products, on="product_name", how="left")
opp["contract_months"] = pd.to_numeric(opp.contract_months).astype(int)
opp["discount_pct"] = pd.to_numeric(opp.discount_pct)
bad_disc = ~opp.discount_pct.between(0, 50)
recovered = ((1 - opp.mrr_gbp / opp.list_mrr_gbp) * 100).round().astype(int)
note("opportunities", "discount_pct outside 0-50% (e.g. 150, -10, 100)", bad_disc.sum(),
     "recovered from list price vs net MRR: discount = 1 - mrr/list (exact for every row where it was checked)")
assert (recovered[~bad_disc] == opp.discount_pct[~bad_disc]).all(), "recovery rule does not hold on valid rows"
opp.loc[bad_disc, "discount_pct"] = recovered[bad_disc]
opp["discount_pct"] = opp.discount_pct.astype(int)
miss = opp.outcome.eq("Lost") & opp.lost_reason.isna()
note("opportunities", "Lost opportunities with blank lost_reason", miss.sum(), "set to 'Not recorded' (kept in all rate metrics)")
opp.loc[miss, "lost_reason"] = "Not recorded"
opp["date_error"] = (opp.close_date < opp.created_date).astype(int)
note("opportunities", "close_date earlier than created_date", opp.date_error.sum(),
     "FLAGGED date_error=1; kept for win/loss counts, excluded from sales-cycle metrics (true date unknown)")

# enrich with lead + rep attributes
opp = opp.merge(leads[["lead_id", "lead_source", "segment", "region"]], on="lead_id", how="left", suffixes=("_product", ""))
orph = opp.lead_source.isna(); note("opportunities", "Opportunity without a matching lead", orph.sum(), "removed")
opp = opp[~orph]
opp = opp.merge(reps[["rep_id", "team", "channel", "hire_date"]], on="rep_id", how="left")
opp["is_closed"] = opp.outcome.isin(["Won", "Lost"]).astype(int)
opp["is_won"] = opp.outcome.eq("Won").astype(int)
opp["created_month"] = opp.created_date.dt.to_period("M").astype(str)
opp["close_month"] = opp.close_date.dt.to_period("M").astype(str).replace("NaT", "")
opp["close_year"] = opp.close_date.dt.year.astype("Int64")
opp["sales_cycle_days"] = np.where(opp.date_error.eq(0) & opp.close_date.notna(),
                                   (opp.close_date - opp.created_date).dt.days, np.nan)
opp["rep_tenure_days"] = (opp.created_date - opp.hire_date).dt.days
opp["rep_ramp_status"] = pd.cut(opp.rep_tenure_days, [-1, 89, 179, 10**5], labels=["0-3 months", "3-6 months", "6+ months"]).astype(str)
opp["discount_band"] = opp.discount_pct.map(lambda d: f"{d}%")
opp["tcv_gbp"] = (opp.mrr_gbp * opp.contract_months).round(2)
opp["install_wait_days"] = (opp.install_date - opp.close_date).dt.days.where(opp.is_won.eq(1) & opp.date_error.eq(0))
opp["install_wait_band"] = pd.cut(opp.install_wait_days, [-1, 14, 21, 28, 999],
                                  labels=["0-14 days", "15-21 days", "22-28 days", "29+ days"]).astype(str).replace("nan", "")
opp["is_cancelled_pre_install"] = opp.order_status.eq("Cancelled before install").astype(int)
opp["is_install_resolved"] = opp.order_status.isin(["Activated", "Cancelled before install"]).astype(int)

# ------------------------------------------------------------------ customers
cust = pd.read_csv(RAW / "billing_customers_export.csv", dtype=str)
dups = cust.duplicated(); note("customers", "Exact duplicate rows", dups.sum(), "removed"); cust = cust[~dups].copy()
for c in ["activation_date", "churn_date"]: cust[c], _ = parse_dates(cust[c])
cust["mrr_gbp"] = pd.to_numeric(cust.mrr_gbp); cust["contract_months"] = pd.to_numeric(cust.contract_months).astype(int)
badc = cust.churn_date < cust.activation_date
note("customers", "churn_date earlier than activation_date", badc.sum(),
     "FLAGGED churn_date_error=1; excluded from churn/retention metrics (cannot tell which date is wrong)")
cust["churn_date_error"] = badc.astype(int)
cust = cust.merge(opp[["opp_id", "lead_source", "segment", "region", "team", "channel", "rep_id", "discount_pct",
                       "product_name"]], on="opp_id", how="left")
cust["is_churned"] = cust.churn_date.notna().astype(int)
cust["tenure_days"] = ((cust.churn_date.fillna(AS_OF)) - cust.activation_date).dt.days
cust["activation_month"] = cust.activation_date.dt.to_period("M").astype(str)
cust["churn_month"] = cust.churn_date.dt.to_period("M").astype(str).replace("NaT", "")
# early-life churn: only customers activated >= 90 days before snapshot are ELIGIBLE (right-censoring)
cust["eligible_90d"] = ((AS_OF - cust.activation_date).dt.days >= 90).astype(int) * (1 - cust.churn_date_error)
cust["churned_90d"] = (cust.eligible_90d.eq(1) & cust.is_churned.eq(1) & (cust.tenure_days < 90)).astype(int)
opp = opp.merge(cust[["opp_id", "customer_id", "churn_date", "eligible_90d", "churned_90d"]], on="opp_id", how="left")
opp["retained_90d_mrr"] = np.where(opp.eligible_90d.eq(1) & opp.churned_90d.eq(0), opp.mrr_gbp, 0.0)

# ------------------------------------------------------------------ quotas
quotas = pd.read_csv(RAW / "sales_quotas.csv")
quotas = quotas.merge(reps[["rep_id", "rep_name", "team", "channel"]], on="rep_id", how="left")

# ------------------------------------------------------------------ write
out_opp_cols = ["opp_id", "lead_id", "rep_id", "team", "channel", "lead_source", "segment", "region", "product_id",
                "product_name", "list_mrr_gbp", "discount_pct", "discount_band", "mrr_gbp", "contract_months", "tcv_gbp",
                "created_date", "quote_sent_date", "credit_check_date", "close_date", "created_month", "close_month",
                "close_year", "outcome", "stage", "lost_reason", "is_closed", "is_won", "date_error", "sales_cycle_days",
                "rep_tenure_days", "rep_ramp_status", "install_date", "install_wait_days", "install_wait_band",
                "order_status", "is_install_resolved", "is_cancelled_pre_install", "cancel_date", "activation_date",
                "customer_id", "churn_date", "eligible_90d", "churned_90d", "retained_90d_mrr"]
opp = opp[out_opp_cols]
for df in [opp, cust, leads, reps]:
    for c in df.columns:
        if pd.api.types.is_datetime64_any_dtype(df[c]): df[c] = df[c].dt.strftime("%Y-%m-%d")
leads.to_csv(CLEAN / "leads.csv", index=False)
opp.to_csv(CLEAN / "opportunities.csv", index=False)
cust.to_csv(CLEAN / "customers.csv", index=False)
reps.to_csv(CLEAN / "reps.csv", index=False)
products.to_csv(CLEAN / "products.csv", index=False)
quotas.to_csv(CLEAN / "quotas.csv", index=False)

with open(ROOT / "docs" / "data_quality_log.md", "w") as f:
    f.write("# Data Quality Log\n\nGenerated by `src/clean_data.py`. Snapshot date: 2026-08-31.\n\n"
            "| Table | Issue found | Rows | Action taken |\n|---|---|---:|---|\n")
    for t, r, n, a in log: f.write(f"| {t} | {r} | {n:,} | {a} |\n")
    f.write(f"\n**Final row counts:** leads {len(leads):,} · opportunities {len(opp):,} · customers {len(cust):,} · "
            f"reps {len(reps):,} · quota rows {len(quotas):,}\n")
for r in log: print(r)
print(len(leads), len(opp), len(cust), len(reps))
