-- 08 VALIDATION: does SQL Server reproduce the published Python/SQLite results?
-- Expected values come from the original pipeline (data/kestrel_sales.db, analysis/outputs/key_metrics.json).
-- Rates are compared to 4 decimals and money to 2, with a one-unit tolerance for rounding mode differences.
-- Every row should say PASS. A FAIL points to the exact metric whose logic or load differs.
USE KestrelSales;
GO
SET NOCOUNT ON;
DECLARE @run DATETIME2(0) = SYSDATETIME();
DECLARE @r TABLE (seq INT IDENTITY(1, 1), check_name NVARCHAR(100), expected DECIMAL(18, 4), actual DECIMAL(18, 4), tolerance DECIMAL(18, 4));

INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'rows_leads', 77005, (SELECT COUNT(*) FROM core.lead), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'rows_opportunities', 28847, (SELECT COUNT(*) FROM core.opportunity), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'rows_customers', 9957, (SELECT COUNT(*) FROM core.customer), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'rows_reps', 49, (SELECT COUNT(*) FROM core.rep), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'rows_quotas', 836, (SELECT COUNT(*) FROM core.quota), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'rows_products', 7, (SELECT COUNT(*) FROM core.product), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'orders', 10861, (SELECT SUM(is_won) FROM core.opportunity), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'closed_opps', 28604, (SELECT SUM(is_closed) FROM core.opportunity), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'open_opps', 243, (SELECT COUNT(*) FROM core.opportunity WHERE outcome = 'Open'), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'win_rate', 0.3797, (SELECT ROUND(1.0 * SUM(is_won) / SUM(is_closed), 4) FROM core.opportunity), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'ordered_mrr', 383899.05, (SELECT ROUND(SUM(CASE WHEN is_won = 1 THEN mrr_gbp END), 2) FROM core.opportunity), 0.01);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'lead_to_opp_rate', 0.3746, (SELECT ROUND(1.0 * SUM(CASE WHEN o.opp_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 4) FROM core.lead AS l LEFT JOIN core.opportunity AS o ON o.lead_id = l.lead_id), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'win_rate_Referral', 0.5488, (SELECT ROUND(1.0 * SUM(is_won) / SUM(is_closed), 4) FROM core.opportunity WHERE lead_source = 'Referral'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'win_rate_Outbound Call', 0.2171, (SELECT ROUND(1.0 * SUM(is_won) / SUM(is_closed), 4) FROM core.opportunity WHERE lead_source = 'Outbound Call'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'win_rate_Door-to-Door', 0.447, (SELECT ROUND(1.0 * SUM(is_won) / SUM(is_closed), 4) FROM core.opportunity WHERE lead_source = 'Door-to-Door'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'median_cycle_Partner', 26.0, (SELECT TOP (1) PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sales_cycle_days) OVER () FROM core.opportunity WHERE is_won = 1 AND date_error = 0 AND lead_source = 'Partner'), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'early_churn_Door-to-Door', 0.1125, (SELECT ROUND(1.0 * SUM(churned_90d) / SUM(eligible_90d), 4) FROM bi.fact_customer WHERE lead_source = 'Door-to-Door'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'cancel_rate_0-14 days', 0.0596, (SELECT ROUND(1.0 * SUM(is_cancelled_pre_install) / COUNT(*), 4) FROM bi.fact_opportunity WHERE is_won = 1 AND is_install_resolved = 1 AND install_wait_band = '0-14 days'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'cancel_rate_15-21 days', 0.0785, (SELECT ROUND(1.0 * SUM(is_cancelled_pre_install) / COUNT(*), 4) FROM bi.fact_opportunity WHERE is_won = 1 AND is_install_resolved = 1 AND install_wait_band = '15-21 days'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'cancel_rate_22-28 days', 0.1545, (SELECT ROUND(1.0 * SUM(is_cancelled_pre_install) / COUNT(*), 4) FROM bi.fact_opportunity WHERE is_won = 1 AND is_install_resolved = 1 AND install_wait_band = '22-28 days'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'cancel_rate_29+ days', 0.2019, (SELECT ROUND(1.0 * SUM(is_cancelled_pre_install) / COUNT(*), 4) FROM bi.fact_opportunity WHERE is_won = 1 AND is_install_resolved = 1 AND install_wait_band = '29+ days'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Business Development_2025', 1.8478, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Business Development' AND YEAR(f.month_start) = 2025), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Business Development_2026', 1.3478, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Business Development' AND YEAR(f.month_start) = 2026), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Field North_2025', 1.0717, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Field North' AND YEAR(f.month_start) = 2025), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Field North_2026', 1.0803, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Field North' AND YEAR(f.month_start) = 2026), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Field South_2025', 1.1931, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Field South' AND YEAR(f.month_start) = 2025), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Field South_2026', 1.2028, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Field South' AND YEAR(f.month_start) = 2026), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Telesales Inbound_2025', 1.1017, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Telesales Inbound' AND YEAR(f.month_start) = 2025), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Telesales Inbound_2026', 1.1077, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Telesales Inbound' AND YEAR(f.month_start) = 2026), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Telesales Outbound_2025', 1.1305, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Telesales Outbound' AND YEAR(f.month_start) = 2025), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'attainment_Telesales Outbound_2026', 0.8133, (SELECT ROUND(SUM(f.ordered_mrr) / SUM(f.quota_mrr_gbp), 4) FROM bi.fact_rep_month AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.is_stub_quota = 0 AND r.team = 'Telesales Outbound' AND YEAR(f.month_start) = 2026), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'retained90_Business Development', 0.8637, (SELECT ROUND(SUM(f.retained_90d_mrr) / SUM(f.mrr_gbp), 4) FROM bi.fact_opportunity AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.in_quality_cohort = 1 AND r.team = 'Business Development'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'retained90_Field North', 0.7767, (SELECT ROUND(SUM(f.retained_90d_mrr) / SUM(f.mrr_gbp), 4) FROM bi.fact_opportunity AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.in_quality_cohort = 1 AND r.team = 'Field North'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'retained90_Field South', 0.8202, (SELECT ROUND(SUM(f.retained_90d_mrr) / SUM(f.mrr_gbp), 4) FROM bi.fact_opportunity AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.in_quality_cohort = 1 AND r.team = 'Field South'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'retained90_Telesales Inbound', 0.9024, (SELECT ROUND(SUM(f.retained_90d_mrr) / SUM(f.mrr_gbp), 4) FROM bi.fact_opportunity AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.in_quality_cohort = 1 AND r.team = 'Telesales Inbound'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'retained90_Telesales Outbound', 0.905, (SELECT ROUND(SUM(f.retained_90d_mrr) / SUM(f.mrr_gbp), 4) FROM bi.fact_opportunity AS f JOIN bi.dim_rep AS r ON r.rep_id = f.rep_id WHERE f.in_quality_cohort = 1 AND r.team = 'Telesales Outbound'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'ending_mrr_2026-08', 293542.7, (SELECT ROUND(ending_mrr, 2) FROM bi.fact_mrr_month WHERE month_start = '2026-08-01'), 0.01);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'active_at_start_2026-08', 8059, (SELECT active_at_start FROM bi.fact_mrr_month WHERE month_start = '2026-08-01'), 0);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'churn_rate_2026-08', 0.0123, (SELECT ROUND(monthly_churn_rate, 4) FROM bi.fact_mrr_month WHERE month_start = '2026-08-01'), 0.0001);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'discount_cost_15plus_annual', 50275.8, (SELECT ROUND(SUM(o.list_mrr_gbp - o.mrr_gbp) * 12, 2) FROM core.opportunity AS o CROSS JOIN core.settings AS s WHERE o.is_won = 1 AND o.close_date > DATEADD(YEAR, -1, s.snapshot_date) AND o.discount_pct >= 15), 0.01);
INSERT INTO @r (check_name, expected, actual, tolerance) VALUES (N'weighted_open_pipeline_mrr', 5017.6, (SELECT ROUND(SUM(weighted_open_mrr), 2) FROM bi.fact_opportunity), 0.01);

INSERT INTO qa.validation_result (run_at, check_name, expected, actual, passed)
SELECT @run, check_name, expected, actual, CASE WHEN ABS(actual - expected) <= tolerance THEN 1 ELSE 0 END FROM @r;

SELECT check_name, expected, actual,
       CASE WHEN actual IS NULL THEN 'FAIL (no value)' WHEN ABS(actual - expected) <= tolerance THEN 'PASS' ELSE 'FAIL' END AS result
FROM @r ORDER BY seq;

SELECT SUM(CASE WHEN ABS(actual - expected) <= tolerance THEN 1 ELSE 0 END) AS passed, COUNT(*) AS total FROM @r;
GO
