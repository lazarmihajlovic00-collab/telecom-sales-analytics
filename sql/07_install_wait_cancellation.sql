-- 07 INSTALLATION WAIT vs PRE-INSTALL CANCELLATION (process bottleneck analysis)
-- A won order is not revenue until installed. If long install waits drive cancellations,
-- the bottleneck is operational capacity, not sales effort.
-- Only RESOLVED orders (activated or cancelled) are counted; orders still awaiting install are excluded.

-- @query: cancellation_by_wait_band
SELECT install_wait_band, COUNT(*) AS resolved_orders, SUM(is_cancelled_pre_install) AS cancelled,
       ROUND(1.0 * SUM(is_cancelled_pre_install) / COUNT(*), 3) AS cancellation_rate
FROM opportunities
WHERE is_won = 1 AND is_install_resolved = 1 AND install_wait_band <> ''
GROUP BY install_wait_band ORDER BY install_wait_band;

-- @query: wait_and_cancellation_by_region_half
SELECT region,
       substr(close_month, 1, 4) || CASE WHEN CAST(substr(close_month, 6, 2) AS INT) <= 6 THEN '-H1' ELSE '-H2' END AS half_year,
       COUNT(*) AS resolved_orders,
       ROUND(AVG(install_wait_days), 1) AS avg_install_wait_days,
       ROUND(1.0 * SUM(is_cancelled_pre_install) / COUNT(*), 3) AS cancellation_rate
FROM opportunities
WHERE is_won = 1 AND is_install_resolved = 1 AND date_error = 0
GROUP BY region, half_year ORDER BY region, half_year;
