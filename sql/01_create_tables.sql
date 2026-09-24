/* ============================================================================
   01 | STAR SCHEMA — TABLES + DATE DIMENSION
   ----------------------------------------------------------------------------
   Grain of each table:
     dim_customer         1 row per registered customer
     dim_store            1 row per dark store
     dim_product          1 row per SKU
     dim_date             1 row per calendar day (covers the analysis window)
     fact_orders          1 row per order (delivered or cancelled)
     fact_order_items     1 row per order x SKU
     fact_app_events      1 row per in-app event (funnel event log)
     fact_marketing_spend 1 row per month x acquisition channel

   Design choices worth explaining in an interview:
     * Money is stored as whole rupees (INT) — no floating point drift.
     * fact_app_events is a second fact table at event grain; it deliberately
       has no surrogate key (analysis is by session_id / event_ts).
     * Nonclustered indexes + foreign keys are added AFTER the bulk load
       (03_load_quality_and_indexes.sql) — loading into indexed tables is slow.
   ============================================================================ */

USE quickkart_analytics;
GO

/* drop children first, then parents (idempotent re-runs) */
DROP TABLE IF EXISTS dbo.fact_app_events;
DROP TABLE IF EXISTS dbo.fact_order_items;
DROP TABLE IF EXISTS dbo.fact_orders;
DROP TABLE IF EXISTS dbo.fact_marketing_spend;
DROP TABLE IF EXISTS dbo.dim_customer;
DROP TABLE IF EXISTS dbo.dim_product;
DROP TABLE IF EXISTS dbo.dim_store;
DROP TABLE IF EXISTS dbo.dim_date;
GO

CREATE TABLE dbo.dim_store (
    store_id          INT          NOT NULL CONSTRAINT pk_dim_store PRIMARY KEY,
    store_code        VARCHAR(20)  NOT NULL,
    zone_name         VARCHAR(40)  NOT NULL,
    city              VARCHAR(40)  NOT NULL,
    launch_date       DATE         NOT NULL,
    base_promise_min  TINYINT      NOT NULL
);
GO

CREATE TABLE dbo.dim_product (
    product_id        INT          NOT NULL CONSTRAINT pk_dim_product PRIMARY KEY,
    product_name      VARCHAR(80)  NOT NULL,
    category          VARCHAR(40)  NOT NULL,
    unit_price        INT          NOT NULL,   -- current catalog price (Rs)
    unit_cost         INT          NOT NULL,   -- cost of goods (Rs)
    is_private_label  BIT          NOT NULL
);
GO

CREATE TABLE dbo.dim_customer (
    customer_id          INT          NOT NULL CONSTRAINT pk_dim_customer PRIMARY KEY,
    signup_ts            DATETIME2(0) NOT NULL,
    acquisition_channel  VARCHAR(20)  NOT NULL,
    platform             VARCHAR(10)  NOT NULL,   -- android | ios
    home_store_id        INT          NOT NULL
);
GO

CREATE TABLE dbo.fact_orders (
    order_id             INT          NOT NULL CONSTRAINT pk_fact_orders PRIMARY KEY,
    customer_id          INT          NOT NULL,
    store_id             INT          NOT NULL,
    order_ts             DATETIME2(0) NOT NULL,
    status               VARCHAR(10)  NOT NULL,   -- delivered | cancelled
    promised_min         TINYINT      NOT NULL,   -- promised delivery time
    actual_delivery_min  SMALLINT     NULL,       -- NULL for cancelled orders
    item_total           INT          NOT NULL,   -- basket value before discount (GMV)
    discount_amount      INT          NOT NULL,
    delivery_fee         TINYINT      NOT NULL,
    handling_fee         TINYINT      NOT NULL,
    net_amount           INT          NOT NULL,   -- item_total - discount + fees
    payment_method       VARCHAR(10)  NOT NULL,
    rating               TINYINT      NULL,       -- 1-5, ~half of delivered orders
    items_missing        BIT          NOT NULL    -- 1 = order arrived incomplete
);
GO

CREATE TABLE dbo.fact_order_items (
    order_id     INT      NOT NULL,
    product_id   INT      NOT NULL,
    quantity     SMALLINT NOT NULL,
    unit_price   INT      NOT NULL,   -- transacted price (Rs)
    line_amount  INT      NOT NULL,   -- quantity * unit_price
    CONSTRAINT pk_fact_order_items PRIMARY KEY (order_id, product_id)
);
GO

CREATE TABLE dbo.fact_app_events (
    session_id   INT          NOT NULL,
    customer_id  INT          NOT NULL,
    event_name   VARCHAR(20)  NOT NULL,  -- app_open | search | product_view
                                          -- | add_to_cart | checkout_start
                                          -- | payment_success
    event_ts     DATETIME2(0) NOT NULL,
    platform     VARCHAR(10)  NOT NULL,
    order_id     INT          NULL       -- populated on payment_success only
);
GO

CREATE TABLE dbo.fact_marketing_spend (
    month_start  DATE         NOT NULL,
    channel      VARCHAR(20)  NOT NULL,
    spend_inr    INT          NOT NULL,
    CONSTRAINT pk_fact_marketing_spend PRIMARY KEY (month_start, channel)
);
GO

/* ---------------------------------------------------------------------------
   dim_date — one row per day, 2025-08-01 .. 2026-09-30 (pads the data window).
   Day-of-week trick: 1900-01-01 was a Monday, so DATEDIFF(DAY,'19000101',d)%7
   gives 0=Mon..6=Sun independent of server DATEFIRST settings.
   --------------------------------------------------------------------------- */
CREATE TABLE dbo.dim_date (
    date_key     DATE        NOT NULL CONSTRAINT pk_dim_date PRIMARY KEY,
    [year]       SMALLINT    NOT NULL,
    [month]      TINYINT     NOT NULL,
    month_start  DATE        NOT NULL,
    month_name   VARCHAR(10) NOT NULL,
    year_month   CHAR(7)     NOT NULL,   -- '2026-05'
    [day]        TINYINT     NOT NULL,
    day_of_week  TINYINT     NOT NULL,   -- 0 = Monday ... 6 = Sunday
    day_name     VARCHAR(10) NOT NULL,
    is_weekend   BIT         NOT NULL,
    week_start   DATE        NOT NULL    -- Monday of that week
);
GO

;WITH n AS (
    SELECT TOP (500)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects
),
d AS (
    SELECT DATEADD(DAY, i, CAST('2025-08-01' AS DATE)) AS date_key
    FROM n
    WHERE DATEADD(DAY, i, CAST('2025-08-01' AS DATE)) <= '2026-09-30'
)
INSERT INTO dbo.dim_date
        (date_key, [year], [month], month_start, month_name, year_month,
         [day], day_of_week, day_name, is_weekend, week_start)
SELECT  date_key,
        YEAR(date_key),
        MONTH(date_key),
        DATEFROMPARTS(YEAR(date_key), MONTH(date_key), 1),
        DATENAME(MONTH, date_key),
        CONVERT(CHAR(7), date_key, 126),
        DAY(date_key),
        DATEDIFF(DAY, '19000101', date_key) % 7,
        DATENAME(WEEKDAY, date_key),
        CASE WHEN DATEDIFF(DAY, '19000101', date_key) % 7 >= 5 THEN 1 ELSE 0 END,
        DATEADD(DAY, -(DATEDIFF(DAY, '19000101', date_key) % 7), date_key)
FROM d;
GO

PRINT 'Star schema created. dim_date populated: '
      + CAST((SELECT COUNT(*) FROM dbo.dim_date) AS VARCHAR(10)) + ' days.';
