"""
Statistical checks, forecasting and figures for the Kestrel Fibre sales analysis.

Every headline claim in the README is produced here, with an uncertainty estimate, and
cross-checked against the SQL outputs (reconciliation step at the end).
Run:  python src/analysis.py
"""
import json, numpy as np, pandas as pd, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy import stats
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
C, OUT, FIG, SQLO = ROOT/"data"/"clean", ROOT/"analysis"/"outputs", ROOT/"analysis"/"figures", ROOT/"analysis"/"sql_outputs"
OUT.mkdir(parents=True, exist_ok=True); FIG.mkdir(parents=True, exist_ok=True)
opp = pd.read_csv(C/"opportunities.csv", parse_dates=["created_date", "close_date"])
cust = pd.read_csv(C/"customers.csv", parse_dates=["activation_date", "churn_date"])
M = {}  # metrics for README

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.spines.top": False,
                     "axes.spines.right": False, "axes.titleweight": "bold", "axes.titlesize": 11})
NAVY, TEAL, GREY, RED = "#1F3A5F", "#2A9D8F", "#B0B7C3", "#C8553D"

def wilson(k, n, z=1.96):
    if n == 0: return (np.nan, np.nan)
    p = k/n; d = 1 + z*z/n; c = (p + z*z/(2*n))/d; h = z*np.sqrt(p*(1-p)/n + z*z/(4*n*n))/d
    return c-h, c+h

def two_prop(k1, n1, k2, n2):
    """Difference in proportions with 95% Wald CI and two-sided z-test p-value."""
    p1, p2 = k1/n1, k2/n2; p = (k1+k2)/(n1+n2)
    z = (p1-p2)/np.sqrt(p*(1-p)*(1/n1+1/n2)); se = np.sqrt(p1*(1-p1)/n1 + p2*(1-p2)/n2)
    return dict(p1=p1, p2=p2, diff=p1-p2, ci_low=p1-p2-1.96*se, ci_high=p1-p2+1.96*se,
                ratio=p1/p2, p_value=2*(1-stats.norm.cdf(abs(z))))

def logit_irls(X, y, iters=25):
    """Plain logistic regression via IRLS (statsmodels not available offline). Returns coef, SE."""
    b = np.zeros(X.shape[1])
    for _ in range(iters):
        p = 1/(1+np.exp(-X@b)); W = p*(1-p)
        H = X.T @ (X*W[:, None]); b = b + np.linalg.solve(H, X.T@(y-p))
    return b, np.sqrt(np.diag(np.linalg.inv(H)))

closed = opp[opp.is_closed == 1]

# ------------------------------------------------ 1. Win rate differences across sources
ct = pd.crosstab(closed.lead_source, closed.is_won)
chi2, p, dof, _ = stats.chi2_contingency(ct)
wr = closed.groupby("lead_source").is_won.agg(["sum", "count"])
wr["win_rate"] = wr["sum"]/wr["count"]; wr[["ci_low", "ci_high"]] = [wilson(k, n) for k, n in zip(wr["sum"], wr["count"])]
wr.round(4).to_csv(OUT/"win_rate_by_source_with_ci.csv")
M["overall_win_rate"] = closed.is_won.mean(); M["win_rate_chi2_p"] = p
M["win_rate_by_source"] = wr.win_rate.round(3).to_dict()

# ------------------------------------------------ 2. Early-life churn: Door-to-Door vs other residential
el = cust[(cust.eligible_90d == 1) & (cust.segment == "Residential")]
d2d, oth = el[el.lead_source == "Door-to-Door"], el[el.lead_source != "Door-to-Door"]
t = two_prop(d2d.churned_90d.sum(), len(d2d), oth.churned_90d.sum(), len(oth))
M["early_churn_d2d"], M["early_churn_other_res"], M["early_churn_test"] = t["p1"], t["p2"], t
reasons = cust[cust.churned_90d == 1].assign(d2d=lambda x: np.where(x.lead_source == "Door-to-Door", "Door-to-Door", "Other"))
rs = pd.crosstab(reasons.churn_reason, reasons.d2d, normalize="columns").round(3)
rs.to_csv(OUT/"early_churn_reasons_d2d_vs_other.csv")
M["d2d_early_churn_reason_contract_terms_share"] = rs.loc["Did not understand contract terms", "Door-to-Door"]
M["other_early_churn_reason_contract_terms_share"] = rs.loc["Did not understand contract terms", "Other"]

# ------------------------------------------------ 3. Install wait -> cancellation (controlled)
res = opp[(opp.is_won == 1) & (opp.is_install_resolved == 1) & (opp.date_error == 0)].copy()
band = res.groupby("install_wait_band").is_cancelled_pre_install.agg(["sum", "count"])
band["rate"] = band["sum"]/band["count"]; band[["ci_low", "ci_high"]] = [wilson(k, n) for k, n in zip(band["sum"], band["count"])]
band.round(4).to_csv(OUT/"cancellation_by_wait_band_with_ci.csv")
# does the gradient survive outside the North West and outside Door-to-Door? (confounding check)
non = res[(res.region != "North West") & (res.lead_source != "Door-to-Door")]
M["cancel_by_band_excl_NW_and_D2D"] = non.groupby("install_wait_band").is_cancelled_pre_install.mean().round(3).to_dict()
X = np.column_stack([np.ones(len(res)), res.install_wait_days/7, (res.lead_source == "Door-to-Door").astype(float),
                     (res.segment == "Business").astype(float), (res.region == "North West").astype(float)])
b, se = logit_irls(X, res.is_cancelled_pre_install.values.astype(float))
M["logit_or_per_extra_week_wait"] = float(np.exp(b[1]))
M["logit_or_per_week_ci"] = [float(np.exp(b[1]-1.96*se[1])), float(np.exp(b[1]+1.96*se[1]))]
M["logit_or_north_west_after_controls"] = float(np.exp(b[4]))
M["cancel_rate_by_band"] = band.rate.round(3).to_dict()
nw = res[res.region == "North West"].assign(h=lambda x: x.close_date.dt.year.astype(str) + np.where(x.close_date.dt.month <= 6, "-H1", "-H2"))
nwh = nw.groupby("h").agg(wait=("install_wait_days", "mean"), cancel=("is_cancelled_pre_install", "mean"), n=("opp_id", "count"))
nwh.round(3).to_csv(OUT/"north_west_wait_trend.csv"); M["north_west_trend"] = nwh.round(3).to_dict()
# orders lost in the North West in the last 12 months above the region's 2024 cancellation rate
nw_base = nw[nw.close_date.dt.year == 2024].is_cancelled_pre_install.mean()
nw12 = nw[nw.close_date > "2025-08-31"]
M["nw_excess_cancellations_12m"] = float(nw12.is_cancelled_pre_install.sum() - nw_base*len(nw12))
M["nw_excess_cancelled_mrr_12m"] = float((nw12.is_cancelled_pre_install.mean() - nw_base)*nw12.mrr_gbp.sum())
M["nw_base_cancel_2024"] = nw_base; M["nw_cancel_last12"] = nw12.is_cancelled_pre_install.mean()

# ------------------------------------------------ 4. Discount: incremental win-rate lift above 10% (within source)
disc = {}
for src in ["Door-to-Door", "Web", "Inbound Call", "Outbound Call"]:
    s = closed[closed.lead_source == src]
    a, bb, hi = s[s.discount_pct == 0], s[s.discount_pct == 10], s[s.discount_pct >= 15]
    disc[src] = dict(wr0=a.is_won.mean(), wr10=bb.is_won.mean(), wr15plus=hi.is_won.mean(), n15plus=len(hi),
                     lift_0_to_10=two_prop(bb.is_won.sum(), len(bb), a.is_won.sum(), len(a)),
                     lift_10_to_15plus=two_prop(hi.is_won.sum(), len(hi), bb.is_won.sum(), len(bb)))
M["discount"] = disc
w12 = opp[(opp.is_won == 1) & (opp.close_date > "2025-08-31")]
M["annual_cost_discounts_15plus"] = float(((w12.list_mrr_gbp - w12.mrr_gbp)*12)[w12.discount_pct >= 15].sum())
# cost of capping at 10%: MRR given away above 10% (i.e. the part of the discount beyond 10 points)
extra = (w12.discount_pct.clip(lower=10) - 10)/100*w12.list_mrr_gbp*12
M["annual_saving_if_capped_at_10"] = float(extra.sum())

# ------------------------------------------------ 5. Rep ramp
rr = closed.groupby(["channel", "rep_ramp_status"]).is_won.mean().unstack()
rr["ratio_new_vs_ramped"] = rr["0-3 months"]/rr["6+ months"]; rr.round(3).to_csv(OUT/"ramp_effect.csv")
M["ramp_ratio_by_channel"] = rr.ratio_new_vs_ramped.round(3).to_dict()
tot = closed.groupby(closed.rep_ramp_status == "0-3 months").is_won.agg(["sum", "count"])
M["ramp_test"] = two_prop(tot.loc[True, "sum"], tot.loc[True, "count"], tot.loc[False, "sum"], tot.loc[False, "count"])

# ------------------------------------------------ 6. Quota vs quality
tq = pd.read_csv(SQLO/"04_quota_attainment__team_sale_quality.csv").set_index("team")
M["retained_90d_share_by_team"] = tq.pct_ordered_mrr_retained_90d.to_dict()
ta = pd.read_csv(SQLO/"04_quota_attainment__team_year_attainment.csv")
M["attainment_2026"] = ta[ta.year == 2026].set_index("team").attainment.to_dict()
M["attainment_2025"] = ta[ta.year == 2025].set_index("team").attainment.to_dict()

# ------------------------------------------------ 7. Forecast monthly orders (backtest 3 methods)
ts = opp[opp.is_won == 1].groupby("close_month").size()
ts.index = pd.PeriodIndex(ts.index, freq="M"); ts = ts.reindex(pd.period_range("2024-01", "2026-08", freq="M"), fill_value=0)
# Jan-2024 is a WARM-UP artefact: the extract starts at lead creation on 2024-01-01, so the pipeline
# starts empty and January orders are understated. It is excluded from all time-series modelling.
ts_all = ts.copy(); ts = ts[ts.index > pd.Period("2024-01", "M")]
H = 6; train, test = ts[:-H], ts[-H:]

def seasonal_naive(y, h):
    return np.array([y.iloc[-12 + (i % 12)] for i in range(h)], dtype=float)

def decomp_trend(y, h):
    """Linear trend x multiplicative monthly index. Index = mean over complete years of month / that year's mean.
       Chosen partly because it can be rebuilt transparently in Excel (see Forecast sheet)."""
    df = pd.DataFrame({"y": y.values, "yr": y.index.year, "mo": y.index.month})
    full = df.groupby("yr").filter(lambda g: len(g) >= 11)   # 2024 has 11 usable months (Jan excluded)
    full = full.assign(r=full.y / full.groupby("yr").y.transform("mean"))
    idx = full.groupby("mo").r.mean(); idx = idx/idx.mean()
    des = df.y/df.mo.map(idx); t = np.arange(len(df))
    slope, icpt = np.polyfit(t, des, 1)
    fut = [(y.index[-1] + i + 1).month for i in range(h)]
    return np.array([(icpt + slope*(len(df)+i))*idx[m] for i, m in enumerate(fut)]), idx, slope, icpt

def holt_winters(y, h, season=12):
    """Additive Holt-Winters, parameters chosen by grid search on in-sample one-step SSE."""
    y = y.values.astype(float); best = None
    for a in np.linspace(.05, .6, 12):
        for b_ in [0, .02, .05, .1]:
            for g in np.linspace(.05, .5, 10):
                L, T = y[:season].mean(), (y[season:2*season].mean() - y[:season].mean())/season
                S = list(y[:season] - L); sse = 0
                for i in range(season, len(y)):
                    f = L + T + S[i-season]; sse += (y[i]-f)**2
                    Ln = a*(y[i]-S[i-season]) + (1-a)*(L+T); T = b_*(Ln-L) + (1-b_)*T
                    S.append(g*(y[i]-Ln) + (1-g)*S[i-season]); L = Ln
                if best is None or sse < best[0]: best = (sse, L, T, S, (a, b_, g))
    _, L, T, S, prm = best
    return np.array([L + (i+1)*T + S[len(S)-season + (i % season)] for i in range(h)]), prm

fc = {"Seasonal naive": seasonal_naive(train, H), "Trend x seasonal index": decomp_trend(train, H)[0],
      "Holt-Winters (additive)": holt_winters(train, H)[0]}
bt = pd.DataFrame({k: dict(MAE=np.mean(np.abs(v-test.values)), MAPE=np.mean(np.abs(v-test.values)/test.values),
                            RMSE=np.sqrt(np.mean((v-test.values)**2)), bias=np.mean(v-test.values)) for k, v in fc.items()}).T
bt.round(3).to_csv(OUT/"forecast_backtest.csv"); M["forecast_backtest"] = bt.round(3).to_dict(orient="index")
best = bt.MAPE.idxmin(); M["forecast_best_method"] = best
full_fc = {"Seasonal naive": seasonal_naive(ts, H), "Trend x seasonal index": decomp_trend(ts, H)[0],
           "Holt-Winters (additive)": holt_winters(ts, H)[0]}[best]
_, idx_full, slope_full, icpt_full = decomp_trend(ts, H)
rmse = bt.loc[best, "RMSE"]
fut_idx = pd.period_range("2026-09", periods=H, freq="M")
avg_mrr = opp[(opp.is_won == 1) & (opp.close_date > "2026-02-28")].mrr_gbp.mean()
fdf = pd.DataFrame({"month": fut_idx.astype(str), "forecast_orders": full_fc.round(0),
                    "lower_80": (full_fc - 1.2816*rmse).round(0), "upper_80": (full_fc + 1.2816*rmse).round(0),
                    "implied_ordered_mrr_gbp": (full_fc*avg_mrr).round(0)})
fdf.to_csv(OUT/"orders_forecast_6m.csv", index=False)
M["forecast"] = fdf.to_dict(orient="records"); M["forecast_avg_mrr_per_order"] = avg_mrr
M["seasonal_index"] = idx_full.round(3).to_dict(); M["trend_slope_orders_per_month"] = slope_full
M["orders_last_6m"] = int(ts[-6:].sum()); M["forecast_next_6m_total"] = float(full_fc.sum())
ts_all.rename("orders").to_frame().assign(used_in_model=lambda d: (d.index > pd.Period("2024-01", "M")).astype(int)).assign(month=lambda d: d.index.astype(str)).to_csv(OUT/"monthly_orders.csv", index=False)

# ------------------------------------------------ Figures
fig, ax = plt.subplots(figsize=(8, 4))
f = pd.read_csv(SQLO/"02_funnel_conversion__funnel_by_source.csv").set_index("lead_source").sort_values("lead_to_order_rate")
yy = np.arange(len(f)); ax.barh(yy-.2, f.lead_to_opp_rate, .4, color=GREY, label="Lead → opportunity")
ax.barh(yy+.2, f.win_rate, .4, color=NAVY, label="Win rate (won / closed)")
ax.set_yticks(yy, f.index); ax.xaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1))
for i, (a, b_) in enumerate(zip(f.lead_to_opp_rate, f.win_rate)):
    ax.text(a+.005, i-.2, f"{a:.0%}", va="center", fontsize=8); ax.text(b_+.005, i+.2, f"{b_:.0%}", va="center", fontsize=8)
ax.set_title("Conversion differs by source at different stages"); ax.legend(frameon=False, loc="lower right")
fig.tight_layout(); fig.savefig(FIG/"01_funnel_by_source.png", dpi=160); plt.close()

fig, ax = plt.subplots(figsize=(8, 4))
tq2 = tq.sort_values("pct_ordered_mrr_retained_90d")
ax.bar(tq2.index, tq2.pct_ordered_mrr_retained_90d, color=[RED if "Field" in i else NAVY for i in tq2.index])
ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1)); ax.set_ylim(.6, 1)
for i, v in enumerate(tq2.pct_ordered_mrr_retained_90d): ax.text(i, v+.005, f"{v:.0%}", ha="center")
ax.set_title("Share of ordered MRR still billing 90 days later (orders Jan-24 to Apr-26)")
plt.xticks(rotation=12); fig.tight_layout(); fig.savefig(FIG/"02_sale_quality_by_team.png", dpi=160); plt.close()

fig, axs = plt.subplots(1, 2, figsize=(10, 4))
ax = axs[0]; ax.bar(band.index, band.rate, color=[NAVY, NAVY, RED, RED],
                    yerr=[band.rate-band.ci_low, band.ci_high-band.rate], capsize=4)
ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1)); ax.set_title("Pre-install cancellation by install wait")
for i, v in enumerate(band.rate): ax.text(i, v+.03, f"{v:.0%}\n(n={band['count'].iloc[i]:,})", ha="center", fontsize=8)
ax.set_ylim(0, .32)
ax = axs[1]; ax2 = ax.twinx()
ax.plot(nwh.index, nwh.wait, marker="o", color=NAVY, label="Avg wait (days)"); ax.set_ylabel("Avg install wait (days)")
ax2.plot(nwh.index, nwh.cancel, marker="s", color=RED, label="Cancellation rate"); ax2.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1))
ax2.spines["right"].set_visible(True); ax.set_title("North West: waits and cancellations rising")
ax.tick_params(axis="x", rotation=30); fig.legend(frameon=False, loc="upper right", bbox_to_anchor=(.98, .88), fontsize=8)
fig.tight_layout(); fig.savefig(FIG/"03_install_wait_cancellation.png", dpi=160); plt.close()

fig, ax = plt.subplots(figsize=(8, 4))
e = cust[cust.eligible_90d == 1].groupby("lead_source").churned_90d.agg(["sum", "count"])
e["r"] = e["sum"]/e["count"]; e[["lo", "hi"]] = [wilson(k, n) for k, n in zip(e["sum"], e["count"])]; e = e.sort_values("r")
ax.barh(e.index, e.r, xerr=[e.r-e.lo, e.hi-e.r], color=[RED if i == "Door-to-Door" else NAVY for i in e.index], capsize=3)
ax.xaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1)); ax.set_title("Churn within 90 days of activation (95% CI)")
fig.tight_layout(); fig.savefig(FIG/"04_early_life_churn.png", dpi=160); plt.close()

fig, ax = plt.subplots(figsize=(8, 4))
for src, col in [("Door-to-Door", RED), ("Web", NAVY), ("Inbound Call", TEAL), ("Outbound Call", GREY)]:
    s = closed[closed.lead_source == src].groupby("discount_pct").is_won.agg(["mean", "count"]); s = s[s["count"] >= 100]
    ax.plot(s.index, s["mean"], marker="o", color=col, label=src)
ax.set_xticks([0, 5, 10, 15, 20], ["0%", "5%", "10%", "15%", "20%"]); ax.yaxis.set_major_formatter(matplotlib.ticker.PercentFormatter(1))
ax.axvspan(12.5, 21, color=GREY, alpha=.2); ax.text(13, ax.get_ylim()[1]*.97, "no further lift", fontsize=8, va="top")
ax.set_xlabel("Discount off list MRR"); ax.set_title("Win rate by discount level, within source (cells n ≥ 100)")
ax.legend(frameon=False, ncol=4, fontsize=8, loc="lower center", bbox_to_anchor=(.5, -.35))
fig.tight_layout(); fig.savefig(FIG/"05_discount_win_rate.png", dpi=160); plt.close()

fig, ax = plt.subplots(figsize=(9, 4))
x = ts_all.index.to_timestamp(); ax.plot(x, ts_all.values, color=NAVY, marker="o", ms=3, label="Actual orders")
ax.plot(test.index.to_timestamp(), fc[best], color=TEAL, ls="--", marker="x", label=f"Backtest: {best}")
fx = fut_idx.to_timestamp(); ax.plot(fx, fdf.forecast_orders, color=RED, marker="o", ms=3, label="Forecast")
ax.fill_between(fx, fdf.lower_80, fdf.upper_80, color=RED, alpha=.15, label="~80% interval")
ax.set_title("Monthly orders: 6-month backtest and forecast"); ax.legend(frameon=False, fontsize=8, ncol=2)
fig.tight_layout(); fig.savefig(FIG/"06_orders_forecast.png", dpi=160); plt.close()

# ------------------------------------------------ Reconciliation: pandas vs SQL must agree
sq = pd.read_csv(SQLO/"03_win_rate_cycle_deal_size__channel_kpis.csv").set_index("lead_source")
assert np.allclose(sq.win_rate, wr.win_rate.reindex(sq.index).round(3), atol=.0011), "SQL/pandas win rate mismatch"
se_ = pd.read_csv(SQLO/"05_churn_retention__early_life_churn_by_source.csv").set_index("lead_source")
assert np.allclose(se_.early_life_churn_rate, e.r.reindex(se_.index).round(3), atol=.0011), "SQL/pandas churn mismatch"
M["reconciliation"] = "passed: SQL and pandas agree on win rate and early-life churn for every source"

def conv(o):
    if isinstance(o, dict): return {str(k): conv(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)): return [conv(v) for v in o]
    if isinstance(o, (np.floating, float)): return round(float(o), 4)
    if isinstance(o, (np.integer,)): return int(o)
    return o
json.dump(conv(M), open(OUT/"key_metrics.json", "w"), indent=2)
print(json.dumps(conv(M), indent=1))
