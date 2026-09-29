"""
Export Tableau-ready extracts to dashboard/tableau/.
Grain is documented per file; relationships are described in docs/tableau_build_guide.md.
Run: python src/export_tableau.py
"""
import pandas as pd, numpy as np
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]; C = ROOT/"data"/"clean"; T = ROOT/"dashboard"/"tableau"; T.mkdir(parents=True, exist_ok=True)
SQLO, OUT = ROOT/"analysis"/"sql_outputs", ROOT/"analysis"/"outputs"

o = pd.read_csv(C/"opportunities.csv", parse_dates=["close_date"])
o["reached_quote"] = o.quote_sent_date.notna().astype(int)
o["reached_credit_check"] = o.credit_check_date.notna().astype(int)
o["is_activated"] = (o.order_status == "Activated").astype(int)
o["quality_cohort"] = ((o.is_won == 1) & (o.close_date <= "2026-04-30")).astype(int)
o["list_minus_net_mrr_gbp"] = (o.list_mrr_gbp - o.mrr_gbp).round(2)
o.drop(columns=["close_year"]).to_csv(T/"fact_opportunities.csv", index=False)          # grain: 1 row per opportunity

l = pd.read_csv(C/"leads.csv"); l.to_csv(T/"fact_leads.csv", index=False)                # grain: 1 row per lead
pd.read_csv(SQLO/"04_quota_attainment__rep_month_attainment.csv").to_csv(T/"rep_month_quota.csv", index=False)  # rep x month
m = pd.read_csv(SQLO/"06_revenue_mrr_bridge__mrr_bridge.csv").merge(
    pd.read_csv(SQLO/"05_churn_retention__monthly_churn_rate.csv"), on="month")
m.to_csv(T/"monthly_mrr_churn.csv", index=False)                                           # grain: month
h = pd.read_csv(OUT/"monthly_orders.csv"); f = pd.read_csv(OUT/"orders_forecast_6m.csv")
fc = pd.concat([h.assign(type="Actual").rename(columns={"orders": "orders"})[["month", "orders", "type"]],
                f.rename(columns={"forecast_orders": "orders"}).assign(type="Forecast (Holt-Winters)")[["month", "orders", "lower_80", "upper_80", "type"]]])
fc.to_csv(T/"orders_actual_and_forecast.csv", index=False)                                 # grain: month x type
print({p.name: sum(1 for _ in open(p)) - 1 for p in T.glob("*.csv")})
