/* ============================================================================
   20 | POWER BI FEED VIEWS
   ----------------------------------------------------------------------------
   Import THESE views into Power BI (never the raw tables):
     * facts stay at useful grain, dims carry the enriched attributes,
     * the 1.45M-row event log is pre-aggregated to month x platform x channel
       so the model stays small and fast.

   Import list:
     vw_pbi_dim_date, vw_pbi_dim_store, vw_pbi_dim_product, vw_pbi_dim_customer
     vw_pbi_fact_orders, vw_pbi_funnel_monthly, vw_pbi_cohort_retention,
     vw_pbi_store_month_ops, vw_pbi_marketing

   Depends on: 04, 12, 13, 15, 17, 19 (run those first).
   ============================================================================ */

USE quickkart_analytics;
GO

CREATE OR ALTER VIEW dbo.vw_pbi_dim_date AS
SELECT date_key, [year], [month], month_start, month_name, year_month,
       [day], day_of_week, day_name, is_weekend, week_start
FROM dbo.dim_date;
GO

CREATE OR ALTER VIEW dbo.vw_pbi_dim_store AS
SELECT store_id, store_code, zone_name, city, launch_date, base_promise_min,
       CASE WHEN store_id IN (4, 6) THEN 'High demand growth' ELSE 'Standard' END AS capacity_profile
FROM dbo.dim_store;
GO

CREATE OR ALTER VIEW dbo.vw_pbi_dim_product AS
SELECT p.product_id, p.product_name, p.category, p.unit_price, p.unit_cost,
       p.is_private_label, ph.health_score AS product_health_score,
       ph.health_tier AS product_health_tier
FROM dbo.dim_product p
LEFT JOIN dbo.vw_product_health ph ON ph.product_id = p.product_id;
GO

CREATE OR ALTER VIEW dbo.vw_pbi_dim_customer AS
SELECT  cf.customer_id,
        cf.signup_date,
        cf.cohort_month,
        cf.acquisition_channel,
        cf.platform,
        cf.home_store_id,
        cf.activated_7d,
        cf.never_ordered,
        cf.bad_first_experience,
        r.rfm_segment,
        h.health_tier          AS customer_health_tier,
        h.health_score         AS customer_health_score
FROM dbo.vw_customer_first cf
LEFT JOIN dbo.vw_customer_rfm    r ON r.customer_id = cf.customer_id
LEFT JOIN dbo.vw_customer_health h ON h.customer_id = cf.customer_id;
GO

CREATE OR ALTER VIEW dbo.vw_pbi_fact_orders AS
SELECT  o.order_id,
        o.customer_id,
        o.store_id,
        CAST(o.order_ts AS DATE)  AS order_date,
        o.status,
        o.promised_min,
        o.actual_delivery_min,
        CASE WHEN o.status = 'delivered'
              AND o.actual_delivery_min <= o.promised_min THEN 1 ELSE 0 END AS is_on_time,
        CASE WHEN o.status = 'delivered'
              AND o.actual_delivery_min > o.promised_min + 5 THEN 1 ELSE 0 END AS is_late_5plus,
        CAST(o.items_missing AS INT) AS items_missing,
        CASE WHEN o.status = 'delivered'
              AND o.actual_delivery_min <= o.promised_min
              AND o.items_missing = 0 THEN 1 ELSE 0 END AS is_perfect_order,
        o.item_total,
        o.discount_amount,
        o.delivery_fee,
        o.handling_fee,
        o.net_amount,
        o.payment_method,
        o.rating,
        om.item_margin,
        om.contribution_rs
FROM dbo.fact_orders o
LEFT JOIN dbo.vw_order_margin om ON om.order_id = o.order_id;
GO

/* month x platform x channel funnel aggregate (small + slice-able) */
CREATE OR ALTER VIEW dbo.vw_pbi_funnel_monthly AS
SELECT  f.session_month,
        f.platform,
        c.acquisition_channel,
        COUNT(*)                  AS sessions,
        SUM(f.used_search)        AS searched,
        SUM(f.reached_pv)         AS reached_product_view,
        SUM(f.reached_cart)       AS reached_cart,
        SUM(f.reached_checkout)   AS reached_checkout,
        SUM(f.converted)          AS converted
FROM dbo.vw_session_funnel f
JOIN dbo.dim_customer c ON c.customer_id = f.customer_id
GROUP BY f.session_month, f.platform, c.acquisition_channel;
GO

/* cohort x offset counts; % is a DAX division so slicers stay honest */
CREATE OR ALTER VIEW dbo.vw_pbi_cohort_retention AS
WITH size_ AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM dbo.vw_customer_first
    GROUP BY cohort_month
)
SELECT  a.cohort_month,
        a.month_offset,
        s.cohort_size,
        COUNT(DISTINCT a.customer_id) AS active_customers
FROM dbo.vw_cohort_activity a
JOIN size_ s ON s.cohort_month = a.cohort_month
GROUP BY a.cohort_month, a.month_offset, s.cohort_size;
GO

CREATE OR ALTER VIEW dbo.vw_pbi_store_month_ops AS
SELECT * FROM dbo.vw_store_month_ops;
GO

/* marketing spend + signups + activations by month x channel (CAC visuals) */
CREATE OR ALTER VIEW dbo.vw_pbi_marketing AS
SELECT  ms.month_start,
        ms.channel,
        ms.spend_inr,
        c.signups,
        c.activated_7d
FROM dbo.fact_marketing_spend ms
LEFT JOIN (
    SELECT cohort_month, acquisition_channel,
           COUNT(*) AS signups, SUM(activated_7d) AS activated_7d
    FROM dbo.vw_customer_first
    GROUP BY cohort_month, acquisition_channel
) c ON c.cohort_month = ms.month_start AND c.acquisition_channel = ms.channel;
GO

PRINT 'Power BI feed views ready (9 views).';
