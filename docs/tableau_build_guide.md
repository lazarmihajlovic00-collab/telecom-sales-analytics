# Tableau Build Guide

Goal: rebuild the analysis as a 3-page interactive Tableau Public workbook using the extracts in
`dashboard/tableau/`. Expected time: **2.5–3.5 hours** for a first-time Tableau user.
Tool: **Tableau Public (free)**, <https://public.tableau.com> → *Create* → download Tableau Public Desktop.

> Only list Tableau on your CV after you have built this yourself and can explain every calculated field.

---

## 1. Data sources

| File | Grain | Use |
|---|---|---|
| `fact_leads.csv` | 1 row per lead | Lead volume, lead → opp conversion |
| `fact_opportunities.csv` | 1 row per opportunity | Win rate, cycle, MRR, install, churn flags |
| `rep_month_quota.csv` | 1 row per rep-month | Quota attainment |
| `monthly_mrr_churn.csv` | 1 row per month | MRR bridge, monthly churn |
| `orders_actual_and_forecast.csv` | 1 row per month × type | Forecast chart |

**Model (Data Source tab):**
1. Connect → Text file → `fact_leads.csv`.
2. Drag `fact_opportunities.csv` onto the canvas → relationship **Lead Id = Lead Id** (Tableau relationships, *not* a join: this keeps each table's count correct).
3. Add `rep_month_quota.csv`, `monthly_mrr_churn.csv` and `orders_actual_and_forecast.csv` as **separate data sources** (different grains; do not relate them to the fact tables).
4. Check data types: all `*_date` fields = Date; `is_*`, `eligible_90d`, `churned_90d`, `date_error`, `quality_cohort`, `reached_*` = Number (whole); `mrr_gbp` = Number (decimal). Month text fields (`created_month`, `close_month`): leave as String; use the date fields for time axes.

## 2. Calculated fields (copy exactly)

On `fact_leads` + `fact_opportunities`:
```
// Leads
COUNTD([Lead Id])

// Lead to Opp Rate
COUNTD([Opp Id]) / COUNTD([Lead Id])

// Closed Opps
SUM([Is Closed])

// Orders
SUM([Is Won])

// Win Rate            -- open deals excluded on purpose (see KPI definitions)
SUM([Is Won]) / SUM([Is Closed])

// Ordered MRR
SUM(IF [Is Won] = 1 THEN [Mrr Gbp] END)

// Avg MRR per Order
[Ordered MRR] / [Orders]

// Median Sales Cycle (days)
MEDIAN(IF [Is Won] = 1 AND [Date Error] = 0 THEN [Sales Cycle Days] END)

// Pre-install Cancel Rate
SUM([Is Cancelled Pre Install]) / SUM([Is Install Resolved])

// 90d Churn Rate      -- only customers activated >= 90 days before snapshot
SUM([Churned 90d]) / SUM([Eligible 90d])

// Retained 90d MRR %  -- orders up to Apr-2026 only
SUM(IF [Quality Cohort] = 1 THEN [Retained 90d Mrr] END)
/ SUM(IF [Quality Cohort] = 1 THEN [Mrr Gbp] END)

// Stage: Qualified to Quote
SUM(IF [Is Closed] = 1 THEN [Reached Quote] END) / SUM([Is Closed])

// Stage: Quote to Credit Check
SUM(IF [Is Closed] = 1 THEN [Reached Credit Check] END)
/ SUM(IF [Is Closed] = 1 THEN [Reached Quote] END)

// Stage: Credit Check to Order
SUM([Is Won]) / SUM(IF [Is Closed] = 1 THEN [Reached Credit Check] END)

// Discount Band (for sorting)
STR([Discount Pct]) + "%"

// Close Month
DATETRUNC('month', [Close Date])
```

On `rep_month_quota.csv`:
```
// Month Date
DATE([Month] + "-01")

// Quota Attainment    -- SUM/SUM, not average of rep %
SUM([Ordered Mrr]) / SUM([Quota Mrr Gbp])

// Rep-month at Quota (row level)
IF [Ordered Mrr] >= [Quota Mrr Gbp] THEN 1 ELSE 0 END

// % Rep-months at Quota
SUM([Rep-month at Quota]) / COUNT([Rep Id])
```
Add a data-source filter on `rep_month_quota`: **Quota Mrr Gbp ≥ 50** (excludes part-month stubs).

**Parameter: KPI selector** (demonstrates parameters):
Create Parameter `p_KPI` (String, list: Win Rate, Lead to Opp Rate, Pre-install Cancel Rate, 90d Churn Rate), then:
```
// Selected KPI
CASE [p_KPI]
  WHEN "Win Rate" THEN [Win Rate]
  WHEN "Lead to Opp Rate" THEN [Lead to Opp Rate]
  WHEN "Pre-install Cancel Rate" THEN [Pre-install Cancel Rate]
  WHEN "90d Churn Rate" THEN [90d Churn Rate]
END
```

## 3. Dashboards (1200 × 800, fixed size)

### Dashboard 1: Executive Overview
```
┌──────────────────────────────────────────────────────────────────────┐
│ Title + "Synthetic portfolio data" subtitle     [Year] [Source] [Team]│
├────────┬────────┬────────┬────────┬────────┬────────┬────────┬───────┤
│ Leads  │Lead→Opp│Win rate│ Orders │Ord. MRR│MRR/ord │Cancel %│90d ch.│  ← 8 BANs
├────────┴────────┴────────┴────────┼────────┴────────┴────────┴───────┤
│ Orders (bars) + Ordered MRR (line)│ Selected-KPI trend by month      │
│ dual axis, by Close Month         │ (p_KPI parameter control)        │
├───────────────────────────────────┼──────────────────────────────────┤
│ Win rate by Lead Source (bar)     │ Orders forecast: actual + HW     │
│ click = filter action on page     │ forecast with 80% band           │
└───────────────────────────────────┴──────────────────────────────────┘
```
- **BANs:** one sheet per KPI, measure on Text, font 24 bold; format % to 1 decimal.
- **Dual axis:** Close Month (continuous month) on Columns; Orders and Ordered MRR on Rows → right-click the second → *Dual Axis* → set marks Bar / Line → *Synchronize* is **off** (different units).
- **Forecast:** from `orders_actual_and_forecast`: Month on Columns, Orders on Rows, Type on Color. Add `Lower 80` and `Upper 80` as a *Measure Values* area band, or use a reference band.
- **Filter action:** Dashboard → Actions → Filter → source = win-rate bar, targets = all sheets using `fact_opportunities`.

### Dashboard 2: Funnel & Process
- **Stage progression by source:** Lead Source on Rows; the three Stage measures on Columns (Measure Names/Values); text labels as %.
- **Lost reasons:** filter Outcome = Lost; Stage and Lost Reason on Rows; count of Opp Id as bars, sorted.
- **Cancellation by install wait band:** Install Wait Band on Columns (exclude Null), Pre-install Cancel Rate on Rows; annotate the 22+ day bars.
- **Region × half-year heatmap:** Region on Rows, YEAR(Close Date) and a half-year calc on Columns (`IF MONTH([Close Date])<=6 THEN "H1" ELSE "H2" END`), AVG(Install Wait Days) on Color (sequential), Is Install Resolved = 1 filter. The North West row should stand out.

### Dashboard 3: Quality, Quota & Pricing
- **Attainment vs retention:** Team on Rows; Quota Attainment (2026 filter, from `rep_month_quota`) and Retained 90d MRR % (from `fact_opportunities`) side by side. Two sheets placed next to each other, because they come from different data sources.
- **90-day churn by source:** bar with a reference line at the overall average.
- **Discount curve:** Discount Pct on Columns (discrete), Win Rate on Rows, Lead Source on Color, line marks; filter Lead Source to Door-to-Door, Web, Inbound Call, Outbound Call; add a filter `Closed Opps ≥ 100` (as a measure filter on the view).
- **Rep scatter (bonus):** per rep, Win Rate (x) vs 90d Churn Rate (y), size = Orders, color = Team. This shows whether high-volume reps also have high churn.

## 4. Validation: your numbers must match these

| Check (all years, all sources) | Expected |
|---|---:|
| Leads | 77,005 |
| Orders | 10,861 |
| Win rate | 38.0% |
| Ordered MRR | £383,899 |
| Pre-install cancel rate | 7.2% |
| 90d churn rate | 6.2% |
| Door-to-Door 90d churn | 11.3% |
| Cancel rate, 29+ day band | 20.2% |

If a number is off, the usual cause is the relationship being built as a join (inflated counts) or `Is Closed` being used as a dimension instead of a measure.

## 5. Publish
File → Save to Tableau Public → name it "Kestrel Fibre Sales Analytics (synthetic data)". On the Tableau Public
profile, add a description that links to the GitHub repo and states the data is synthetic. Put the Tableau Public link
at the top of the README.
