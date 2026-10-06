-- 07 THE NINE ANALYSES, PORTED FROM SQLITE (sql/01-09) TO T-SQL
-- Same definitions and comments as the originals; each block is one result set. Run after 06.
-- Main syntax changes: boolean sums become SUM(CASE ...), median uses PERCENTILE_CONT, derived groups
-- (quarter, half-year) use CROSS APPLY, month sequences come from core.calendar, dates from core.settings.
USE KestrelSales;
GO

------------------------------------------------------------------------------------------------
-- 01 DATA QUALITY: every result should be 0 or explainable. Keys and constraints now enforce most of these;
-- the queries stay as documentation and as a check after any manual change.
------------------------------------------------------------------------------------------------
SELECT 'leads' AS tbl, COUNT(*) AS n FROM core.lead
UNION ALL SELECT 'opportunities', COUNT(*) FROM core.opportunity
UNION ALL SELECT 'customers', COUNT(*) FROM core.customer
UNION ALL SELECT 'reps', COUNT(*) FROM core.rep
UNION ALL SELECT 'quotas', COUNT(*) FROM core.quota;

SELECT 'opps without lead' AS check_name, COUNT(*) AS n
FROM core.opportunity AS o LEFT JOIN core.lead AS l ON l.lead_id = o.lead_id WHERE l.lead_id IS NULL
UNION ALL SELECT 'opps without rep', COUNT(*)
FROM core.opportunity AS o LEFT JOIN core.rep AS r ON r.rep_id = o.rep_id WHERE r.rep_id IS NULL
UNION ALL SELECT 'customers without opp', COUNT(*)
FROM core.customer AS c LEFT JOIN core.opportunity AS o ON o.opp_id = c.opp_id WHERE o.opp_id IS NULL
UNION ALL SELECT 'won opps without close_date', COUNT(*) FROM core.opportunity WHERE outcome = 'Won' AND close_date IS NULL
UNION ALL SELECT 'activated orders without customer', COUNT(*) FROM core.opportunity WHERE order_status = 'Activated' AND customer_id IS NULL
UNION ALL SELECT 'opportunity.customer_id not found in customer', COUNT(*)
FROM core.opportunity AS o WHERE o.customer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.customer AS c WHERE c.customer_id = o.customer_id)
UNION ALL SELECT 'duplicate opp_id', COUNT(*) - COUNT(DISTINCT opp_id) FROM core.opportunity
UNION ALL SELECT 'flagged: close before create (excluded from cycle time)', SUM(date_error) FROM core.opportunity
UNION ALL SELECT 'flagged: churn before activation (excluded from churn)', SUM(churn_date_error) FROM core.customer;

------------------------------------------------------------------------------------------------
-- 02 FUNNEL & CONVERSION. Lead->opp conversion measures lead quality; win rate measures selling.
------------------------------------------------------------------------------------------------
SELECT l.lead_source,
       COUNT(*)                                                        AS leads,
       SUM(CASE WHEN o.opp_id IS NOT NULL THEN 1 ELSE 0 END)          AS opportunities,
       SUM(CASE WHEN o.outcome = 'Won'  THEN 1 ELSE 0 END)            AS orders,
       SUM(CASE WHEN o.outcome = 'Lost' THEN 1 ELSE 0 END)            AS lost,
       SUM(CASE WHEN o.outcome = 'Open' THEN 1 ELSE 0 END)            AS open_opps,
       ROUND(1.0 * SUM(CASE WHEN o.opp_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 3) AS lead_to_opp_rate,
       ROUND(1.0 * SUM(CASE WHEN o.outcome = 'Won' THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN o.outcome IN ('Won', 'Lost') THEN 1 ELSE 0 END), 0), 3) AS win_rate,
       ROUND(1.0 * SUM(CASE WHEN o.outcome = 'Won' THEN 1 ELSE 0 END) / COUNT(*), 3)     AS lead_to_order_rate
FROM core.lead AS l
LEFT JOIN core.opportunity AS o ON o.lead_id = l.lead_id
GROUP BY l.lead_source
ORDER BY leads DESC;

-- Closed opportunities only: of those that entered each stage, what share progressed?
SELECT lead_source,
       COUNT(*) AS closed_opps,
       ROUND(1.0 * SUM(CASE WHEN quote_sent_date IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 3) AS qualified_to_quote,
       ROUND(1.0 * SUM(CASE WHEN credit_check_date IS NOT NULL THEN 1 ELSE 0 END)
             / NULLIF(SUM(CASE WHEN quote_sent_date IS NOT NULL THEN 1 ELSE 0 END), 0), 3)        AS quote_to_credit_check,
       ROUND(1.0 * SUM(is_won) / NULLIF(SUM(CASE WHEN credit_check_date IS NOT NULL THEN 1 ELSE 0 END), 0), 3) AS credit_check_to_order
FROM core.opportunity
WHERE is_closed = 1
GROUP BY lead_source
ORDER BY closed_opps DESC;

SELECT stage AS lost_at_stage, lost_reason, COUNT(*) AS n,
       ROUND(1.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY stage), 3) AS share_of_stage_losses
FROM core.opportunity
WHERE outcome = 'Lost'
GROUP BY stage, lost_reason
ORDER BY stage, n DESC;

------------------------------------------------------------------------------------------------
-- 03 WIN RATE, SALES CYCLE, DEAL SIZE. Win rate = won / (won + lost); median cycle (right-skewed data).
------------------------------------------------------------------------------------------------
WITH med AS (
    SELECT DISTINCT lead_source,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sales_cycle_days) OVER (PARTITION BY lead_source) AS median_cycle_days
    FROM core.opportunity
    WHERE is_won = 1 AND date_error = 0
)
SELECT o.lead_source,
       SUM(o.is_closed) AS closed_opps,
       SUM(o.is_won)    AS orders,
       ROUND(1.0 * SUM(o.is_won) / SUM(o.is_closed), 3)                     AS win_rate,
       ROUND(AVG(CASE WHEN o.is_won = 1 THEN o.mrr_gbp END), 2)             AS avg_mrr_per_order,
       ROUND(AVG(CASE WHEN o.is_won = 1 THEN o.tcv_gbp END), 0)             AS avg_tcv_per_order,
       ROUND(AVG(CASE WHEN o.is_won = 1 THEN 1.0 * o.discount_pct END), 1)  AS avg_discount_pct,
       m.median_cycle_days
FROM core.opportunity AS o
JOIN med AS m ON m.lead_source = o.lead_source
GROUP BY o.lead_source, m.median_cycle_days
ORDER BY orders DESC;

SELECT o.team, q.quarter,
       SUM(o.is_closed) AS closed_opps, SUM(o.is_won) AS orders,
       ROUND(1.0 * SUM(o.is_won) / SUM(o.is_closed), 3) AS win_rate
FROM core.opportunity AS o
CROSS APPLY (SELECT CONCAT(LEFT(o.close_month, 4), '-Q', (CAST(RIGHT(o.close_month, 2) AS INT) + 2) / 3) AS quarter) AS q
WHERE o.is_closed = 1
GROUP BY o.team, q.quarter
ORDER BY o.team, q.quarter;

-- Do new reps convert worse? If so, quotas and lead routing for new starters should reflect it.
SELECT team, rep_ramp_status, SUM(is_closed) AS closed_opps,
       ROUND(1.0 * SUM(is_won) / SUM(is_closed), 3) AS win_rate
FROM core.opportunity
WHERE is_closed = 1
GROUP BY team, rep_ramp_status
ORDER BY team, rep_ramp_status;

------------------------------------------------------------------------------------------------
-- 04 QUOTA ATTAINMENT & SALE QUALITY. Attainment = SUM(actual) / SUM(quota), not an average of rep %.
------------------------------------------------------------------------------------------------
WITH actual AS (
    SELECT rep_id, close_month, SUM(mrr_gbp) AS ordered_mrr, COUNT(*) AS orders
    FROM core.opportunity WHERE is_won = 1 GROUP BY rep_id, close_month
)
SELECT q.rep_id, q.rep_name, q.team, q.[month], q.quota_mrr_gbp,
       COALESCE(a.ordered_mrr, 0) AS ordered_mrr, COALESCE(a.orders, 0) AS orders,
       ROUND(COALESCE(a.ordered_mrr, 0) / NULLIF(q.quota_mrr_gbp, 0), 3) AS attainment
FROM core.quota AS q
LEFT JOIN actual AS a ON a.rep_id = q.rep_id AND a.close_month = q.[month]
ORDER BY q.team, q.rep_id, q.[month];

WITH actual AS (
    SELECT rep_id, close_month, SUM(mrr_gbp) AS ordered_mrr
    FROM core.opportunity WHERE is_won = 1 GROUP BY rep_id, close_month
), rm AS (
    SELECT q.team, LEFT(q.[month], 4) AS [year], q.quota_mrr_gbp AS quota, COALESCE(a.ordered_mrr, 0) AS actual
    FROM core.quota AS q
    CROSS JOIN core.settings AS s
    LEFT JOIN actual AS a ON a.rep_id = q.rep_id AND a.close_month = q.[month]
    WHERE q.quota_mrr_gbp >= s.stub_quota_below          -- ignore stub part-month quotas
)
SELECT team, [year], COUNT(*) AS rep_months,
       ROUND(SUM(quota), 0)  AS quota_mrr,
       ROUND(SUM(actual), 0) AS ordered_mrr,
       ROUND(SUM(actual) / SUM(quota), 3) AS attainment,
       ROUND(1.0 * SUM(CASE WHEN actual >= quota THEN 1 ELSE 0 END) / COUNT(*), 3) AS share_rep_months_at_or_above_quota
FROM rm
GROUP BY team, [year]
ORDER BY team, [year];

-- Ordered MRR vs MRR that activated and survived 90 days (orders old enough to judge, see core.settings).
SELECT o.team,
       COUNT(*)                     AS orders,
       ROUND(SUM(o.mrr_gbp), 0)     AS ordered_mrr,
       ROUND(SUM(CASE WHEN o.order_status = 'Activated' THEN o.mrr_gbp ELSE 0 END), 0) AS activated_mrr,
       ROUND(SUM(o.retained_90d_mrr), 0) AS retained_90d_mrr,
       ROUND(SUM(o.retained_90d_mrr) / SUM(o.mrr_gbp), 3) AS pct_ordered_mrr_retained_90d
FROM core.opportunity AS o
CROSS JOIN core.settings AS s
WHERE o.is_won = 1 AND o.close_date <= s.quality_cohort_cutoff
GROUP BY o.team
ORDER BY pct_ordered_mrr_retained_90d;

------------------------------------------------------------------------------------------------
-- 05 CHURN & RETENTION. Monthly churn = churned in month / active at start of month.
-- Early-life churn only for customers activated >= 90 days before the snapshot (eligible_90d = 1).
------------------------------------------------------------------------------------------------
SELECT year_month = CONVERT(CHAR(7), month_start, 126), active_at_start, churned_from_opening_base,
       ROUND(monthly_churn_rate, 4) AS monthly_churn_rate
FROM bi.fact_mrr_month
ORDER BY month_start;

SELECT lead_source, SUM(eligible_90d) AS eligible_customers, SUM(churned_90d) AS churned_within_90d,
       ROUND(1.0 * SUM(churned_90d) / SUM(eligible_90d), 3) AS early_life_churn_rate
FROM core.customer
GROUP BY lead_source
ORDER BY early_life_churn_rate DESC;

SELECT channel, churn_reason, COUNT(*) AS n,
       ROUND(1.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY channel), 3) AS share
FROM core.customer
WHERE churned_90d = 1
GROUP BY channel, churn_reason
ORDER BY channel, n DESC;

------------------------------------------------------------------------------------------------
-- 06 MRR BRIDGE (customers acquired since Jan-2024 only; the older base is not in this extract)
------------------------------------------------------------------------------------------------
SELECT CONVERT(CHAR(7), month_start, 126) AS [month], activations, churns,
       ROUND(new_mrr, 0) AS new_mrr, ROUND(churned_mrr, 0) AS churned_mrr,
       ROUND(net_new_mrr, 0) AS net_new_mrr, ROUND(ending_mrr, 0) AS ending_mrr
FROM bi.fact_mrr_month
ORDER BY month_start;

------------------------------------------------------------------------------------------------
-- 07 INSTALLATION WAIT vs PRE-INSTALL CANCELLATION. Only resolved orders (activated or cancelled).
------------------------------------------------------------------------------------------------
SELECT install_wait_band, COUNT(*) AS resolved_orders, SUM(is_cancelled_pre_install) AS cancelled,
       ROUND(1.0 * SUM(is_cancelled_pre_install) / COUNT(*), 3) AS cancellation_rate
FROM core.opportunity
WHERE is_won = 1 AND is_install_resolved = 1 AND install_wait_band IS NOT NULL
GROUP BY install_wait_band
ORDER BY install_wait_band;

SELECT o.region, h.half_year, COUNT(*) AS resolved_orders,
       ROUND(AVG(1.0 * o.install_wait_days), 1) AS avg_install_wait_days,
       ROUND(1.0 * SUM(o.is_cancelled_pre_install) / COUNT(*), 3) AS cancellation_rate
FROM core.opportunity AS o
CROSS APPLY (SELECT CONCAT(LEFT(o.close_month, 4),
                           CASE WHEN CAST(RIGHT(o.close_month, 2) AS INT) <= 6 THEN '-H1' ELSE '-H2' END) AS half_year) AS h
WHERE o.is_won = 1 AND o.is_install_resolved = 1 AND o.date_error = 0
GROUP BY o.region, h.half_year
ORDER BY o.region, h.half_year;

------------------------------------------------------------------------------------------------
-- 08 DISCOUNT EFFECTIVENESS. Compared within lead source (field reps discount more = confounding).
------------------------------------------------------------------------------------------------
SELECT lead_source, discount_pct, SUM(is_closed) AS closed_opps,
       ROUND(1.0 * SUM(is_won) / SUM(is_closed), 3) AS win_rate
FROM core.opportunity
WHERE is_closed = 1
GROUP BY lead_source, discount_pct
HAVING SUM(is_closed) >= 100            -- suppress unreliable small cells
ORDER BY lead_source, discount_pct;

-- Annualised MRR given away on orders placed in the 12 months before the snapshot
SELECT o.discount_pct, COUNT(*) AS orders,
       ROUND(SUM(o.list_mrr_gbp - o.mrr_gbp) * 12, 0) AS annual_discount_cost_gbp
FROM core.opportunity AS o
CROSS JOIN core.settings AS s
WHERE o.is_won = 1 AND o.close_date > DATEADD(YEAR, -1, s.snapshot_date)
GROUP BY o.discount_pct
ORDER BY o.discount_pct;

------------------------------------------------------------------------------------------------
-- 09 OPEN PIPELINE & STAGE-WEIGHTED VALUE. Weighted pipeline is an expected value, not a promise.
------------------------------------------------------------------------------------------------
WITH c AS (
    SELECT o.is_won, o.quote_sent_date, o.credit_check_date
    FROM core.opportunity AS o
    CROSS JOIN core.settings AS s
    WHERE o.is_closed = 1 AND o.close_date >= s.pipeline_lookback_from
)
SELECT 'Qualified' AS stage, ROUND(1.0 * SUM(is_won) / COUNT(*), 3) AS p_win FROM c
UNION ALL SELECT 'Quote Sent',   ROUND(1.0 * SUM(is_won) / COUNT(*), 3) FROM c WHERE quote_sent_date IS NOT NULL
UNION ALL SELECT 'Credit Check', ROUND(1.0 * SUM(is_won) / COUNT(*), 3) FROM c WHERE credit_check_date IS NOT NULL;

SELECT r.team, f.stage, COUNT(*) AS open_opps,
       ROUND(SUM(f.mrr_gbp), 0) AS open_mrr,
       ROUND(SUM(f.weighted_open_mrr), 0) AS weighted_mrr
FROM bi.fact_opportunity AS f
JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id
WHERE f.outcome = 'Open'
GROUP BY r.team, f.stage
ORDER BY r.team, f.stage;
GO
