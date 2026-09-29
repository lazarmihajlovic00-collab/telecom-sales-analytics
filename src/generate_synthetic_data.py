"""
Generate SYNTHETIC CRM-style data for a fictional UK full-fibre broadband provider
("Kestrel Fibre" - not a real company).

Every behavioural assumption encoded here is documented in docs/synthetic_data_design.md.
The raw files deliberately contain data-quality defects (duplicates, inconsistent labels,
mixed date formats, currency strings, test records, impossible dates) so that the
cleaning step in src/clean_data.py has real work to do.

Run:  python src/generate_synthetic_data.py      (seed fixed -> fully reproducible)
"""
import numpy as np, pandas as pd
from pathlib import Path

rng = np.random.default_rng(20260929)
ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"; RAW.mkdir(parents=True, exist_ok=True)

START, AS_OF = pd.Timestamp("2024-01-01"), pd.Timestamp("2026-08-31")
MONTHS = pd.period_range("2024-01", "2026-08", freq="M")

REGION_W = {"London": .26, "South East": .18, "Midlands": .16, "North West": .16,
            "Yorkshire & North East": .14, "Scotland": .10}
FIELD_TEAM = {"London": "Field South", "South East": "Field South", "Midlands": "Field South",
              "North West": "Field North", "Yorkshire & North East": "Field North", "Scotland": "Field North"}

TEAMS = {"Telesales Inbound": ("Telesales", 8), "Telesales Outbound": ("Telesales", 5),
         "Field North": ("Field Sales", 5), "Field South": ("Field Sales", 5),
         "Business Development": ("Business Development", 3)}
VOL_SCALE = 1.5

# ---------------- products ----------------
products = pd.DataFrame([
    ("P01", "Fibre 150", "Residential", 25.0), ("P02", "Fibre 500", "Residential", 32.0),
    ("P03", "Fibre 1000", "Residential", 42.0), ("P04", "Fibre 3000", "Residential", 60.0),
    ("P11", "Business Fibre 500", "Business", 45.0), ("P12", "Business Fibre 1000", "Business", 65.0),
    ("P13", "Business Leased Line 1G", "Business", 250.0)],
    columns=["product_id", "product_name", "segment", "list_mrr_gbp"])
RES_MIX = {"P01": .30, "P02": .40, "P03": .22, "P04": .08}
D2D_MIX = {"P01": .15, "P02": .45, "P03": .30, "P04": .10}
BUS_MIX = {"P11": .40, "P12": .45, "P13": .15}
LIST = dict(zip(products.product_id, products.list_mrr_gbp))

# ---------------- reps (with attrition + replacement hires) ----------------
FIRST = ["Amelia","Oliver","Isla","Jack","Ava","Harry","Mia","George","Sophie","Noah","Grace","Leo",
         "Chloe","Oscar","Ella","Charlie","Lily","Jacob","Emily","Thomas","Freya","James","Ruby","Alfie",
         "Evie","Joshua","Poppy","William","Daisy","Henry","Zara","Ethan","Hannah","Samuel","Layla","Daniel"]
reps, rid = [], [1]
def new_rep(team, hire):
    r = dict(rep_id=f"R{rid[0]:03d}", rep_name=f"{rng.choice(FIRST)} {chr(65 + rng.integers(0, 26))}.",
             team=team, channel=TEAMS[team][0], hire_date=hire, leave_date=pd.NaT,
             skill=float(np.clip(rng.normal(1, .10), .75, 1.25)))
    rid[0] += 1; reps.append(r); return r

for team, (_, n) in TEAMS.items():
    active = [new_rep(team, START - pd.Timedelta(days=int(rng.integers(120, 900)))) for _ in range(n)]
    for m in MONTHS:
        for r in list(active):
            if rng.random() < 0.025:                      # ~26% annual attrition
                leave = max(m.start_time + pd.Timedelta(days=int(rng.integers(0, 28))),
                            r["hire_date"] + pd.Timedelta(days=60))
                if leave > AS_OF: continue
                r["leave_date"] = leave; active.remove(r)
                hire = leave + pd.Timedelta(days=int(rng.integers(14, 45)))
                if hire <= AS_OF: active.append(new_rep(team, hire))
reps_df = pd.DataFrame(reps)

def active_reps(team, d):
    return reps_df[(reps_df.team == team) & (reps_df.hire_date <= d) &
                   (reps_df.leave_date.isna() | (reps_df.leave_date > d))]
SKILL = dict(zip(reps_df.rep_id, reps_df.skill)); HIRE = dict(zip(reps_df.rep_id, reps_df.hire_date))

# ---------------- behavioural parameters (see docs/synthetic_data_design.md) ----------------
SEASON = [1.10, 1.05, 1.08, .98, .97, .95, .92, .85, 1.10, 1.08, 1.00, .80]
SEASON_D2D = [.80, .85, .95, 1.05, 1.10, 1.10, 1.05, .95, 1.05, 1.00, .90, .70]  # weather-driven
SRC = {  # base leads/month, monthly growth, lead->opp conv, base win prob, median cycle days, owning team
 "Web":            dict(vol=400, g=.012, conv=.38, win=.34, cyc=5,  team="Telesales Inbound"),
 "Web (Business)": dict(vol=35,  g=.010, conv=.45, win=.28, cyc=21, team="Business Development"),
 "Inbound Call":   dict(vol=170, g=.005, conv=.60, win=.42, cyc=3,  team="Telesales Inbound"),
 "Referral":       dict(vol=55,  g=.015, conv=.62, win=.55, cyc=4,  team="Telesales Inbound"),
 "Outbound Call":  dict(vol=600, g=-.008,conv=.16, win=.22, cyc=8,  team="Telesales Outbound"),
 "Door-to-Door":   dict(vol=270, g=.003, conv=.55, win=.42, cyc=.6, team=None),
 "Partner":        dict(vol=35,  g=.010, conv=.50, win=.30, cyc=28, team="Business Development"),
}
DISC_LEVELS = [0, 5, 10, 15, 20]
DISC_P = {"Web": [.60,.20,.15,.04,.01], "Web (Business)": [.30,.25,.25,.15,.05],
          "Inbound Call": [.50,.25,.20,.04,.01], "Referral": [.70,.20,.10,0,0],
          "Outbound Call": [.30,.30,.25,.10,.05], "Door-to-Door": [.20,.20,.25,.20,.15],
          "Partner": [.30,.25,.25,.15,.05]}
DISC_MULT = {0: 1.00, 5: 1.08, 10: 1.15, 15: 1.16, 20: 1.16}   # lift plateaus after 10%
LOST_STAGE_P = {"Door-to-Door": [.15,.40,.45], "Outbound Call": [.35,.55,.10]}
STAGES = ["Qualified", "Quote Sent", "Credit Check"]
LOST_REASON = {"Qualified": ["No response","Not serviceable at address","Price"],
               "Quote Sent": ["Price","Chose competitor","No response","Contract length"],
               "Credit Check": ["Failed credit check","Customer withdrew"]}
BASE_WAIT = {"London": 9, "South East": 11, "Midlands": 12, "North West": 13,
             "Yorkshire & North East": 13, "Scotland": 15}

def ramp_mult(tenure_days):
    return .72 if tenure_days < 90 else (.88 if tenure_days < 180 else 1.0)

leads, opps, custs = [], [], []
lid = oid = cid = 0
for m in MONTHS:
    k = (m - MONTHS[0]).n
    for src, p in SRC.items():
        season = SEASON_D2D if src == "Door-to-Door" else SEASON
        n = rng.poisson(VOL_SCALE * p["vol"] * season[m.month - 1] * (1 + p["g"]) ** k)
        days = rng.integers(0, m.days_in_month, n)
        for dd in days:
            d = m.start_time + pd.Timedelta(days=int(dd))
            if d > AS_OF: continue
            region = rng.choice(list(REGION_W), p=list(REGION_W.values()))
            team = FIELD_TEAM[region] if src == "Door-to-Door" else p["team"]
            pool = active_reps(team, d)
            rep = pool.rep_id.iloc[rng.integers(0, len(pool))] if len(pool) else None
            segment = "Business" if team == "Business Development" else "Residential"
            lid += 1; lead_id = f"L{lid:06d}"
            converted = rng.random() < p["conv"]
            status = "Converted" if converted else ("Open" if (AS_OF - d).days < 7 else
                     rng.choice(["Disqualified", "Unworked"], p=[.8, .2]))
            leads.append(dict(lead_id=lead_id, created_date=d, lead_source=src, segment=segment,
                              region=region, assigned_rep_id=rep, lead_status=status))
            if not converted or rep is None: continue
            # ---- opportunity ----
            c_date = d + pd.Timedelta(days=0 if src == "Door-to-Door" else int(rng.geometric(.5) - 1))
            if c_date > AS_OF: c_date = AS_OF
            mix = BUS_MIX if segment == "Business" else (D2D_MIX if src == "Door-to-Door" else RES_MIX)
            prod = rng.choice(list(mix), p=list(mix.values()))
            disc = int(rng.choice(DISC_LEVELS, p=DISC_P[src]))
            contract = int(rng.choice([36, 24], p=[.5, .5])) if segment == "Business" else int(rng.choice([24, 12], p=[.7, .3]))
            mrr = round(LIST[prod] * (1 - disc / 100), 2)
            tenure = (c_date - HIRE[rep]).days
            pwin = np.clip(p["win"] * DISC_MULT[disc] * ramp_mult(tenure) * SKILL[rep], .02, .9)
            won = rng.random() < pwin
            cyc = max(0, int(round(rng.lognormal(np.log(p["cyc"]), .6) * (1 if won else 1.6))))
            close = c_date + pd.Timedelta(days=cyc)
            oid += 1; opp_id = f"O{oid:06d}"
            o = dict(opp_id=opp_id, lead_id=lead_id, rep_id=rep, product_id=prod, created_date=c_date,
                     contract_months=contract, discount_pct=disc, mrr_gbp=mrr,
                     quote_sent_date=pd.NaT, credit_check_date=pd.NaT, close_date=pd.NaT,
                     outcome=None, stage=None, lost_reason=None,
                     install_date=pd.NaT, order_status=None, cancel_date=pd.NaT, activation_date=pd.NaT)
            reached = 3 if won else int(rng.choice([0, 1, 2], p=LOST_STAGE_P.get(src, [.30, .50, .20])))
            if reached >= 1: o["quote_sent_date"] = c_date + pd.Timedelta(days=int(round(cyc * .35)))
            if reached >= 2: o["credit_check_date"] = c_date + pd.Timedelta(days=int(round(cyc * .8)))
            if close > AS_OF:                                         # still open at snapshot
                o["outcome"] = "Open"
                for col in ["quote_sent_date", "credit_check_date"]:
                    if pd.notna(o[col]) and o[col] > AS_OF: o[col] = pd.NaT
                o["stage"] = "Credit Check" if pd.notna(o["credit_check_date"]) else \
                             "Quote Sent" if pd.notna(o["quote_sent_date"]) else "Qualified"
            elif not won:
                o.update(outcome="Lost", stage=STAGES[reached], close_date=close,
                         lost_reason=rng.choice(LOST_REASON[STAGES[reached]]))
            else:
                o.update(outcome="Won", stage="Order Placed", close_date=close)
                # ---- installation & pre-install cancellation ----
                base = BASE_WAIT[region]
                if region == "North West":   # install capacity constraint building from 2025
                    base += 13 * np.clip((close - pd.Timestamp("2025-01-01")).days / 540, 0, 1)
                wait = max(2, int(round(rng.normal(base + (8 if segment == "Business" else 0), 4))))
                o["install_date"] = close + pd.Timedelta(days=wait)
                p_cancel = .04 + .20 / (1 + np.exp(-(wait - 24) / 4)) + (.04 if src == "Door-to-Door" else 0)
                if rng.random() < p_cancel:
                    cdate = close + pd.Timedelta(days=int(rng.integers(1, max(2, wait))))
                    if cdate <= AS_OF: o.update(order_status="Cancelled before install", cancel_date=cdate)
                    else: o["order_status"] = "Awaiting install"
                else:
                    act = o["install_date"] + pd.Timedelta(days=0 if rng.random() < .9 else int(rng.integers(1, 8)))
                    if act > AS_OF: o["order_status"] = "Awaiting install"
                    else:
                        o.update(order_status="Activated", activation_date=act)
                        # ---- churn (monthly hazard simulation) ----
                        churn_date, reason = pd.NaT, None
                        for mm in range(1, 60):
                            mstart = act + pd.Timedelta(days=30 * (mm - 1))
                            if mstart > AS_OF: break
                            h = .004 if segment == "Business" else .007
                            if mm <= 3: h += .035 if src == "Door-to-Door" else .006
                            if mm in (contract, contract + 1): h += .04 if segment == "Business" else .07
                            if rng.random() < h:
                                cd = mstart + pd.Timedelta(days=int(rng.integers(0, 30)))
                                if cd <= AS_OF:
                                    churn_date = cd
                                    if mm <= 3:
                                        w = [.25,.30,.15,.15,.15] if src == "Door-to-Door" else [.30,.08,.30,.17,.15]
                                        reason = rng.choice(["Service not as expected","Did not understand contract terms",
                                                             "Installation/early service issues","Moving home","Found cheaper offer"], p=w)
                                    else:
                                        reason = rng.choice(["Price","Competitor offer","Moving home",
                                                             "Out of contract - switched","Service issues"],
                                                            p=[.25,.25,.2,.15,.15] if mm < contract else [.15,.2,.1,.45,.1])
                                break
                        cid += 1
                        custs.append(dict(customer_id=f"C{cid:06d}", opp_id=opp_id, activation_date=act,
                                          mrr_gbp=mrr, contract_months=contract,
                                          churn_date=churn_date, churn_reason=reason))
            opps.append(o)

leads, opps, custs = pd.DataFrame(leads), pd.DataFrame(opps), pd.DataFrame(custs)

# ---------------- quotas: ordered net-new MRR per rep-month (company policy assumption) -------------
won = opps[opps.outcome == "Won"].copy(); won["m"] = won.close_date.dt.to_period("M")
actual = won.groupby(["rep_id", "m"]).mrr_gbp.sum()
q_rows = []
for _, r in reps_df.iterrows():
    for m in MONTHS:
        ms, me = m.start_time, m.end_time.normalize()
        if r.hire_date > me or (pd.notna(r.leave_date) and r.leave_date <= ms): continue
        s = max(ms, r.hire_date); e = min(me, r.leave_date - pd.Timedelta(days=1)) if pd.notna(r.leave_date) else me
        frac = ((e - s).days + 1) / m.days_in_month
        tm = (ms.year - r.hire_date.year) * 12 + ms.month - r.hire_date.month
        q_rows.append(dict(rep_id=r.rep_id, team=r.team, month=str(m), tenure_month=tm, active_frac=round(frac, 3),
                           actual=actual.get((r.rep_id, m), 0.0)))
q = pd.DataFrame(q_rows)
# base quota = 2024 median of fully-active, fully-ramped rep-months; then +6% (2025) and +15% (2026)
full24 = q[(q.active_frac == 1) & (q.tenure_month >= 6) & q.month.str.startswith("2024")]
base = (full24.groupby("team").actual.median() / 50).round() * 50
RAMP_Q = {0: .25, 1: .50, 2: .75}
uplift = {"2024": 1.00, "2025": 1.06, "2026": 1.15}
q["quota_mrr_gbp"] = [round(base[t] * uplift[mo[:4]] * RAMP_Q.get(tm, 1.0) * f, 0)
                      for t, mo, tm, f in zip(q.team, q.month, q.tenure_month, q.active_frac)]
quotas = q[["rep_id", "month", "quota_mrr_gbp"]]

# ================= inject realistic data-quality defects into the RAW exports =================
def fmt_dates(s, pct_ddmm=0.0):
    out = s.dt.strftime("%Y-%m-%d")
    idx = rng.random(len(s)) < pct_ddmm
    out[idx] = s[idx].dt.strftime("%d/%m/%Y")
    return out.where(s.notna(), "")

L = leads.copy()
REG_VAR = {"London": ["london", "LONDON ", "Greater London"], "South East": ["South-East", "SE", "south east"],
           "Midlands": ["midlands", "The Midlands"], "North West": ["North-West", "NW"],
           "Yorkshire & North East": ["Yorkshire and North East", "Yorks & NE"], "Scotland": ["scotland ", "SCOTLAND"]}
SRC_VAR = {"Web": ["web", "Website", "WEB "], "Door-to-Door": ["Door to door", "D2D", "door-to-door"],
           "Outbound Call": ["Outbound", "outbound call"], "Inbound Call": ["Inbound", "inbound call"]}
for col, var, pct in [("region", REG_VAR, .06), ("lead_source", SRC_VAR, .05)]:
    idx = L.index[(rng.random(len(L)) < pct) & L[col].isin(list(var))]
    L.loc[idx, col] = [rng.choice(var[v]) for v in L.loc[idx, col]]
L["created_date"] = fmt_dates(L.created_date, .02)
tests = pd.DataFrame([dict(lead_id=f"L-TEST-{i:03d}", created_date="2025-03-1%d" % i, lead_source="Web",
                           segment="Residential", region="Test", assigned_rep_id="R999", lead_status="Converted")
                      for i in range(1, 6)])
L = pd.concat([L, tests, L.sample(frac=.012, random_state=1)]).sort_values("lead_id")
L.to_csv(RAW / "crm_leads_export.csv", index=False)

O = opps.merge(products[["product_id", "product_name"]], on="product_id", how="left").drop(columns="product_id")
bad = O.index[(O.outcome == "Won") & (rng.random(len(O)) < .003)]
O.loc[bad, "close_date"] = O.loc[bad, "created_date"] - pd.to_timedelta(rng.integers(3, 11, len(bad)), unit="D")
idx = O.index[rng.random(len(O)) < .03]; O.loc[idx, "product_name"] = O.loc[idx, "product_name"].str.lower()
idx = O.index[rng.random(len(O)) < .002]; O.loc[idx, "discount_pct"] = rng.choice([150, -10, 100], len(idx))
idx = O.index[(O.outcome == "Lost") & (rng.random(len(O)) < .08)]; O.loc[idx, "lost_reason"] = ""
O["mrr_gbp"] = O.mrr_gbp.map(lambda v: f"£{v:.2f}" if rng.random() < .05 else f"{v}")
for c in ["created_date", "quote_sent_date", "credit_check_date", "close_date", "install_date", "cancel_date", "activation_date"]:
    O[c] = fmt_dates(O[c])
testo = pd.DataFrame([dict(opp_id=f"O-TEST-{i:03d}", lead_id=f"L-TEST-{i:03d}", rep_id="R999", product_name="Fibre 500",
                           created_date="2025-03-1%d" % i, outcome="Won", stage="Order Placed", mrr_gbp="32.0")
                      for i in range(1, 6)])
pd.concat([O, testo]).to_csv(RAW / "crm_opportunities_export.csv", index=False)

C = custs.copy()
idx = C.index[C.churn_date.notna() & (rng.random(len(C)) < .004)]
C.loc[idx, "churn_date"] = C.loc[idx, "activation_date"] - pd.Timedelta(days=5)
for c in ["activation_date", "churn_date"]: C[c] = fmt_dates(C[c])
pd.concat([C, C.sample(frac=.005, random_state=2)]).to_csv(RAW / "billing_customers_export.csv", index=False)

R = reps_df.drop(columns="skill").copy()   # rep skill is a hidden generator variable, never exported
R = pd.concat([R, pd.DataFrame([dict(rep_id="R999", rep_name="Test User", team="Test", channel="Test",
                                     hire_date=pd.Timestamp("2025-01-01"))])])
for c in ["hire_date", "leave_date"]: R[c] = fmt_dates(R[c])
R.to_csv(RAW / "hr_sales_reps.csv", index=False)
products.to_csv(RAW / "product_catalogue.csv", index=False)
quotas.to_csv(RAW / "sales_quotas.csv", index=False)
print(f"leads={len(leads)} opps={len(opps)} customers={len(custs)} reps={len(reps_df)} quota_rows={len(quotas)}")
print("quota base by team:", base.to_dict())
