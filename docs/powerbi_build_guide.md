# Power BI build guide

Build the report in Power BI Desktop on top of the SQL Server views (`sql_server/`).
Do the SQL Server steps first: `08_validation.sql` must show 41/41 PASS.

## 1. Connect (Import mode)

1. **Get data → SQL Server.** Server `localhost` (or `.\SQLEXPRESS`), database `KestrelSales`, mode **Import**.
2. In the navigator, tick the ten `bi` views and click **Transform Data**.
3. Rename each query to drop the schema prefix (`bi dim_date` → `dim_date`), so the measures in `dashboard/powerbi/measures.dax` work unchanged. **Close & Apply.**

## 2. Model

Create these relationships in Model view. All are many-to-one, single direction, from fact to dimension.

| From (fact) | To (dimension) | Active |
|---|---|---|
| `fact_opportunity[close_date]` | `dim_date[date]` | Yes |
| `fact_opportunity[created_date]` | `dim_date[date]` | **No** (used by *Opportunities Created*) |
| `fact_opportunity[rep_id]`, `[product_id]`, `[lead_source]`, `[region]` | `dim_rep`, `dim_product`, `dim_lead_source`, `dim_region` | Yes |
| `fact_lead[created_date]`, `[rep_id]`, `[lead_source]`, `[region]` | `dim_date`, `dim_rep`, `dim_lead_source`, `dim_region` | Yes |
| `fact_customer[activation_date]`, `[rep_id]`, `[lead_source]`, `[region]` | `dim_date`, `dim_rep`, `dim_lead_source`, `dim_region` | Yes |
| `fact_rep_month[month_start]`, `[rep_id]` | `dim_date`, `dim_rep` | Yes |
| `fact_mrr_month[month_start]` | `dim_date` | Yes |

Then:
- **Mark `dim_date` as the date table** (Table tools → Mark as date table → `date`).
- **Sort `dim_date[month_name]` by `month_no`.**
- **Hide the key columns** in fact tables (`rep_id`, `lead_source`, `region`, dates), so report users slice by dimensions only.
- **Create the measure table:** Home → Enter data → name it `_Measures`. Add the 33 measures from `dashboard/powerbi/measures.dax`.
- **Format the measures:**
  - rates as **Percentage, 1 decimal**
  - MRR measures as **Currency £, 0 decimals**
  - day counts as **Whole number**

## 3. Report pages

| Page | Visuals | Slicers |
|---|---|---|
| **Executive overview** | Cards: Orders, Ordered MRR, Win Rate, Lead to Opp Rate, Cancellation Rate, Early Life Churn Rate · Line: Orders by `dim_date[year_month]` · Bar: Win Rate by `lead_source` | `year`, `team`, `lead_source` |
| **Sales process** | Funnel: Leads → Opportunities Created → Orders · Matrix: Quote Rate, Credit Check Rate of Quoted, Order Rate of Credit Checked by `lead_source` · Column: Cancellation Rate by `install_wait_band` · Matrix: Avg Install Wait Days and Cancellation Rate by `region` × `half_label` | `year`, `region` |
| **Teams and quota** | Matrix: Quota Attainment and Share of Rep-Months at Quota by `team` × `year` · Bar: Retained 90d MRR Share by `team` · Bar: Win Rate by `rep_ramp_status` | `year`, `channel` |
| **Revenue and churn** | Clustered column: New MRR vs Churned MRR by `year_month` · Line: Ending MRR · Line: Monthly Churn Rate · Table: Win Rate by `discount_pct` (filtered to one `lead_source`) · Card: Annualised Discount Cost · Cards: Open Pipeline MRR, Weighted Open Pipeline | `year`, `lead_source` |

## 4. Check the numbers before you trust the report

With **no slicers** unless stated, the visuals must show these values. They match `sql_server/08_validation.sql` and the original analysis.

| Visual or measure | Filter | Expected |
|---|---|---|
| Orders | none | 10,861 |
| Ordered MRR | none | £383,899 |
| Win Rate | none | 38.0% |
| Lead to Opp Rate | none | 37.5% |
| Win Rate | lead_source = Referral | 54.9% |
| Early Life Churn Rate | lead_source = Door-to-Door | 11.3% |
| Cancellation Rate | install_wait_band = 29+ days | 20.2% |
| Quota Attainment | team = Telesales Outbound, year = 2026 | 81.3% |
| Quota Attainment | team = Telesales Outbound, year = 2025 | 113.1% |
| Retained 90d MRR Share | team = Field North | 77.7% |
| Ending MRR | year_month = 2026-08 | £293,543 |
| Monthly Churn Rate | year_month = 2026-08 | 1.2% |
| Median Sales Cycle Days | lead_source = Partner | 26 |
| Weighted Open Pipeline | none | £5,018 |

If a value differs, check the relationship and the measure for that visual first. The SQL side is already validated.

## 5. Put it in the repo

1. Save as `dashboard/powerbi/Kestrel_Sales.pbix`. GitHub accepts files up to 100 MB; this one should be a few MB.
2. Export one PNG per page into `dashboard/powerbi/` so the README shows the report without Power BI.
3. Optionally, File → Export → PDF, saved as `dashboard/powerbi/Kestrel_Sales_report.pdf`.

Power BI Service "Publish to web" needs a work or school account. The PNG and PDF exports give reviewers the same view without one.
