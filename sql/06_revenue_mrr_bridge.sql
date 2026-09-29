-- 06 MRR BRIDGE (customers acquired since Jan-2024 only; the pre-2024 base is not in this extract)
-- New MRR = MRR of customers activated in month; Churned MRR = MRR of customers who churned in month.

-- @query: mrr_bridge
WITH RECURSIVE months(m) AS (
  SELECT '2024-01' UNION ALL SELECT substr(date(m || '-01', '+1 month'), 1, 7) FROM months WHERE m < '2026-08'
), c AS (SELECT * FROM customers WHERE churn_date_error = 0),
nw AS (SELECT activation_month AS m, SUM(mrr_gbp) AS new_mrr, COUNT(*) AS activations FROM c GROUP BY 1),
ch AS (SELECT churn_month AS m, SUM(mrr_gbp) AS churned_mrr, COUNT(*) AS churns FROM c WHERE churn_month <> '' GROUP BY 1)
SELECT months.m AS month,
       COALESCE(activations, 0) AS activations, COALESCE(churns, 0) AS churns,
       ROUND(COALESCE(new_mrr, 0), 0) AS new_mrr, ROUND(COALESCE(churned_mrr, 0), 0) AS churned_mrr,
       ROUND(COALESCE(new_mrr, 0) - COALESCE(churned_mrr, 0), 0) AS net_new_mrr,
       ROUND(SUM(COALESCE(new_mrr, 0) - COALESCE(churned_mrr, 0)) OVER (ORDER BY months.m), 0) AS ending_mrr
FROM months LEFT JOIN nw ON nw.m = months.m LEFT JOIN ch ON ch.m = months.m
ORDER BY month;
