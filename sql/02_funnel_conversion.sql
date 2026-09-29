-- 02 FUNNEL & CONVERSION
-- Lead->Opp conversion measures lead QUALITY/qualification; win rate measures SELLING effectiveness.
-- Keeping them separate tells you whether to fix the lead source or the sales process.

-- @query: funnel_by_source
SELECT l.lead_source,
       COUNT(*)                                                    AS leads,
       SUM(o.opp_id IS NOT NULL)                                   AS opportunities,
       SUM(o.outcome = 'Won')                                      AS orders,
       SUM(o.outcome = 'Lost')                                     AS lost,
       SUM(o.outcome = 'Open')                                     AS open_opps,
       ROUND(1.0 * SUM(o.opp_id IS NOT NULL) / COUNT(*), 3)        AS lead_to_opp_rate,
       ROUND(1.0 * SUM(o.outcome = 'Won') / NULLIF(SUM(o.outcome IN ('Won','Lost')), 0), 3) AS win_rate,
       ROUND(1.0 * SUM(o.outcome = 'Won') / COUNT(*), 3)           AS lead_to_order_rate
FROM leads l
LEFT JOIN opportunities o ON o.lead_id = l.lead_id
GROUP BY l.lead_source
ORDER BY leads DESC;

-- @query: stage_progression_by_source
-- Closed opportunities only: of those that entered each stage, what share progressed?
-- Tells us WHERE in the process each channel loses deals (process-improvement target).
SELECT lead_source,
       COUNT(*)                                                         AS closed_opps,
       ROUND(1.0 * SUM(quote_sent_date IS NOT NULL) / COUNT(*), 3)      AS qualified_to_quote,
       ROUND(1.0 * SUM(credit_check_date IS NOT NULL) / NULLIF(SUM(quote_sent_date IS NOT NULL), 0), 3) AS quote_to_credit_check,
       ROUND(1.0 * SUM(is_won) / NULLIF(SUM(credit_check_date IS NOT NULL), 0), 3)                     AS credit_check_to_order
FROM opportunities
WHERE is_closed = 1
GROUP BY lead_source
ORDER BY closed_opps DESC;

-- @query: lost_reasons_by_stage
SELECT stage AS lost_at_stage, lost_reason, COUNT(*) AS n,
       ROUND(1.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY stage), 3) AS share_of_stage_losses
FROM opportunities
WHERE outcome = 'Lost'
GROUP BY stage, lost_reason
ORDER BY stage, n DESC;
