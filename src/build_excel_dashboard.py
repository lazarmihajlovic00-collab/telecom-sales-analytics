"""
Build dashboard/Kestrel_Sales_Performance_Dashboard.xlsx

Design choices (interview-defensible):
- Row-level opportunity data lives in the workbook; every KPI is a live COUNTIFS/SUMIFS formula,
  so the dashboard recalculates when the Year / Lead Source selectors change.
- Values imported from Python/SQL (MRR bridge, Holt-Winters forecast) are labelled as such.
- The Excel forecast (trend x seasonal index) is built from formulas as a transparent cross-check
  on the Python model.
Run: python src/build_excel_dashboard.py  then recalc with LibreOffice.
"""
import json, pandas as pd, numpy as np
from pathlib import Path
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.chart.label import DataLabelList
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.comments import Comment
from openpyxl.utils import get_column_letter as L

ROOT = Path(__file__).resolve().parents[1]
C, SQLO, OUT = ROOT/"data"/"clean", ROOT/"analysis"/"sql_outputs", ROOT/"analysis"/"outputs"
opp = pd.read_csv(C/"opportunities.csv", parse_dates=["close_date"])
leads = pd.read_csv(C/"leads.csv")
M = json.load(open(OUT/"key_metrics.json"))

NAVY, TEAL, LIGHT, GREYF = "1F3A5F", "2A9D8F", "EEF2F7", "7F8C9A"
F = lambda **k: Font(name="Arial", **k)
HDR_FILL = PatternFill("solid", fgColor=NAVY); IN_FILL = PatternFill("solid", fgColor="FFFF00")
TILE_FILL = PatternFill("solid", fgColor=LIGHT); thin = Side(style="thin", color="C9D1DB")
BOX = Border(left=thin, right=thin, top=thin, bottom=thin)
PCT, GBP, INT, DEC1 = "0.0%", "£#,##0", "#,##0", "0.0"

wb = Workbook()
def sheet(name, idx=None):
    ws = wb.create_sheet(name) if idx is None else wb.create_sheet(name, idx)
    ws.sheet_view.showGridLines = False; return ws
def header(ws, r, c0, labels, widths=None):
    for i, t in enumerate(labels):
        cell = ws.cell(r, c0+i, t); cell.font = F(bold=True, color="FFFFFF"); cell.fill = HDR_FILL
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True); cell.border = BOX
    if widths:
        for i, w in enumerate(widths): ws.column_dimensions[L(c0+i)].width = w
def title(ws, text, sub=None):
    ws["A1"] = text; ws["A1"].font = F(bold=True, size=15, color=NAVY)
    if sub: ws["A2"] = sub; ws["A2"].font = F(italic=True, size=9, color=GREYF)
def fmt(cell, nf=None, bold=False, color=None):
    cell.font = F(bold=bold, color=color) if color else F(bold=bold)
    if nf: cell.number_format = nf
    cell.border = BOX

# ============================================================ DATA SHEETS
opp["close_half"] = np.where(opp.close_date.notna(),
                             opp.close_date.dt.year.astype("Int64").astype(str) + np.where(opp.close_date.dt.month <= 6, "-H1", "-H2"), "")
opp["reached_quote"] = opp.quote_sent_date.notna().astype(int)
opp["reached_credit"] = opp.credit_check_date.notna().astype(int)
opp["quality_cohort"] = ((opp.is_won == 1) & (opp.close_date <= "2026-04-30")).astype(int)
opp["is_activated"] = (opp.order_status == "Activated").astype(int)
cols = ["opp_id", "created_month", "close_month", "close_year", "close_half", "team", "channel", "lead_source", "region",
        "segment", "product_name", "discount_pct", "list_mrr_gbp", "mrr_gbp", "outcome", "is_closed", "is_won",
        "reached_quote", "reached_credit", "sales_cycle_days", "rep_ramp_status", "install_wait_days", "install_wait_band",
        "is_install_resolved", "is_cancelled_pre_install", "order_status", "eligible_90d", "churned_90d",
        "retained_90d_mrr", "quality_cohort", "is_activated"]
D = opp[cols].copy()
D["close_year"] = D.close_year.astype("Int64")
wsD = sheet("Data_Opps")
header(wsD, 1, 1, cols)
for r in D.itertuples(index=False):
    wsD.append([None if (isinstance(v, float) and np.isnan(v)) or v is pd.NA or v == "" else
                (int(v) if isinstance(v, (np.integer,)) else v) for v in r])
N = len(D) + 1
col = {c: L(i+1) for i, c in enumerate(cols)}
def R(c): return f"Data_Opps!${col[c]}$2:${col[c]}${N}"
wsD.freeze_panes = "A2"; wsD.auto_filter.ref = f"A1:{L(len(cols))}{N}"

la = leads.assign(lead_year=leads.lead_month.str[:4].astype(int)).groupby(
    ["lead_month", "lead_year", "lead_source", "region"]).agg(leads=("lead_id", "count"), converted=("is_converted", "sum")).reset_index()
wsL = sheet("Data_Leads"); header(wsL, 1, 1, list(la.columns))
for r in la.itertuples(index=False): wsL.append([int(v) if isinstance(v, np.integer) else v for v in r])
NL = len(la) + 1
def RL(c): return f"Data_Leads!${'ABCDEF'[list(la.columns).index(c)]}$2:${'ABCDEF'[list(la.columns).index(c)]}${NL}"

qa = pd.read_csv(SQLO/"04_quota_attainment__rep_month_attainment.csv")
wsQ = sheet("Data_Quota")
header(wsQ, 1, 1, ["rep_id", "rep_name", "team", "month", "year", "quota_mrr_gbp", "ordered_mrr", "orders", "attainment", "at_or_above_quota"])
for i, r in enumerate(qa.itertuples(index=False), start=2):
    wsQ.append([r.rep_id, r.rep_name, r.team, r.month, int(r.month[:4]), r.quota_mrr_gbp, r.ordered_mrr, int(r.orders),
                f"=IFERROR(G{i}/F{i},\"\")", f"=IF(G{i}>=F{i},1,0)"])
NQ = len(qa) + 1

# ============================================================ DASHBOARD (selectors + KPI tiles)
ws = wb.active; ws.title = "Dashboard"; ws.sheet_view.showGridLines = False
for c in range(1, 19): ws.column_dimensions[L(c)].width = 11.5
ws.column_dimensions["A"].width = 2
ws["B1"] = "Kestrel Fibre — Sales Performance & Revenue Dashboard"; ws["B1"].font = F(bold=True, size=18, color=NAVY)
ws["B2"] = ("SYNTHETIC PORTFOLIO DATA — fictional UK full-fibre provider. Snapshot 31-Aug-2026. "
            "Built by Lazar Mihajlović as an independent portfolio project.")
ws["B2"].font = F(italic=True, size=9, color="C8553D")
ws["B4"] = "Year (order/lead year):"; ws["B4"].font = F(bold=True)
ws["E4"] = "All"; ws["G4"] = "Lead source:"; ws["G4"].font = F(bold=True); ws["I4"] = "All"
for a in ["E4", "I4"]:
    ws[a].fill = IN_FILL; ws[a].font = F(bold=True, color="0000FF"); ws[a].border = BOX
ws.merge_cells("I4:J4")
dv1 = DataValidation(type="list", formula1='"All,2024,2025,2026"', allow_blank=False)
srcs = ["All", "Web", "Inbound Call", "Referral", "Outbound Call", "Door-to-Door", "Partner", "Web (Business)"]
dv2 = DataValidation(type="list", formula1='"' + ",".join(srcs) + '"', allow_blank=False)
ws.add_data_validation(dv1); ws.add_data_validation(dv2); dv1.add("E4"); dv2.add("I4")
ws["L4"] = "← change the yellow cells to filter the tiles and the channel charts"; ws["L4"].font = F(italic=True, size=9, color=GREYF)
# helper criteria (hidden-ish, column T)
ws["T4"] = '=IF(E4="All",">0",E4)'; ws["T5"] = '=IF(I4="All","*",I4)'
ws["S4"] = "year crit"; ws["S5"] = "source crit"
for a in ["S4", "S5", "T4", "T5"]: ws[a].font = F(size=8, color=GREYF)
Y, S = "Dashboard!$T$4", "Dashboard!$T$5"
opp_f = f"{R('lead_source')},{S},{R('close_year')},{Y}"
lead_f = f"{RL('lead_source')},{S},{RL('lead_year')},{Y}"
tiles = [
    ("Leads", f"=SUMIFS({RL('leads')},{lead_f})", INT, "all sources, by lead date"),
    ("Lead → Opp", f"=IFERROR(SUMIFS({RL('converted')},{lead_f})/SUMIFS({RL('leads')},{lead_f}),0)", PCT, "opportunities ÷ leads"),
    ("Win rate", f"=IFERROR(COUNTIFS({R('is_won')},1,{opp_f})/COUNTIFS({R('is_closed')},1,{opp_f}),0)", PCT, "won ÷ (won + lost)"),
    ("Orders", f"=COUNTIFS({R('is_won')},1,{opp_f})", INT, "orders placed (won)"),
    ("Ordered MRR", f"=SUMIFS({R('mrr_gbp')},{R('is_won')},1,{opp_f})", GBP, "net monthly recurring revenue"),
    ("Avg MRR / order", f"=IFERROR(SUMIFS({R('mrr_gbp')},{R('is_won')},1,{opp_f})/COUNTIFS({R('is_won')},1,{opp_f}),0)", '£#,##0.00', "after discount"),
    ("Pre-install cancel", f"=IFERROR(SUMIFS({R('is_cancelled_pre_install')},{R('is_install_resolved')},1,{opp_f})/COUNTIFS({R('is_install_resolved')},1,{opp_f}),0)", PCT, "cancelled ÷ resolved orders"),
    ("90-day churn", f"=IFERROR(SUMIFS({R('churned_90d')},{opp_f})/SUMIFS({R('eligible_90d')},{opp_f}),0)", PCT, "churned <90d ÷ eligible"),
]
for i, (lab, f, nf, note) in enumerate(tiles):
    c = 2 + i*2
    ws.merge_cells(start_row=6, start_column=c, end_row=6, end_column=c+1)
    ws.merge_cells(start_row=7, start_column=c, end_row=7, end_column=c+1)
    ws.merge_cells(start_row=8, start_column=c, end_row=8, end_column=c+1)
    a, b, n = ws.cell(6, c, lab), ws.cell(7, c, f), ws.cell(8, c, note)
    a.font = F(bold=True, size=9, color=GREYF); b.font = F(bold=True, size=17, color=NAVY); n.font = F(size=7, italic=True, color=GREYF)
    b.number_format = nf
    for rr in (6, 7, 8):
        for cc in (c, c+1): ws.cell(rr, cc).fill = TILE_FILL
        ws.cell(rr, c).alignment = Alignment(horizontal="center", vertical="center")
ws.row_dimensions[7].height = 30

# ============================================================ CHANNEL sheet (filtered by Year selector)
wsC = sheet("Channel")
title(wsC, "Channel performance by lead source", "Filtered by the Year selector on the Dashboard (lead metrics by lead year; opportunity metrics by close year).")
hdr = ["Lead source", "Leads", "Converted", "Lead → Opp", "Closed opps", "Orders", "Win rate", "Lead → Order",
       "Ordered MRR (£)", "Avg MRR/order (£)", "Avg discount %", "Eligible 90d", "Churned <90d", "90-day churn", "Median cycle (days) *"]
header(wsC, 4, 1, hdr, [18, 10, 11, 11, 11, 10, 10, 11, 13, 13, 12, 11, 11, 11, 13])
ck = pd.read_csv(SQLO/"03_win_rate_cycle_deal_size__channel_kpis.csv").set_index("lead_source")
for i, s in enumerate(srcs[1:], start=5):
    yf = f"{R('close_year')},{Y}"
    row = [s, f"=SUMIFS({RL('leads')},{RL('lead_source')},A{i},{RL('lead_year')},{Y})",
           f"=SUMIFS({RL('converted')},{RL('lead_source')},A{i},{RL('lead_year')},{Y})", f"=IFERROR(C{i}/B{i},0)",
           f"=COUNTIFS({R('lead_source')},A{i},{R('is_closed')},1,{yf})", f"=COUNTIFS({R('lead_source')},A{i},{R('is_won')},1,{yf})",
           f"=IFERROR(F{i}/E{i},0)", f"=IFERROR(D{i}*G{i},0)",
           f"=SUMIFS({R('mrr_gbp')},{R('lead_source')},A{i},{R('is_won')},1,{yf})", f"=IFERROR(I{i}/F{i},0)",
           f"=IFERROR(AVERAGEIFS({R('discount_pct')},{R('lead_source')},A{i},{R('is_won')},1,{yf}),0)/100",
           f"=SUMIFS({R('eligible_90d')},{R('lead_source')},A{i},{yf})", f"=SUMIFS({R('churned_90d')},{R('lead_source')},A{i},{yf})",
           f"=IFERROR(M{i}/L{i},0)", float(ck.loc[s, "median_cycle_days"])]
    for j, v in enumerate(row, start=1):
        fmt(wsC.cell(i, j, v), [None, INT, INT, PCT, INT, INT, PCT, PCT, GBP, '£#,##0.00', PCT, INT, INT, PCT, DEC1][j-1], bold=(j == 1))
t = 12
wsC.cell(t, 1, "Total"); fmt(wsC.cell(t, 1), bold=True)
for j, c in enumerate("BCDEFGHIJKLMN", start=2):
    f = {"D": f"=IFERROR(C{t}/B{t},0)", "G": f"=IFERROR(F{t}/E{t},0)", "H": f"=IFERROR(D{t}*G{t},0)",
         "J": f"=IFERROR(I{t}/F{t},0)", "K": "", "N": f"=IFERROR(M{t}/L{t},0)"}.get(c, f"=SUM({c}5:{c}11)")
    fmt(wsC.cell(t, j, f), [INT, INT, PCT, INT, INT, PCT, PCT, GBP, '£#,##0.00', PCT, INT, INT, PCT][j-2], bold=True)
wsC["A14"] = ("* Median cycle is all-time and imported from sql/03 (Excel has no MEDIANIFS; an array formula would slow the "
              "workbook). Lead → Order = Lead→Opp × Win rate (approximation when years differ between lead and close).")
wsC["A14"].font = F(italic=True, size=8, color=GREYF)

# ============================================================ MONTHLY sheet
wsM = sheet("Monthly")
title(wsM, "Monthly trend & MRR bridge", "Orders/leads are live formulas. Activation, churn and MRR bridge values imported from sql/05 & sql/06 (customer-level logic).")
br = pd.read_csv(SQLO/"06_revenue_mrr_bridge__mrr_bridge.csv"); ch = pd.read_csv(SQLO/"05_churn_retention__monthly_churn_rate.csv")
br = br.merge(ch, on="month")
hdr = ["Month", "Leads", "Closed opps", "Orders", "Win rate", "Ordered MRR (£)", "Activations", "Churned customers",
       "Active at month start", "Churned from opening base", "Monthly churn rate", "New MRR (£)", "Churned MRR (£)", "Net new MRR (£)", "Ending MRR (£) †"]
header(wsM, 4, 1, hdr, [10, 9, 11, 9, 9, 13, 11, 11, 12, 13, 11, 12, 12, 12, 13])
for i, r in enumerate(br.itertuples(index=False), start=5):
    vals = [r.month, f"=SUMIFS({RL('leads')},{RL('lead_month')},A{i})", f"=COUNTIFS({R('close_month')},A{i},{R('is_closed')},1)",
            f"=COUNTIFS({R('close_month')},A{i},{R('is_won')},1)", f"=IFERROR(D{i}/C{i},0)",
            f"=SUMIFS({R('mrr_gbp')},{R('close_month')},A{i},{R('is_won')},1)", int(r.activations), int(r.churns),
            int(r.active_at_start), int(r.churned_from_opening_base), f"=IFERROR(J{i}/I{i},0)", float(r.new_mrr),
            float(r.churned_mrr), f"=L{i}-M{i}", f"=N{i}" if i == 5 else f"=O{i-1}+N{i}"]
    for j, v in enumerate(vals, start=1):
        c = wsM.cell(i, j, v); fmt(c, [None, INT, INT, INT, PCT, GBP, INT, INT, INT, INT, '0.00%', GBP, GBP, GBP, GBP][j-1])
        if j in (7, 8, 9, 10, 12, 13): c.font = F(color="404040", italic=True)
LM = 4 + len(br)
wsM.cell(LM+2, 1, "† MRR from customers acquired since Jan-2024 only (pre-2024 base not in extract), so Ending MRR starts at 0. "
                   "Grey italic columns = imported values. Jan-2024 orders are a warm-up artefact (pipeline starts empty).").font = F(italic=True, size=8, color=GREYF)

# ============================================================ TEAM & QUOTA sheet
wsT = sheet("Team_Quota")
title(wsT, "Quota attainment vs sale quality", "Quota measured on ORDERED net-new MRR (assumed policy). Attainment = SUM(actual) ÷ SUM(quota); part-month stubs (<£50) excluded.")
teams = ["Telesales Inbound", "Telesales Outbound", "Field North", "Field South", "Business Development"]
header(wsT, 4, 1, ["Team", "Year", "Quota MRR (£)", "Ordered MRR (£)", "Attainment", "Rep-months", "Rep-months ≥ quota", "% rep-months ≥ quota"],
       [22, 8, 13, 14, 11, 11, 13, 13])
q = lambda c: f"Data_Quota!${c}$2:${c}${NQ}"
r = 5
for tm in teams:
    for yr in [2024, 2025, 2026]:
        vals = [tm, yr, f'=SUMIFS({q("F")},{q("C")},A{r},{q("E")},B{r},{q("F")},">=50")',
                f'=SUMIFS({q("G")},{q("C")},A{r},{q("E")},B{r},{q("F")},">=50")', f"=IFERROR(D{r}/C{r},0)",
                f'=COUNTIFS({q("C")},A{r},{q("E")},B{r},{q("F")},">=50")',
                f'=COUNTIFS({q("C")},A{r},{q("E")},B{r},{q("F")},">=50",{q("J")},1)', f"=IFERROR(G{r}/F{r},0)"]
        for j, v in enumerate(vals, start=1): fmt(wsT.cell(r, j, v), [None, "0", GBP, GBP, PCT, INT, INT, PCT][j-1])
        r += 1
qs = r + 2
wsT.cell(qs-1, 1, "Sale quality — orders placed Jan-2024 to Apr-2026 (every order has had time to activate + 90 days)").font = F(bold=True, color=NAVY)
header(wsT, qs, 1, ["Team", "Orders", "Ordered MRR (£)", "Activated MRR (£)", "Retained 90d MRR (£)", "% ordered MRR retained 90d", "2026 attainment", "Gap (attainment − retained %)"])
for k, tm in enumerate(teams):
    i = qs + 1 + k; base = f"{R('team')},A{i},{R('quality_cohort')},1"
    att_row = 5 + teams.index(tm)*3 + 2
    vals = [tm, f"=COUNTIFS({base})", f"=SUMIFS({R('mrr_gbp')},{base})", f"=SUMIFS({R('mrr_gbp')},{base},{R('is_activated')},1)",
            f"=SUMIFS({R('retained_90d_mrr')},{base})", f"=IFERROR(E{i}/C{i},0)", f"=E{att_row}", f"=G{i}-F{i}"]
    for j, v in enumerate(vals, start=1): fmt(wsT.cell(i, j, v), [None, INT, GBP, GBP, GBP, PCT, PCT, PCT][j-1])
QS1, QS2 = qs + 1, qs + 5

# ============================================================ PROCESS sheet
wsP = sheet("Process")
title(wsP, "Process bottlenecks: stage progression & installation", "Closed opportunities only for stage progression; resolved orders only (activated or cancelled) for cancellation.")
header(wsP, 4, 1, ["Lead source", "Closed opps", "Reached quote", "Reached credit check", "Won", "Qualified → Quote", "Quote → Credit check", "Credit check → Order"],
       [18, 11, 12, 13, 9, 13, 13, 13])
for k, s in enumerate(srcs[1:]):
    i = 5 + k; b = f"{R('lead_source')},A{i},{R('is_closed')},1"
    vals = [s, f"=COUNTIFS({b})", f"=COUNTIFS({b},{R('reached_quote')},1)", f"=COUNTIFS({b},{R('reached_credit')},1)",
            f"=COUNTIFS({b},{R('is_won')},1)", f"=IFERROR(C{i}/B{i},0)", f"=IFERROR(D{i}/C{i},0)", f"=IFERROR(E{i}/D{i},0)"]
    for j, v in enumerate(vals, start=1): fmt(wsP.cell(i, j, v), [None, INT, INT, INT, INT, PCT, PCT, PCT][j-1])
wsP["A13"] = "Pre-install cancellation by install wait"; wsP["A13"].font = F(bold=True, color=NAVY)
header(wsP, 14, 1, ["Install wait band", "Resolved orders", "Cancelled", "Cancellation rate"])
for k, bnd in enumerate(["0-14 days", "15-21 days", "22-28 days", "29+ days"]):
    i = 15 + k; b = f"{R('install_wait_band')},A{i},{R('is_install_resolved')},1"
    for j, v in enumerate([bnd, f"=COUNTIFS({b})", f"=SUMIFS({R('is_cancelled_pre_install')},{b})", f"=IFERROR(C{i}/B{i},0)"], start=1):
        fmt(wsP.cell(i, j, v), [None, INT, INT, PCT][j-1])
wsP["A21"] = "Average install wait (days) by region and half-year of order"; wsP["A21"].font = F(bold=True, color=NAVY)
halves = ["2024-H1", "2024-H2", "2025-H1", "2025-H2", "2026-H1", "2026-H2"]
regions = ["London", "South East", "Midlands", "North West", "Yorkshire & North East", "Scotland"]
header(wsP, 22, 1, ["Region"] + halves)
for k, rg in enumerate(regions):
    i = 23 + k; wsP.cell(i, 1, rg); fmt(wsP.cell(i, 1), bold=True)
    for j, h in enumerate(halves, start=2):
        fmt(wsP.cell(i, j, f"=IFERROR(AVERAGEIFS({R('install_wait_days')},{R('region')},$A{i},{R('close_half')},{L(j)}$22,{R('is_install_resolved')},1),\"\")"), DEC1)
wsP["A30"] = "2026-H2 = July–August only."; wsP["A30"].font = F(italic=True, size=8, color=GREYF)

# ============================================================ DISCOUNT sheet
wsX = sheet("Discount")
title(wsX, "Win rate by discount level — within each lead source", "Compared within source because field reps discount more (comparing across all deals would confound channel with discount). Cells with <100 closed opps are suppressed.")
header(wsX, 4, 1, ["Lead source", "0%", "5%", "10%", "15%", "20%"], [18, 10, 10, 10, 10, 10])
for k, s in enumerate(srcs[1:]):
    i = 5 + k; wsX.cell(i, 1, s); fmt(wsX.cell(i, 1), bold=True)
    for j, d in enumerate([0, 5, 10, 15, 20], start=2):
        b = f"{R('lead_source')},$A{i},{R('discount_pct')},{d},{R('is_closed')},1"
        fmt(wsX.cell(i, j, f'=IF(COUNTIFS({b})<100,"n<100",COUNTIFS({b},{R("is_won")},1)/COUNTIFS({b}))'), PCT)
wsX["A13"] = "Annualised cost of discount (orders placed Sep-2025 to Aug-2026)"; wsX["A13"].font = F(bold=True, color=NAVY)
header(wsX, 14, 1, ["Discount", "Orders", "Annual MRR given away (£)"])
for k, d in enumerate([0, 5, 10, 15, 20]):
    i = 15 + k; w = f"{R('discount_pct')},{d},{R('is_won')},1"
    # last-12-month window via close_year/close_month text is awkward in SUMIFS; use a helper: Sep-25..Aug-26 months
    months12 = [str(p) for p in pd.period_range("2025-09", "2026-08", freq="M")]
    cnt = "+".join([f'COUNTIFS({w},{R("close_month")},"{m}")' for m in months12])
    cost = "+".join([f'(SUMIFS({R("list_mrr_gbp")},{w},{R("close_month")},"{m}")-SUMIFS({R("mrr_gbp")},{w},{R("close_month")},"{m}"))' for m in months12])
    for j, v in enumerate([f"{d}%", f"={cnt}", f"=({cost})*12"], start=1): fmt(wsX.cell(i, j, v), [None, INT, GBP][j-1])
fmt(wsX.cell(20, 1, "Total"), bold=True); fmt(wsX.cell(20, 2, "=SUM(B15:B19)"), INT, True); fmt(wsX.cell(20, 3, "=SUM(C15:C19)"), GBP, True)
wsX["A22"] = "Statistical check (Python, analysis/outputs/key_metrics.json):"; wsX["A22"].font = F(bold=True)
dd = M["discount"]
lines = [f"Door-to-Door: 0%→10% lift {dd['Door-to-Door']['lift_0_to_10']['diff']:+.1%} (95% CI {dd['Door-to-Door']['lift_0_to_10']['ci_low']:+.1%} to {dd['Door-to-Door']['lift_0_to_10']['ci_high']:+.1%}); "
         f"10%→15%+ {dd['Door-to-Door']['lift_10_to_15plus']['diff']:+.1%} (CI {dd['Door-to-Door']['lift_10_to_15plus']['ci_low']:+.1%} to {dd['Door-to-Door']['lift_10_to_15plus']['ci_high']:+.1%}, p={dd['Door-to-Door']['lift_10_to_15plus']['p_value']:.2f}).",
         f"Web: 10%→15%+ {dd['Web']['lift_10_to_15plus']['diff']:+.1%} (p={dd['Web']['lift_10_to_15plus']['p_value']:.2f}). Inbound Call shows p=0.046 on n=207 — not significant after correcting for 4 comparisons (Bonferroni α=0.0125)."]
for k, t_ in enumerate(lines): wsX.cell(23+k, 1, t_).font = F(size=9)

# ============================================================ FORECAST sheet
wsF = sheet("Forecast")
title(wsF, "Monthly orders forecast", "Excel model: linear trend × seasonal index (live formulas). Python models (analysis.py) compared on a 6-month backtest; Holt-Winters selected.")
header(wsF, 4, 1, ["Month", "Year", "Month #", "t", "Orders (actual)", "Year mean", "Ratio to year mean", "Seasonal index",
                   "Deseasonalised", "Excel forecast (trend×index)", "Python Holt-Winters", "HW lower 80%", "HW upper 80%"],
       [10, 7, 8, 5, 12, 10, 11, 10, 12, 14, 13, 11, 11])
months = [str(p) for p in pd.period_range("2024-01", "2027-02", freq="M")]
fc = {f["month"]: f for f in M["forecast"]}
first_model_row, last_act_row = 6, 5 + 31   # Feb-24 .. Aug-26
for k, m in enumerate(months):
    i = 5 + k; actual = m <= "2026-08"
    wsF.cell(i, 1, m); wsF.cell(i, 2, int(m[:4])); wsF.cell(i, 3, int(m[5:]))
    wsF.cell(i, 4, k)
    if actual:
        wsF.cell(i, 5, f"=COUNTIFS({R('close_month')},A{i},{R('is_won')},1)")
        if i >= first_model_row:
            wsF.cell(i, 6, f"=IF(B{i}<=2025,AVERAGEIFS($E${first_model_row}:$E${last_act_row},$B${first_model_row}:$B${last_act_row},B{i}),\"\")")
            wsF.cell(i, 7, f'=IF(F{i}="","",E{i}/F{i})')
            wsF.cell(i, 9, f"=E{i}/H{i}")
    wsF.cell(i, 8, f"=INDEX($P$6:$P$17,C{i})")
    if not actual:
        wsF.cell(i, 10, f"=FORECAST(D{i},$I${first_model_row}:$I${last_act_row},$D${first_model_row}:$D${last_act_row})*H{i}")
        wsF.cell(i, 11, fc[m]["forecast_orders"]); wsF.cell(i, 12, fc[m]["lower_80"]); wsF.cell(i, 13, fc[m]["upper_80"])
    for j, nf in zip(range(1, 14), [None, "0", "0", "0", INT, DEC1, "0.000", "0.000", DEC1, INT, INT, INT, INT]):
        fmt(wsF.cell(i, j), nf)
    if not actual:
        for j in (11, 12, 13): wsF.cell(i, j).font = F(italic=True, color="404040")
wsF["A5"].comment = Comment("Jan-2024 excluded from the model: warm-up artefact (pipeline starts empty on 2024-01-01).", "LM")
header(wsF, 5, 15, ["Month #", "Seasonal index"]); wsF.column_dimensions["O"].width = 9; wsF.column_dimensions["P"].width = 13
for mth in range(1, 13):
    i = 5 + mth
    fmt(wsF.cell(i, 15, mth), "0")
    fmt(wsF.cell(i, 16, f"=AVERAGEIF($C${first_model_row}:$C${last_act_row},O{i},$G${first_model_row}:$G${last_act_row})/AVERAGE($Q$6:$Q$17)"), "0.000")
    fmt(wsF.cell(i, 17, f"=AVERAGEIF($C${first_model_row}:$C${last_act_row},O{i},$G${first_model_row}:$G${last_act_row})"), "0.000")
wsF["Q5"] = "raw"; wsF["Q5"].font = F(size=8, color=GREYF)
wsF["O19"] = "Backtest (train Feb-24→Feb-26, test Mar→Aug-26)"; wsF["O19"].font = F(bold=True, color=NAVY)
header(wsF, 20, 15, ["Method", "MAE", "MAPE", "RMSE", "Bias"]); wsF.column_dimensions["O"].width = 24
for k, (meth, v) in enumerate(M["forecast_backtest"].items()):
    i = 21 + k
    for j, val in enumerate([meth, v["MAE"], v["MAPE"], v["RMSE"], v["bias"]], start=15):
        fmt(wsF.cell(i, j, val), [None, DEC1, PCT, DEC1, DEC1][j-15], bold=(meth == M["forecast_best_method"]))
wsF["O25"] = ("A single 6-month holdout is a small test: the 80% band (±1.28×backtest RMSE) is indicative, not guaranteed. "
              "Re-run the backtest monthly and track forecast error.")
wsF["O25"].font = F(italic=True, size=8, color=GREYF)

# ============================================================ PLANNER sheet (reverse funnel / capacity)
wsN = sheet("Planner")
title(wsN, "Reverse-funnel & capacity planner", "Yellow/blue cells are inputs — change them. Everything else is calculated from the data.")
wsN["A4"] = "Target ordered MRR for the month (£)"; wsN["D4"] = 15000
wsN["A5"] = "New starters in first 3 months (count of reps)"; wsN["D5"] = 2
wsN["A6"] = "New-starter productivity vs ramped rep"; wsN["D6"] = round(float(np.mean(list(M["ramp_ratio_by_channel"].values()))), 2)
for a in ["D4", "D5", "D6"]:
    wsN[a].fill = IN_FILL; wsN[a].font = F(bold=True, color="0000FF"); wsN[a].border = BOX
wsN["D4"].number_format = GBP; wsN["D6"].number_format = "0%"
wsN["E4"] = "Example: £15,000 ≈ a stretch on the Holt-Winters Sep-26 forecast of ~£14.3k"; wsN["E6"] = "Default from data: new reps win ~69–72% as often (Python ramp analysis)"
for a in ["E4", "E6"]: wsN[a].font = F(italic=True, size=8, color=GREYF)
wsN.column_dimensions["A"].width = 18
header(wsN, 8, 1, ["Lead source", "Owning team", "Order mix %", "Avg MRR/order (£)", "Win rate", "Lead → Opp",
                   "Orders needed", "Opps needed", "Leads needed"], [18, 20, 11, 13, 10, 11, 12, 12, 12])
own = {"Web": "Telesales Inbound", "Inbound Call": "Telesales Inbound", "Referral": "Telesales Inbound",
       "Outbound Call": "Telesales Outbound", "Door-to-Door": "Field", "Partner": "Business Development", "Web (Business)": "Business Development"}
recent = opp[(opp.is_won == 1) & (opp.close_date > "2026-02-28")].lead_source.value_counts(normalize=True).round(3)
recent[recent.idxmax()] += round(1 - recent.sum(), 3)   # rounding residual onto the largest source so the mix totals 100%
last12 = f"{R('close_year')},\">=2025\""
for k, s in enumerate(srcs[1:]):
    i = 9 + k
    vals = [s, own[s], round(float(recent.get(s, 0)), 3),
            f"=IFERROR(SUMIFS({R('mrr_gbp')},{R('lead_source')},A{i},{R('is_won')},1,{last12})/COUNTIFS({R('lead_source')},A{i},{R('is_won')},1,{last12}),0)",
            f"=IFERROR(COUNTIFS({R('lead_source')},A{i},{R('is_won')},1,{last12})/COUNTIFS({R('lead_source')},A{i},{R('is_closed')},1,{last12}),0)",
            f"=IFERROR(SUMIFS({RL('converted')},{RL('lead_source')},A{i},{RL('lead_year')},\">=2025\")/SUMIFS({RL('leads')},{RL('lead_source')},A{i},{RL('lead_year')},\">=2025\"),0)",
            f"=IFERROR($D$4*C{i}/SUMPRODUCT($C$9:$C$15,$D$9:$D$15),0)", f"=IFERROR(G{i}/E{i},0)", f"=IFERROR(H{i}/F{i},0)"]
    for j, v in enumerate(vals, start=1): fmt(wsN.cell(i, j, v), [None, None, PCT, '£#,##0.00', PCT, PCT, INT, INT, INT][j-1])
    wsN.cell(i, 3).fill = IN_FILL; wsN.cell(i, 3).font = F(color="0000FF")
fmt(wsN.cell(16, 1, "Total"), bold=True)
for j, c in [(3, "C"), (7, "G"), (8, "H"), (9, "I")]: fmt(wsN.cell(16, j, f"=SUM({c}9:{c}15)"), PCT if c == "C" else INT, True)
wsN["A17"] = "Order mix default = share of orders by source, Mar–Aug 2026. Rates use orders/leads since Jan-2025. Mix must total 100%."
wsN["A17"].font = F(italic=True, size=8, color=GREYF)
# capacity: leads handled per active rep-month (2025-26), computed in Python and entered as editable input
qa2 = qa.assign(year=qa.month.str[:4].astype(int))
rm = qa2[(qa2.year >= 2025) & (qa2.quota_mrr_gbp >= 50)].groupby("team").size()
lt = leads[leads.lead_month >= "2025-01"].merge(pd.read_csv(C/"reps.csv")[["rep_id", "team"]], left_on="assigned_rep_id", right_on="rep_id")
lead_per_rep = (lt.groupby("team").size()/rm).round(0)
lead_per_rep["Field"] = round(float(lt[lt.team.str.startswith("Field")].shape[0]/rm[[t for t in rm.index if t.startswith("Field")]].sum()), 0)
header(wsN, 19, 1, ["Team", "Leads needed", "Leads per rep-month (capacity)", "Ramped reps needed", "+ new-starter adjustment", "Total reps needed"])
for k, tm in enumerate(["Telesales Inbound", "Telesales Outbound", "Field", "Business Development"]):
    i = 20 + k
    vals = [tm, f"=SUMIF($B$9:$B$15,A{i},$I$9:$I$15)", float(lead_per_rep[tm]), f"=IFERROR(B{i}/C{i},0)",
            f"=IF(A{i}=\"Telesales Inbound\",$D$5*(1-$D$6),0)", f"=D{i}+E{i}"]
    for j, v in enumerate(vals, start=1): fmt(wsN.cell(i, j, v), [None, INT, INT, DEC1, DEC1, DEC1][j-1])
    wsN.cell(i, 3).fill = IN_FILL; wsN.cell(i, 3).font = F(color="0000FF")
    wsN.cell(i, 3).comment = Comment("Derived from data: leads assigned to the team Jan-25→Aug-26 ÷ active rep-months. Edit to test scenarios.", "LM")
wsN["A25"] = ("Reading: 'Total reps needed' = leads required ÷ leads each rep handled per month historically. LIMITATION: historical "
              "leads-per-rep reflects lead SUPPLY as much as rep CAPACITY; a real plan should use activity data (calls/visits per hour). "
              "It also assumes lead supply exists at the required volume — for Outbound and Door-to-Door that is a real constraint.")
wsN["A25"].font = F(italic=True, size=8, color=GREYF)

# ============================================================ DEFINITIONS sheet
wsK = sheet("KPI_Definitions")
title(wsK, "KPI definitions", "Same definitions as docs/kpi_definitions.md")
header(wsK, 4, 1, ["KPI", "Formula", "Why it matters", "Watch-out"], [22, 45, 50, 50])
kpis = [
 ("Lead → Opp conversion", "Opportunities ÷ leads (by lead date)", "Lead quality & qualification speed", "Recent weeks look low until leads are worked"),
 ("Win rate", "Won ÷ (Won + Lost); open deals excluded", "Selling effectiveness once a deal is qualified", "Including open deals biases recent periods down"),
 ("Sales cycle", "Median days opp created → order", "Speed of process; B2B vs residential", "Skewed; use median. 36 rows with impossible dates excluded"),
 ("Avg MRR / order", "Ordered net MRR ÷ orders", "Deal size after discount", "Business leased lines inflate averages — segment first"),
 ("Quota attainment", "SUM(ordered MRR) ÷ SUM(quota)", "Are targets realistic & consistently hit?", "Average of rep % over-weights part-month reps"),
 ("Pre-install cancellation", "Cancelled ÷ resolved orders", "Orders that never become revenue", "Orders still awaiting install are excluded"),
 ("90-day churn", "Churned <90d ÷ customers activated ≥90d before snapshot", "Quality of sale / expectation-setting", "Recent customers not eligible yet (censoring)"),
 ("Retained 90d MRR %", "MRR still billing at 90d ÷ ordered MRR", "Quality-adjusted sales output", "Needs a 4-month lag before it can be measured"),
 ("Monthly churn rate", "Churned from opening base ÷ active at month start", "Base retention; revenue at risk", "Spikes at contract end (months 12/24) are expected"),
]
for k, row in enumerate(kpis):
    for j, v in enumerate(row, start=1):
        c = wsK.cell(5+k, j, v); c.font = F(bold=(j == 1), size=9); c.alignment = Alignment(wrap_text=True, vertical="top"); c.border = BOX

# ============================================================ CHARTS on Dashboard
def bar(title_, cats, data, anchor, ytitle=None, pct=True, horizontal=False, series_titles=True, w=16.5, h=8.2):
    ch = BarChart(); ch.type = "bar" if horizontal else "col"; ch.title = title_; ch.style = 10
    ch.add_data(data, titles_from_data=series_titles); ch.set_categories(cats)
    ch.width, ch.height = w, h; ch.legend = None if not series_titles or len(ch.series) == 1 else ch.legend
    if pct: ch.y_axis.numFmt = "0%"
    ch.y_axis.majorGridlines = None; ch.y_axis.delete = False; ch.x_axis.delete = False
    colors = [NAVY, TEAL, "C8553D", "B0B7C3"]
    for s_i, s in enumerate(ch.series): s.graphicalProperties.solidFill = colors[s_i % 4]; s.graphicalProperties.line.solidFill = colors[s_i % 4]
    ch.dataLabels = DataLabelList(); ch.dataLabels.showVal = True
    ch.dataLabels.showSerName = False; ch.dataLabels.showCatName = False
    ch.dataLabels.showLegendKey = False; ch.dataLabels.showPercent = False
    ch.dataLabels.numFmt = "0.0%" if pct else "#,##0"; ch.gapWidth = 60
    ws.add_chart(ch, anchor); return ch

# 1 monthly orders + MRR
c1 = BarChart(); c1.title = "Monthly orders (bars) and ordered MRR £ (line)"; c1.style = 10
c1.add_data(Reference(wsM, min_col=4, min_row=4, max_row=LM), titles_from_data=True)
c1.set_categories(Reference(wsM, min_col=1, min_row=5, max_row=LM)); c1.gapWidth = 40
c1.series[0].graphicalProperties.solidFill = "9AA5B4"; c1.series[0].graphicalProperties.line.solidFill = "9AA5B4"
c1.y_axis.title = "Orders"; c1.y_axis.majorGridlines = None; c1.y_axis.delete = False; c1.x_axis.delete = False
l1 = LineChart(); l1.add_data(Reference(wsM, min_col=6, min_row=4, max_row=LM), titles_from_data=True)
l1.y_axis.axId = 200; l1.y_axis.title = "Ordered MRR (£)"; l1.y_axis.crosses = "max"; l1.y_axis.delete = False
l1.series[0].graphicalProperties.line.solidFill = NAVY; l1.series[0].graphicalProperties.line.width = 22000
c1 += l1; c1.width, c1.height = 16.5, 8.2; c1.legend.position = "b"; ws.add_chart(c1, "B10")
# 2 win rate & lead->opp by source
bar("Win rate by lead source (filtered by Year)", Reference(wsC, min_col=1, min_row=5, max_row=11),
    Reference(wsC, min_col=7, min_row=4, max_row=11), "J10")
# 3 sale quality vs attainment
c3 = bar("2026 quota attainment vs % ordered MRR retained at 90 days", Reference(wsT, min_col=1, min_row=QS1, max_row=QS2),
         Reference(wsT, min_col=6, max_col=7, min_row=QS1-1, max_row=QS2), "B27")
c3.legend.position = "b"
# 4 early life churn by source
bar("90-day churn by lead source (filtered by Year)", Reference(wsC, min_col=1, min_row=5, max_row=11),
    Reference(wsC, min_col=14, min_row=4, max_row=11), "J27")
# 5 cancellation by wait band
bar("Pre-install cancellation rate by install wait", Reference(wsP, min_col=1, min_row=15, max_row=18),
    Reference(wsP, min_col=4, min_row=14, max_row=18), "B44")
# 6 forecast
c6 = LineChart(); c6.title = "Orders: actual, Excel trend×index and Python Holt-Winters forecast"; c6.style = 12
c6.add_data(Reference(wsF, min_col=5, min_row=4, max_row=4+len(months)), titles_from_data=True)
c6.add_data(Reference(wsF, min_col=10, min_row=4, max_row=4+len(months)), titles_from_data=True)
c6.add_data(Reference(wsF, min_col=11, min_row=4, max_row=4+len(months)), titles_from_data=True)
c6.set_categories(Reference(wsF, min_col=1, min_row=5, max_row=4+len(months)))
for s_, colr in zip(c6.series, [NAVY, TEAL, "C8553D"]): s_.graphicalProperties.line.solidFill = colr; s_.smooth = False
c6.y_axis.majorGridlines = None; c6.y_axis.delete = False; c6.x_axis.delete = False
c6.width, c6.height = 16.5, 8.2; c6.legend.position = "b"; ws.add_chart(c6, "J44")

ws["B61"] = "How to read this dashboard: tiles and channel charts respond to the selectors; trend, quota, process and forecast charts show all data. See KPI_Definitions and each sheet's notes."
ws["B61"].font = F(italic=True, size=8, color=GREYF)
order = ["Dashboard", "Channel", "Monthly", "Team_Quota", "Process", "Discount", "Forecast", "Planner", "KPI_Definitions", "Data_Opps", "Data_Leads", "Data_Quota"]
wb._sheets = [wb[n] for n in order]
for n in ["Data_Opps", "Data_Leads", "Data_Quota"]: wb[n].sheet_properties.tabColor = "B0B7C3"
wb["Dashboard"].sheet_properties.tabColor = NAVY
out = ROOT/"dashboard"/"Kestrel_Sales_Performance_Dashboard.xlsx"; wb.save(out); print("saved", out)
