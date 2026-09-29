# Data dictionary (clean tables)

All tables are synthetic. Money is GBP per month (MRR) unless it says TCV (total contract value = MRR × contract months).
Dates are ISO `YYYY-MM-DD`. Snapshot date: **2026-08-31**. Flags are 0/1.

## `opportunities` (1 row per opportunity, 28,847 rows). Main fact table
| Column | Type | Meaning / rule |
|---|---|---|
| opp_id, lead_id, customer_id | text | Keys. `customer_id` is only filled if the order activated |
| rep_id, team, channel | text | Owning rep; team (5); channel = Telesales / Field / Business Development |
| lead_source | text | Standardised to 7 values (Web, Inbound Call, Outbound Call, Door-to-Door, Referral, Partner, Web (Business)) |
| segment, region | text | Residential / Business; 6 UK regions (standardised from 20+ raw spellings) |
| product_id, product_name | text | Package from `products` |
| list_mrr_gbp, mrr_gbp | number | List price and net price after discount |
| discount_pct, discount_band | number / text | Discrete steps 0 / 5 / 10 / 15 / 20%; band = the step as text. 54 out-of-range values recovered from list vs net MRR |
| contract_months, tcv_gbp | int / number | 12, 24 or 36 months; TCV = mrr_gbp × contract_months |
| created_date, quote_sent_date, credit_check_date, close_date | date | Stage timestamps; blank if the stage was never reached |
| created_month, close_month, close_year | text / int | Derived for grouping |
| outcome | text | Won / Lost / Open |
| stage | text | Furthest stage reached (Qualified → Quote Sent → Credit Check → Order Placed). Lost deals keep the stage where they were lost |
| lost_reason | text | For Lost only; 1,434 blanks set to "Not recorded" (not guessed) |
| is_closed, is_won | flag | Win rate = SUM(is_won) / SUM(is_closed). Open deals excluded |
| date_error | flag | 1 if close_date < created_date (36 rows): kept for counts, excluded from cycle time |
| sales_cycle_days | number | close_date − created_date; blank when date_error = 1 |
| rep_tenure_days, rep_ramp_status | int / text | Rep tenure on created_date; `0-3 months`, `3-6 months`, `6+ months` |
| install_date, install_wait_days, install_wait_band | date / int / text | For won orders; bands 0–14, 15–21, 22–28, 29+ days |
| order_status | text | Activated / Cancelled before install / Awaiting install (blank if not won) |
| is_install_resolved | flag | 1 if activated or cancelled (denominator for cancellation rate) |
| is_cancelled_pre_install, cancel_date | flag / date | Order cancelled before installation |
| activation_date, churn_date | date | From billing |
| eligible_90d | flag | 1 if activated ≥ 90 days before snapshot (prevents censoring bias) |
| churned_90d | flag | Churned within 90 days of activation (only meaningful when eligible_90d = 1) |
| retained_90d_mrr | number | MRR still billing at day 90 (0 if cancelled or churned early) |

**Tableau extract only** (`dashboard/tableau/fact_opportunities.csv`) adds: `reached_quote`, `reached_credit_check`,
`is_activated`, `quality_cohort` (1 = old enough to judge 90-day retention, closed by Apr-2026) and
`list_minus_net_mrr_gbp` (discount cost per order).

## `leads` (1 row per lead, 77,005 rows)
| Column | Meaning |
|---|---|
| lead_id, created_date, lead_month | Key and creation date |
| lead_source, segment, region | As above |
| assigned_rep_id | Rep the lead was routed to |
| lead_status | Converted / Disqualified / Unworked / Open |
| is_converted | 1 if an opportunity was created. Lead→opp conversion = AVG(is_converted) |

## `customers` (1 row per activated customer, 9,957 rows)
Adds to the opportunity fields: `churn_reason`, `churn_date_error` (7 rows with churn before activation, flagged and
excluded from churn metrics), `is_churned`, `tenure_days` (to churn date or snapshot), `activation_month`, `churn_month`.

## `reps` (49 rows)
`rep_id, rep_name` (fictional first name + initial), `team, channel, hire_date, leave_date` (blank = still employed).

## `quotas` (1 row per rep-month, 836 rows)
`rep_id, month, quota_mrr_gbp, rep_name, team, channel`. Quota is on **ordered MRR** in the month the order closes.
New starters get 25% / 50% / 75% of full quota in months 1–3. Team attainment = SUM(ordered MRR) / SUM(quota).
This is a ratio of sums, not an average of rep percentages, so small quotas don't dominate.

## `products` (7 rows)
`product_id, product_name, segment, list_mrr_gbp`.

## Other Tableau extracts
- `rep_month_quota.csv`: rep × month quota, ordered MRR, orders, attainment.
- `monthly_mrr_churn.csv`: MRR bridge (new, churned, net new, ending MRR) and monthly churn rate on the opening base.
- `orders_actual_and_forecast.csv`: monthly orders plus the 6-month Holt-Winters forecast with 80% band.
