-- 09 OPEN PIPELINE & STAGE-WEIGHTED VALUE
-- Stage probability = historical share of closed opps that reached a stage and were then won (last 12 months).
-- Weighted pipeline is an expected value, not a promise; residential cycles are short, so pipeline is small.

-- @query: stage_win_probability
WITH c AS (SELECT * FROM opportunities WHERE is_closed = 1 AND close_date > '2025-08-31')
SELECT 'Qualified' AS stage, ROUND(1.0 * SUM(is_won) / COUNT(*), 3) AS p_win FROM c
UNION ALL SELECT 'Quote Sent', ROUND(1.0 * SUM(is_won) / COUNT(*), 3) FROM c WHERE quote_sent_date IS NOT NULL
UNION ALL SELECT 'Credit Check', ROUND(1.0 * SUM(is_won) / COUNT(*), 3) FROM c WHERE credit_check_date IS NOT NULL;

-- @query: weighted_open_pipeline
WITH c AS (SELECT * FROM opportunities WHERE is_closed = 1 AND close_date > '2025-08-31'),
p AS (
  SELECT 'Qualified' AS stage, 1.0 * SUM(is_won) / COUNT(*) AS p_win FROM c
  UNION ALL SELECT 'Quote Sent', 1.0 * SUM(is_won) / COUNT(*) FROM c WHERE quote_sent_date IS NOT NULL
  UNION ALL SELECT 'Credit Check', 1.0 * SUM(is_won) / COUNT(*) FROM c WHERE credit_check_date IS NOT NULL
)
SELECT o.team, o.stage, COUNT(*) AS open_opps, ROUND(SUM(o.mrr_gbp)) AS open_mrr,
       ROUND(SUM(o.mrr_gbp * p.p_win)) AS weighted_mrr
FROM opportunities o JOIN p ON p.stage = o.stage
WHERE o.outcome = 'Open'
GROUP BY o.team, o.stage ORDER BY o.team, o.stage;
