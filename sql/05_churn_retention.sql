-- 05 CHURN & RETENTION
-- Monthly churn rate = customers churned in month / customers active at START of month.
-- Early-life churn (<90 days) is measured only on customers activated >= 90 days before the
-- snapshot (eligible_90d = 1); otherwise recent cohorts would look artificially loyal (right-censoring).

-- @query: monthly_churn_rate
WITH RECURSIVE months(m) AS (
  SELECT '2024-01-01' UNION ALL SELECT date(m, '+1 month') FROM months WHERE m < '2026-08-01'
), c AS (SELECT * FROM customers WHERE churn_date_error = 0)
SELECT substr(m, 1, 7) AS month,
       (SELECT COUNT(*) FROM c WHERE activation_date < m AND (churn_date IS NULL OR churn_date >= m)) AS active_at_start,
       (SELECT COUNT(*) FROM c WHERE churn_month = substr(m, 1, 7) AND activation_date < m)       AS churned_from_opening_base,
       ROUND(1.0 * (SELECT COUNT(*) FROM c WHERE churn_month = substr(m, 1, 7) AND activation_date < m)
             / NULLIF((SELECT COUNT(*) FROM c WHERE activation_date < m AND (churn_date IS NULL OR churn_date >= m)), 0), 4) AS monthly_churn_rate
FROM months;

-- @query: early_life_churn_by_source
SELECT lead_source, SUM(eligible_90d) AS eligible_customers, SUM(churned_90d) AS churned_within_90d,
       ROUND(1.0 * SUM(churned_90d) / SUM(eligible_90d), 3) AS early_life_churn_rate
FROM customers GROUP BY lead_source ORDER BY early_life_churn_rate DESC;

-- @query: early_churn_reasons_by_channel
SELECT channel, churn_reason, COUNT(*) AS n,
       ROUND(1.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY channel), 3) AS share
FROM customers WHERE churned_90d = 1
GROUP BY channel, churn_reason ORDER BY channel, n DESC;
