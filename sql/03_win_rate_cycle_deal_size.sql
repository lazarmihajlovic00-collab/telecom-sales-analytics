-- 03 WIN RATE, SALES CYCLE, DEAL SIZE
-- Win rate = Won / (Won + Lost). Open deals are EXCLUDED: including them would drag down
-- recent periods simply because their deals have not finished yet.
-- Sales cycle uses the MEDIAN because cycle times are right-skewed (a few very long B2B deals).

-- @query: channel_kpis
WITH cyc AS (
  SELECT lead_source, sales_cycle_days AS d,
         ROW_NUMBER() OVER (PARTITION BY lead_source ORDER BY sales_cycle_days) AS rn,
         COUNT(*)     OVER (PARTITION BY lead_source)                          AS n
  FROM opportunities WHERE is_won = 1 AND date_error = 0
), med AS (
  SELECT lead_source, AVG(d) AS median_cycle_days FROM cyc
  WHERE rn IN ((n + 1) / 2, (n + 2) / 2) GROUP BY lead_source
)
SELECT o.lead_source,
       SUM(is_closed) AS closed_opps, SUM(is_won) AS orders,
       ROUND(1.0 * SUM(is_won) / SUM(is_closed), 3)                       AS win_rate,
       ROUND(AVG(CASE WHEN is_won = 1 THEN mrr_gbp END), 2)               AS avg_mrr_per_order,
       ROUND(AVG(CASE WHEN is_won = 1 THEN tcv_gbp END), 0)               AS avg_tcv_per_order,
       ROUND(AVG(CASE WHEN is_won = 1 THEN discount_pct END), 1)          AS avg_discount_pct,
       m.median_cycle_days
FROM opportunities o JOIN med m ON m.lead_source = o.lead_source
GROUP BY o.lead_source ORDER BY orders DESC;

-- @query: win_rate_by_team_quarter
SELECT team,
       substr(close_month, 1, 4) || '-Q' || ((CAST(substr(close_month, 6, 2) AS INT) + 2) / 3) AS quarter,
       SUM(is_closed) AS closed_opps, SUM(is_won) AS orders,
       ROUND(1.0 * SUM(is_won) / SUM(is_closed), 3) AS win_rate
FROM opportunities WHERE is_closed = 1
GROUP BY team, quarter ORDER BY team, quarter;

-- @query: win_rate_by_rep_ramp
-- Do new reps convert worse? If so, quotas and lead routing for new starters should reflect it.
SELECT team, rep_ramp_status, SUM(is_closed) AS closed_opps,
       ROUND(1.0 * SUM(is_won) / SUM(is_closed), 3) AS win_rate
FROM opportunities WHERE is_closed = 1
GROUP BY team, rep_ramp_status ORDER BY team, rep_ramp_status;
