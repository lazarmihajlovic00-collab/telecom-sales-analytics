-- 06 STAR-SCHEMA VIEWS FOR POWER BI
-- Power BI imports only the bi schema. Dimensions: date, rep, product, lead source, region.
-- Facts: leads, opportunities, customers, rep-months (quota vs ordered MRR), months (MRR bridge and churn).
-- Business rules that are awkward in DAX (stage win probabilities, cohort cut-offs, stub quotas, the MRR
-- running total) are computed here once, so every visual uses the same definitions as the SQL analyses.
USE KestrelSales;
GO

CREATE OR ALTER VIEW bi.dim_date AS
SELECT [date], [year], quarter_no, quarter_label, half_label, month_no, month_name, year_month, month_start
FROM core.calendar;
GO

CREATE OR ALTER VIEW bi.dim_rep AS
SELECT rep_id, rep_name, team, channel, hire_date, leave_date,
       CASE WHEN leave_date IS NULL THEN 'Active' ELSE 'Left' END AS rep_status
FROM core.rep;
GO

CREATE OR ALTER VIEW bi.dim_product AS
SELECT product_id, product_name, segment, list_mrr_gbp
FROM core.product;
GO

CREATE OR ALTER VIEW bi.dim_lead_source AS
SELECT DISTINCT lead_source
FROM core.lead;
GO

CREATE OR ALTER VIEW bi.dim_region AS
SELECT DISTINCT region
FROM core.lead;
GO

CREATE OR ALTER VIEW bi.fact_lead AS
SELECT lead_id, created_date, lead_source, segment, region,
       assigned_rep_id AS rep_id, lead_status, is_converted
FROM core.lead;
GO

-- One row per opportunity. weighted_open_mrr = open MRR x historical win probability of its current stage
-- (closed opportunities since core.settings.pipeline_lookback_from).
CREATE OR ALTER VIEW bi.fact_opportunity AS
WITH closed_recent AS (
    SELECT o.is_won, o.quote_sent_date, o.credit_check_date
    FROM core.opportunity AS o
    CROSS JOIN core.settings AS s
    WHERE o.is_closed = 1 AND o.close_date >= s.pipeline_lookback_from
), stage_p AS (
    SELECT 'Qualified' AS stage, 1.0 * SUM(is_won) / COUNT(*) AS p_win FROM closed_recent
    UNION ALL
    SELECT 'Quote Sent', 1.0 * SUM(is_won) / COUNT(*) FROM closed_recent WHERE quote_sent_date IS NOT NULL
    UNION ALL
    SELECT 'Credit Check', 1.0 * SUM(is_won) / COUNT(*) FROM closed_recent WHERE credit_check_date IS NOT NULL
)
SELECT o.opp_id, o.lead_id, o.rep_id, o.product_id, o.lead_source, o.region, o.segment,
       o.created_date, o.close_date, o.outcome, o.stage, o.lost_reason,
       o.is_closed, o.is_won, o.date_error,
       CASE WHEN o.date_error = 0 THEN o.sales_cycle_days END AS sales_cycle_days,
       o.discount_pct, o.discount_band, o.contract_months,
       o.list_mrr_gbp, o.mrr_gbp, o.tcv_gbp,
       o.list_mrr_gbp - o.mrr_gbp AS discount_mrr_gbp,
       o.rep_ramp_status,
       CASE WHEN o.quote_sent_date   IS NOT NULL THEN 1 ELSE 0 END AS reached_quote,
       CASE WHEN o.credit_check_date IS NOT NULL THEN 1 ELSE 0 END AS reached_credit_check,
       o.install_wait_days, o.install_wait_band, o.order_status,
       o.is_install_resolved, o.is_cancelled_pre_install, o.retained_90d_mrr,
       CASE WHEN o.is_won = 1 AND o.close_date <= s.quality_cohort_cutoff THEN 1 ELSE 0 END AS in_quality_cohort,
       CASE WHEN o.outcome = 'Open' THEN o.mrr_gbp * p.p_win END AS weighted_open_mrr
FROM core.opportunity AS o
CROSS JOIN core.settings AS s
LEFT JOIN stage_p AS p ON p.stage = o.stage;
GO

-- Customers with a churn date before activation (churn_date_error = 1) keep their row but lose the churn date.
CREATE OR ALTER VIEW bi.fact_customer AS
SELECT customer_id, opp_id, rep_id, lead_source, region, segment,
       activation_date,
       CASE WHEN churn_date_error = 0 THEN churn_date END AS churn_date,
       mrr_gbp, contract_months, is_churned, churn_reason, churn_date_error,
       eligible_90d, churned_90d, tenure_days
FROM core.customer;
GO

-- One row per rep-month with a quota. Attainment = SUM(ordered_mrr) / SUM(quota_mrr_gbp) over non-stub rows.
CREATE OR ALTER VIEW bi.fact_rep_month AS
WITH actual AS (
    SELECT rep_id, close_month, SUM(mrr_gbp) AS ordered_mrr, COUNT(*) AS orders
    FROM core.opportunity
    WHERE is_won = 1
    GROUP BY rep_id, close_month
)
SELECT q.rep_id,
       DATEFROMPARTS(CAST(LEFT(q.[month], 4) AS INT), CAST(RIGHT(q.[month], 2) AS INT), 1) AS month_start,
       q.quota_mrr_gbp,
       COALESCE(a.ordered_mrr, 0) AS ordered_mrr,
       COALESCE(a.orders, 0)      AS orders,
       CASE WHEN q.quota_mrr_gbp < s.stub_quota_below THEN 1 ELSE 0 END AS is_stub_quota,
       CASE WHEN COALESCE(a.ordered_mrr, 0) >= q.quota_mrr_gbp THEN 1 ELSE 0 END AS met_quota
FROM core.quota AS q
CROSS JOIN core.settings AS s
LEFT JOIN actual AS a ON a.rep_id = q.rep_id AND a.close_month = q.[month];
GO

-- One row per month from Jan-2024 to the snapshot month: MRR bridge and monthly churn on the opening base.
-- ending_mrr covers customers acquired since Jan-2024 only (the extract has no older base).
CREATE OR ALTER VIEW bi.fact_mrr_month AS
WITH months AS (
    SELECT cal.month_start
    FROM core.calendar AS cal
    CROSS JOIN core.settings AS s
    WHERE cal.is_month_start = 1
      AND cal.month_start BETWEEN '2024-01-01' AND DATEFROMPARTS(YEAR(s.snapshot_date), MONTH(s.snapshot_date), 1)
), cust AS (
    SELECT activation_date, churn_date, mrr_gbp,
           DATEFROMPARTS(YEAR(activation_date), MONTH(activation_date), 1) AS activation_month,
           CASE WHEN churn_date IS NOT NULL THEN DATEFROMPARTS(YEAR(churn_date), MONTH(churn_date), 1) END AS churn_month
    FROM core.customer
    WHERE churn_date_error = 0
), flows AS (
    -- Every month is paired with every customer and then grouped by month. Months and customers sit in the
    -- same FROM clause, so the aggregates contain no outer reference (a CROSS APPLY version raises error 8124).
    SELECT m.month_start,
           SUM(CASE WHEN c.activation_month = m.month_start THEN 1 ELSE 0 END)         AS activations,
           SUM(CASE WHEN c.activation_month = m.month_start THEN c.mrr_gbp ELSE 0 END) AS new_mrr,
           SUM(CASE WHEN c.churn_month = m.month_start THEN 1 ELSE 0 END)              AS churns,
           SUM(CASE WHEN c.churn_month = m.month_start THEN c.mrr_gbp ELSE 0 END)      AS churned_mrr,
           SUM(CASE WHEN c.activation_date < m.month_start
                     AND (c.churn_date IS NULL OR c.churn_date >= m.month_start) THEN 1 ELSE 0 END)          AS active_at_start,
           SUM(CASE WHEN c.churn_month = m.month_start AND c.activation_date < m.month_start THEN 1 ELSE 0 END) AS churned_from_opening_base
    FROM months AS m
    CROSS JOIN cust AS c
    GROUP BY m.month_start
)
SELECT month_start, activations, churns, new_mrr, churned_mrr,
       new_mrr - churned_mrr AS net_new_mrr,
       SUM(new_mrr - churned_mrr) OVER (ORDER BY month_start ROWS UNBOUNDED PRECEDING) AS ending_mrr,
       active_at_start, churned_from_opening_base,
       CAST(1.0 * churned_from_opening_base / NULLIF(active_at_start, 0) AS DECIMAL(9, 6)) AS monthly_churn_rate
FROM flows;
GO

SELECT s.name AS [schema], v.name AS view_name FROM sys.views AS v JOIN sys.schemas AS s ON s.schema_id = v.schema_id
WHERE s.name = N'bi' ORDER BY v.name;   -- expected: 10 views, including fact_mrr_month
GO
