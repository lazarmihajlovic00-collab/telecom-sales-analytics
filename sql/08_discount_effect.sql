-- 08 DISCOUNT EFFECTIVENESS
-- Discount levels differ by channel (field reps discount more), so comparing discount bands across
-- ALL deals mixes channel effects with discount effects (confounding). We therefore compare WITHIN source.

-- @query: win_rate_by_discount_within_source
SELECT lead_source, discount_pct, SUM(is_closed) AS closed_opps,
       ROUND(1.0 * SUM(is_won) / SUM(is_closed), 3) AS win_rate
FROM opportunities WHERE is_closed = 1
GROUP BY lead_source, discount_pct
HAVING SUM(is_closed) >= 100            -- suppress unreliable small cells
ORDER BY lead_source, discount_pct;

-- @query: discount_cost_by_band
-- Annualised MRR given away on orders placed in the last 12 months
SELECT discount_pct, COUNT(*) AS orders,
       ROUND(SUM(list_mrr_gbp - mrr_gbp) * 12, 0) AS annual_discount_cost_gbp
FROM opportunities WHERE is_won = 1 AND close_date > '2025-08-31'
GROUP BY discount_pct ORDER BY discount_pct;
