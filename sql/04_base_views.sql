/* ============================================================================
   04 | BASE VIEWS — the reusable building blocks of every analysis
   ----------------------------------------------------------------------------
   Three views the whole project stands on:

   vw_orders_delivered   delivered orders + experience flags + date attributes
                         + is_first_order derived with a window function
   vw_customer_first     one row per customer: signup, first order, activation
                         status, and the quality of the FIRST order experience
   vw_order_margin       per-order contribution economics (item margin from
                         the basket, fees, discounts, and a last-mile cost
                         assumption)

   Definitions live in docs/metric_definitions.md.
   ============================================================================ */

USE quickkart_analytics;
GO

/* --------------------------------------------------------------------------
   4.1 Delivered orders, enriched.
       late_by_min : minutes past the promise (0 if on time)
       is_perfect_order : delivered on time AND complete — the operations
                          north-star used across marketplace health & HEART
   -------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_orders_delivered
AS
SELECT  o.order_id,
        o.customer_id,
        o.store_id,
        o.order_ts,
        CAST(o.order_ts AS DATE)                                  AS order_date,
        DATEFROMPARTS(YEAR(o.order_ts), MONTH(o.order_ts), 1)     AS order_month,
        o.promised_min,
        o.actual_delivery_min,
        CASE WHEN o.actual_delivery_min > o.promised_min
             THEN o.actual_delivery_min - o.promised_min ELSE 0 END AS late_by_min,
        CASE WHEN o.actual_delivery_min <= o.promised_min THEN 1 ELSE 0 END AS is_on_time,
        CASE WHEN o.actual_delivery_min >  o.promised_min + 5 THEN 1 ELSE 0 END AS is_late_5plus,
        CAST(o.items_missing AS INT)                              AS items_missing,
        CASE WHEN o.actual_delivery_min <= o.promised_min
              AND o.items_missing = 0 THEN 1 ELSE 0 END           AS is_perfect_order,
        o.item_total,
        o.discount_amount,
        o.delivery_fee,
        o.handling_fee,
        o.net_amount,
        o.payment_method,
        o.rating,
        CASE WHEN ROW_NUMBER() OVER (PARTITION BY o.customer_id
                                     ORDER BY o.order_ts, o.order_id) = 1
             THEN 1 ELSE 0 END                                    AS is_first_order
FROM dbo.fact_orders o
WHERE o.status = 'delivered';
GO

/* --------------------------------------------------------------------------
   4.2 Customer spine: signup -> first order -> first-order experience.
       activated_7d = first delivered order within 7 days of signup (the
       project's activation definition).
       bad_first_experience = first order arrived >5 min late OR incomplete
       (this flag is the heart of the activation-cliff insight).
   -------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_customer_first
AS
WITH firsts AS
(
    SELECT  d.customer_id,
            d.order_ts          AS first_order_ts,
            d.late_by_min       AS first_late_by_min,
            d.items_missing     AS first_items_missing,
            d.is_late_5plus     AS first_late_5plus,
            d.store_id          AS first_store_id
    FROM dbo.vw_orders_delivered d
    WHERE d.is_first_order = 1
)
SELECT  c.customer_id,
        c.signup_ts,
        CAST(c.signup_ts AS DATE)                                  AS signup_date,
        DATEFROMPARTS(YEAR(c.signup_ts), MONTH(c.signup_ts), 1)    AS cohort_month,
        c.acquisition_channel,
        c.platform,
        c.home_store_id,
        f.first_order_ts,
        f.first_store_id,
        DATEDIFF(HOUR, c.signup_ts, f.first_order_ts) / 24.0       AS days_to_first_order,
        CASE WHEN f.first_order_ts IS NOT NULL
              AND f.first_order_ts <= DATEADD(DAY, 7, c.signup_ts)
             THEN 1 ELSE 0 END                                     AS activated_7d,
        CASE WHEN f.customer_id IS NULL THEN 1 ELSE 0 END          AS never_ordered,
        CASE WHEN f.first_late_5plus = 1 OR f.first_items_missing = 1
             THEN 1 ELSE 0 END                                     AS bad_first_experience
FROM dbo.dim_customer c
LEFT JOIN firsts f
       ON f.customer_id = c.customer_id;
GO

/* --------------------------------------------------------------------------
   4.3 Order-level contribution economics.
       item_margin      = SUM(line_amount - quantity * unit_cost)  from basket
       contribution     = item_margin + fees - discount - @last-mile cost
       Last-mile cost is an ASSUMPTION (Rs 30/delivered order, documented in
       metric_definitions.md) — call it out as such in interviews.
   -------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_order_margin
AS
SELECT  d.order_id,
        d.customer_id,
        d.store_id,
        d.order_month,
        d.order_ts,
        d.item_total,
        m.item_margin,
        d.discount_amount,
        d.delivery_fee + d.handling_fee                            AS fees_collected,
        m.item_margin + d.delivery_fee + d.handling_fee
            - d.discount_amount - 30                               AS contribution_rs
FROM dbo.vw_orders_delivered d
JOIN (
        SELECT  i.order_id,
                SUM(i.line_amount - i.quantity * p.unit_cost)      AS item_margin
        FROM dbo.fact_order_items i
        JOIN dbo.dim_product p ON p.product_id = i.product_id
        GROUP BY i.order_id
     ) m
  ON m.order_id = d.order_id;
GO

PRINT 'Base views created: vw_orders_delivered, vw_customer_first, vw_order_margin';
