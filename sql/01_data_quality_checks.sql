-- 01 DATA QUALITY CHECKS (run after load; every result should be 0 or explainable)
-- Why: a dashboard is only as trustworthy as its joins. These checks prove the clean layer is consistent.

-- @query: row_counts
SELECT 'leads' AS tbl, COUNT(*) AS n FROM leads
UNION ALL SELECT 'opportunities', COUNT(*) FROM opportunities
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'reps', COUNT(*) FROM reps
UNION ALL SELECT 'quotas', COUNT(*) FROM quotas;

-- @query: integrity_checks
SELECT 'opps without lead' AS check_name, COUNT(*) AS n FROM opportunities o LEFT JOIN leads l ON l.lead_id = o.lead_id WHERE l.lead_id IS NULL
UNION ALL SELECT 'opps without rep', COUNT(*) FROM opportunities o LEFT JOIN reps r ON r.rep_id = o.rep_id WHERE r.rep_id IS NULL
UNION ALL SELECT 'customers without opp', COUNT(*) FROM customers c LEFT JOIN opportunities o ON o.opp_id = c.opp_id WHERE o.opp_id IS NULL
UNION ALL SELECT 'won opps without close_date', COUNT(*) FROM opportunities WHERE outcome = 'Won' AND close_date IS NULL
UNION ALL SELECT 'activated orders without customer', COUNT(*) FROM opportunities WHERE order_status = 'Activated' AND customer_id IS NULL
UNION ALL SELECT 'duplicate opp_id', COUNT(*) - COUNT(DISTINCT opp_id) FROM opportunities
UNION ALL SELECT 'flagged: close before create (excluded from cycle time)', SUM(date_error) FROM opportunities
UNION ALL SELECT 'flagged: churn before activation (excluded from churn)', SUM(churn_date_error) FROM customers;
