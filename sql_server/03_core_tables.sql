-- 03 CORE TABLES: typed, keyed and constrained
-- 0/1 flags are TINYINT (not BIT) so SUM(flag) counts rows directly, as in the original SQL.
-- opportunity.customer_id has no foreign key on purpose (customer already points to opportunity); 08 checks it instead.
USE KestrelSales;
GO
DROP TABLE IF EXISTS core.quota, core.customer, core.opportunity, core.lead, core.product, core.rep, core.settings;
GO
-- Analysis settings, kept in one place instead of being hard-coded in every view
CREATE TABLE core.settings (
    snapshot_date          DATE NOT NULL,  -- date the CRM and billing extracts were taken
    quality_cohort_cutoff  DATE NOT NULL,  -- orders closed up to here have had time to activate + 90 days
    pipeline_lookback_from DATE NOT NULL,  -- stage win probabilities use closed opps from this date
    stub_quota_below       DECIMAL(10,2) NOT NULL  -- part-month starter quotas below this are excluded from attainment
);
INSERT INTO core.settings VALUES ('2026-08-31', '2026-04-30', '2025-09-01', 50);
GO
CREATE TABLE core.rep (
    rep_id                     VARCHAR(10)    NOT NULL,
    rep_name                   NVARCHAR(50)   NOT NULL,
    team                       VARCHAR(30)    NOT NULL,
    channel                    VARCHAR(30)    NOT NULL,
    hire_date                  DATE           NOT NULL,
    leave_date                 DATE           NULL,
    CONSTRAINT PK_rep PRIMARY KEY (rep_id),
    CONSTRAINT CK_rep_dates CHECK (leave_date IS NULL OR leave_date >= hire_date)
);
CREATE TABLE core.product (
    product_id                 VARCHAR(10)    NOT NULL,
    product_name               NVARCHAR(50)   NOT NULL,
    segment                    VARCHAR(20)    NOT NULL,
    list_mrr_gbp               DECIMAL(10,2)  NOT NULL,
    CONSTRAINT PK_product PRIMARY KEY (product_id),
    CONSTRAINT CK_product_price CHECK (list_mrr_gbp >= 0)
);
CREATE TABLE core.lead (
    lead_id                    VARCHAR(10)    NOT NULL,
    created_date               DATE           NOT NULL,
    lead_source                VARCHAR(30)    NOT NULL,
    segment                    VARCHAR(20)    NOT NULL,
    region                     VARCHAR(40)    NOT NULL,
    assigned_rep_id            VARCHAR(10)    NOT NULL,
    lead_status                VARCHAR(20)    NOT NULL,
    lead_month                 CHAR(7)        NOT NULL,
    is_converted               TINYINT        NOT NULL,
    CONSTRAINT PK_lead PRIMARY KEY (lead_id),
    CONSTRAINT FK_lead_rep FOREIGN KEY (assigned_rep_id) REFERENCES core.rep (rep_id),
    CONSTRAINT CK_lead_flag CHECK (is_converted IN (0, 1))
);
CREATE TABLE core.opportunity (
    opp_id                     VARCHAR(10)    NOT NULL,
    lead_id                    VARCHAR(10)    NOT NULL,
    rep_id                     VARCHAR(10)    NOT NULL,
    team                       VARCHAR(30)    NOT NULL,
    channel                    VARCHAR(30)    NOT NULL,
    lead_source                VARCHAR(30)    NOT NULL,
    segment                    VARCHAR(20)    NOT NULL,
    region                     VARCHAR(40)    NOT NULL,
    product_id                 VARCHAR(10)    NOT NULL,
    product_name               NVARCHAR(50)   NOT NULL,
    list_mrr_gbp               DECIMAL(10,2)  NOT NULL,
    discount_pct               SMALLINT       NOT NULL,
    discount_band              VARCHAR(10)    NOT NULL,
    mrr_gbp                    DECIMAL(10,2)  NOT NULL,
    contract_months            SMALLINT       NOT NULL,
    tcv_gbp                    DECIMAL(12,2)  NOT NULL,
    created_date               DATE           NOT NULL,
    quote_sent_date            DATE           NULL,
    credit_check_date          DATE           NULL,
    close_date                 DATE           NULL,
    created_month              CHAR(7)        NOT NULL,
    close_month                CHAR(7)        NULL,
    close_year                 SMALLINT       NULL,
    outcome                    VARCHAR(10)    NOT NULL,
    stage                      VARCHAR(20)    NOT NULL,
    lost_reason                NVARCHAR(60)   NULL,
    is_closed                  TINYINT        NOT NULL,
    is_won                     TINYINT        NOT NULL,
    date_error                 TINYINT        NOT NULL,
    sales_cycle_days           INT            NULL,
    rep_tenure_days            INT            NOT NULL,
    rep_ramp_status            VARCHAR(20)    NOT NULL,
    install_date               DATE           NULL,
    install_wait_days          INT            NULL,
    install_wait_band          VARCHAR(20)    NULL,
    order_status               VARCHAR(30)    NULL,
    is_install_resolved        TINYINT        NOT NULL,
    is_cancelled_pre_install   TINYINT        NOT NULL,
    cancel_date                DATE           NULL,
    activation_date            DATE           NULL,
    customer_id                VARCHAR(10)    NULL,
    churn_date                 DATE           NULL,
    eligible_90d               TINYINT        NULL,
    churned_90d                TINYINT        NULL,
    retained_90d_mrr           DECIMAL(10,2)  NOT NULL,
    CONSTRAINT PK_opportunity PRIMARY KEY (opp_id),
    CONSTRAINT FK_opp_lead FOREIGN KEY (lead_id) REFERENCES core.lead (lead_id),
    CONSTRAINT FK_opp_rep FOREIGN KEY (rep_id) REFERENCES core.rep (rep_id),
    CONSTRAINT FK_opp_product FOREIGN KEY (product_id) REFERENCES core.product (product_id),
    CONSTRAINT CK_opp_outcome CHECK (outcome IN ('Won', 'Lost', 'Open')),
    CONSTRAINT CK_opp_won_closed CHECK (is_won <= is_closed),
    CONSTRAINT CK_opp_discount CHECK (discount_pct BETWEEN 0 AND 100),
    CONSTRAINT CK_opp_price CHECK (mrr_gbp >= 0 AND mrr_gbp <= list_mrr_gbp),
    CONSTRAINT CK_opp_flags CHECK (is_closed IN (0, 1) AND is_won IN (0, 1) AND date_error IN (0, 1) AND is_install_resolved IN (0, 1) AND is_cancelled_pre_install IN (0, 1)),
    CONSTRAINT CK_opp_open_no_close CHECK (outcome <> 'Open' OR close_date IS NULL)
);
CREATE TABLE core.customer (
    customer_id                VARCHAR(10)    NOT NULL,
    opp_id                     VARCHAR(10)    NOT NULL,
    activation_date            DATE           NOT NULL,
    mrr_gbp                    DECIMAL(10,2)  NOT NULL,
    contract_months            SMALLINT       NOT NULL,
    churn_date                 DATE           NULL,
    churn_reason               NVARCHAR(60)   NULL,
    churn_date_error           TINYINT        NOT NULL,
    lead_source                VARCHAR(30)    NOT NULL,
    segment                    VARCHAR(20)    NOT NULL,
    region                     VARCHAR(40)    NOT NULL,
    team                       VARCHAR(30)    NOT NULL,
    channel                    VARCHAR(30)    NOT NULL,
    rep_id                     VARCHAR(10)    NOT NULL,
    discount_pct               SMALLINT       NOT NULL,
    product_name               NVARCHAR(50)   NOT NULL,
    is_churned                 TINYINT        NOT NULL,
    tenure_days                INT            NOT NULL,
    activation_month           CHAR(7)        NOT NULL,
    churn_month                CHAR(7)        NULL,
    eligible_90d               TINYINT        NOT NULL,
    churned_90d                TINYINT        NOT NULL,
    CONSTRAINT PK_customer PRIMARY KEY (customer_id),
    CONSTRAINT UQ_customer_opp UNIQUE (opp_id),
    CONSTRAINT FK_customer_opp FOREIGN KEY (opp_id) REFERENCES core.opportunity (opp_id),
    CONSTRAINT FK_customer_rep FOREIGN KEY (rep_id) REFERENCES core.rep (rep_id),
    CONSTRAINT CK_customer_flags CHECK (is_churned IN (0, 1) AND churn_date_error IN (0, 1) AND eligible_90d IN (0, 1) AND churned_90d IN (0, 1))
);
CREATE TABLE core.quota (
    rep_id                     VARCHAR(10)    NOT NULL,
    month                      CHAR(7)        NOT NULL,
    quota_mrr_gbp              DECIMAL(10,2)  NOT NULL,
    rep_name                   NVARCHAR(50)   NOT NULL,
    team                       VARCHAR(30)    NOT NULL,
    channel                    VARCHAR(30)    NOT NULL,
    CONSTRAINT PK_quota PRIMARY KEY (rep_id, month),
    CONSTRAINT FK_quota_rep FOREIGN KEY (rep_id) REFERENCES core.rep (rep_id),
    CONSTRAINT CK_quota_value CHECK (quota_mrr_gbp >= 0)
);
GO
-- Indexes for the joins and filters the analyses and BI views use most
CREATE INDEX IX_opp_lead      ON core.opportunity (lead_id);
CREATE INDEX IX_opp_close     ON core.opportunity (close_date) INCLUDE (is_won, is_closed, mrr_gbp, rep_id, lead_source);
CREATE INDEX IX_opp_rep_month ON core.opportunity (rep_id, close_month) INCLUDE (is_won, mrr_gbp);
CREATE INDEX IX_lead_created  ON core.lead (created_date) INCLUDE (lead_source, is_converted);
CREATE INDEX IX_customer_dates ON core.customer (activation_date, churn_date) INCLUDE (mrr_gbp, churn_date_error);
GO
-- Load audit tables (kept across runs)
IF OBJECT_ID(N'qa.conversion_check') IS NULL
    CREATE TABLE qa.conversion_check (run_at DATETIME2(0) NOT NULL, table_name SYSNAME NOT NULL, column_name SYSNAME NOT NULL,
        is_required BIT NOT NULL, failed_conversions INT NOT NULL, null_after_conversion INT NOT NULL, is_problem BIT NOT NULL);
IF OBJECT_ID(N'qa.load_log') IS NULL
    CREATE TABLE qa.load_log (run_at DATETIME2(0) NOT NULL, table_name SYSNAME NOT NULL, staged_rows INT NOT NULL, loaded_rows INT NOT NULL);
IF OBJECT_ID(N'qa.validation_result') IS NULL
    CREATE TABLE qa.validation_result (run_at DATETIME2(0) NOT NULL, check_name NVARCHAR(100) NOT NULL, expected DECIMAL(18,4) NOT NULL,
        actual DECIMAL(18,4) NULL, passed BIT NOT NULL);
GO
