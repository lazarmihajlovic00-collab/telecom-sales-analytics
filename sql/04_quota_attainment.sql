-- 04 QUOTA ATTAINMENT & SALE QUALITY
-- Quota is set on ORDERED net-new MRR (assumed company policy). Attainment = ordered MRR / quota.
-- Aggregated as SUM(actual)/SUM(quota), NOT the average of rep percentages (which over-weights part-month reps).

-- @query: rep_month_attainment
WITH actual AS (
  SELECT rep_id, close_month AS month, SUM(mrr_gbp) AS ordered_mrr, COUNT(*) AS orders
  FROM opportunities WHERE is_won = 1 GROUP BY rep_id, close_month
)
SELECT q.rep_id, q.rep_name, q.team, q.month, q.quota_mrr_gbp,
       COALESCE(a.ordered_mrr, 0) AS ordered_mrr, COALESCE(a.orders, 0) AS orders,
       ROUND(COALESCE(a.ordered_mrr, 0) / NULLIF(q.quota_mrr_gbp, 0), 3) AS attainment
FROM quotas q LEFT JOIN actual a ON a.rep_id = q.rep_id AND a.month = q.month
ORDER BY q.team, q.rep_id, q.month;

-- @query: team_year_attainment
WITH actual AS (
  SELECT rep_id, close_month AS month, SUM(mrr_gbp) AS ordered_mrr
  FROM opportunities WHERE is_won = 1 GROUP BY rep_id, close_month
), rm AS (
  SELECT q.team, substr(q.month, 1, 4) AS year, q.quota_mrr_gbp AS quota, COALESCE(a.ordered_mrr, 0) AS actual
  FROM quotas q LEFT JOIN actual a ON a.rep_id = q.rep_id AND a.month = q.month
  WHERE q.quota_mrr_gbp >= 50          -- ignore stub part-month quotas
)
SELECT team, year, COUNT(*) AS rep_months, ROUND(SUM(quota)) AS quota_mrr, ROUND(SUM(actual)) AS ordered_mrr,
       ROUND(SUM(actual) / SUM(quota), 3) AS attainment,
       ROUND(1.0 * SUM(actual >= quota) / COUNT(*), 3) AS share_rep_months_at_or_above_quota
FROM rm GROUP BY team, year ORDER BY team, year;

-- @query: team_sale_quality
-- Ordered MRR vs MRR that actually activated and survived 90 days.
-- Cohort restricted to orders placed up to 2026-04-30 so that every order has had time to activate + 90 days.
SELECT team,
       COUNT(*)                                         AS orders,
       ROUND(SUM(mrr_gbp))                              AS ordered_mrr,
       ROUND(SUM(CASE WHEN order_status = 'Activated' THEN mrr_gbp ELSE 0 END)) AS activated_mrr,
       ROUND(SUM(retained_90d_mrr))                     AS retained_90d_mrr,
       ROUND(SUM(retained_90d_mrr) / SUM(mrr_gbp), 3)   AS pct_ordered_mrr_retained_90d
FROM opportunities
WHERE is_won = 1 AND close_date <= '2026-04-30'
GROUP BY team ORDER BY pct_ordered_mrr_retained_90d;
