-- 01 STAGING TABLES
-- Raw text copies of the clean CSVs: every column is NVARCHAR, so the bulk load never fails on a value.
-- Types are applied in 04, where every failed conversion is counted instead of silently becoming NULL.
USE KestrelSales;
GO
DROP TABLE IF EXISTS stg.reps, stg.products, stg.leads, stg.opportunities, stg.customers, stg.quotas;
GO
CREATE TABLE stg.reps (
    rep_id NVARCHAR(200) NULL,
    rep_name NVARCHAR(200) NULL,
    team NVARCHAR(200) NULL,
    channel NVARCHAR(200) NULL,
    hire_date NVARCHAR(200) NULL,
    leave_date NVARCHAR(200) NULL
);
CREATE TABLE stg.products (
    product_id NVARCHAR(200) NULL,
    product_name NVARCHAR(200) NULL,
    segment NVARCHAR(200) NULL,
    list_mrr_gbp NVARCHAR(200) NULL
);
CREATE TABLE stg.leads (
    lead_id NVARCHAR(200) NULL,
    created_date NVARCHAR(200) NULL,
    lead_source NVARCHAR(200) NULL,
    segment NVARCHAR(200) NULL,
    region NVARCHAR(200) NULL,
    assigned_rep_id NVARCHAR(200) NULL,
    lead_status NVARCHAR(200) NULL,
    lead_month NVARCHAR(200) NULL,
    is_converted NVARCHAR(200) NULL
);
CREATE TABLE stg.opportunities (
    opp_id NVARCHAR(200) NULL,
    lead_id NVARCHAR(200) NULL,
    rep_id NVARCHAR(200) NULL,
    team NVARCHAR(200) NULL,
    channel NVARCHAR(200) NULL,
    lead_source NVARCHAR(200) NULL,
    segment NVARCHAR(200) NULL,
    region NVARCHAR(200) NULL,
    product_id NVARCHAR(200) NULL,
    product_name NVARCHAR(200) NULL,
    list_mrr_gbp NVARCHAR(200) NULL,
    discount_pct NVARCHAR(200) NULL,
    discount_band NVARCHAR(200) NULL,
    mrr_gbp NVARCHAR(200) NULL,
    contract_months NVARCHAR(200) NULL,
    tcv_gbp NVARCHAR(200) NULL,
    created_date NVARCHAR(200) NULL,
    quote_sent_date NVARCHAR(200) NULL,
    credit_check_date NVARCHAR(200) NULL,
    close_date NVARCHAR(200) NULL,
    created_month NVARCHAR(200) NULL,
    close_month NVARCHAR(200) NULL,
    close_year NVARCHAR(200) NULL,
    outcome NVARCHAR(200) NULL,
    stage NVARCHAR(200) NULL,
    lost_reason NVARCHAR(200) NULL,
    is_closed NVARCHAR(200) NULL,
    is_won NVARCHAR(200) NULL,
    date_error NVARCHAR(200) NULL,
    sales_cycle_days NVARCHAR(200) NULL,
    rep_tenure_days NVARCHAR(200) NULL,
    rep_ramp_status NVARCHAR(200) NULL,
    install_date NVARCHAR(200) NULL,
    install_wait_days NVARCHAR(200) NULL,
    install_wait_band NVARCHAR(200) NULL,
    order_status NVARCHAR(200) NULL,
    is_install_resolved NVARCHAR(200) NULL,
    is_cancelled_pre_install NVARCHAR(200) NULL,
    cancel_date NVARCHAR(200) NULL,
    activation_date NVARCHAR(200) NULL,
    customer_id NVARCHAR(200) NULL,
    churn_date NVARCHAR(200) NULL,
    eligible_90d NVARCHAR(200) NULL,
    churned_90d NVARCHAR(200) NULL,
    retained_90d_mrr NVARCHAR(200) NULL
);
CREATE TABLE stg.customers (
    customer_id NVARCHAR(200) NULL,
    opp_id NVARCHAR(200) NULL,
    activation_date NVARCHAR(200) NULL,
    mrr_gbp NVARCHAR(200) NULL,
    contract_months NVARCHAR(200) NULL,
    churn_date NVARCHAR(200) NULL,
    churn_reason NVARCHAR(200) NULL,
    churn_date_error NVARCHAR(200) NULL,
    lead_source NVARCHAR(200) NULL,
    segment NVARCHAR(200) NULL,
    region NVARCHAR(200) NULL,
    team NVARCHAR(200) NULL,
    channel NVARCHAR(200) NULL,
    rep_id NVARCHAR(200) NULL,
    discount_pct NVARCHAR(200) NULL,
    product_name NVARCHAR(200) NULL,
    is_churned NVARCHAR(200) NULL,
    tenure_days NVARCHAR(200) NULL,
    activation_month NVARCHAR(200) NULL,
    churn_month NVARCHAR(200) NULL,
    eligible_90d NVARCHAR(200) NULL,
    churned_90d NVARCHAR(200) NULL
);
CREATE TABLE stg.quotas (
    rep_id NVARCHAR(200) NULL,
    month NVARCHAR(200) NULL,
    quota_mrr_gbp NVARCHAR(200) NULL,
    rep_name NVARCHAR(200) NULL,
    team NVARCHAR(200) NULL,
    channel NVARCHAR(200) NULL
);
GO
