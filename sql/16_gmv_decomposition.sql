/* ============================================================================
   16 | GMV DECOMPOSITION — what is actually driving growth?
   ----------------------------------------------------------------------------
   Identity:  GMV = Active customers x Orders per active x AOV
   A month-over-month GMV change is attributed to the three drivers by
   sequential substitution. This split is EXACT (check_diff ~ 0, rounding
   aside) but order-dependent — swapping the substitution order shifts a small
   interaction between drivers. Say so when you present it.

   Business questions
     A. Monthly KPI base (GMV, actives, orders/active, AOV, discount rate)
     B. MoM GMV bridge: driver attribution
     C. Growth accounting: GMV from new vs retained vs reactivated customers
     D. Category mix & margin: where GMV and PROFIT come from (S5 story)
   ============================================================================ */

USE quickkart_analytics;
GO

/* ---------------------------------------------------------------------------
   A. Monthly KPI base
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_monthly_kpis
AS
SELECT  d.order_month,
        COUNT(DISTINCT d.customer_id)                        AS active_customers,
        COUNT(*)                                             AS orders,
        SUM(d.item_total)                                    AS gmv_rs,
        SUM(d.net_amount)                                    AS net_revenue_rs,
        SUM(d.discount_amount)                               AS discounts_rs,
        CAST(1.0 * COUNT(*) / COUNT(DISTINCT d.customer_id) AS DECIMAL(6,2)) AS orders_per_active,
        CAST(1.0 * SUM(d.item_total) / COUNT(*)  AS DECIMAL(8,0))            AS aov_rs,
        CAST(100.0 * SUM(d.discount_amount) / SUM(d.item_total) AS DECIMAL(5,1)) AS discount_rate_pct,
        CAST(100.0 * AVG(1.0 * d.is_perfect_order) AS DECIMAL(5,1))          AS perfect_order_pct
FROM dbo.vw_orders_delivered d
GROUP BY d.order_month;
GO

SELECT * FROM dbo.vw_monthly_kpis ORDER BY order_month;

/* ---------------------------------------------------------------------------
   B. MoM GMV bridge (sequential substitution)
        actives_effect = dActives x OPA_prev x AOV_prev
        opa_effect     = Actives_cur x dOPA x AOV_prev
        aov_effect     = Actives_cur x OPA_cur x dAOV ... equivalent algebra:
      here: aov_effect  = Orders_cur x dAOV
            opa_effect  = (Orders_cur - dActives x OPA_prev - Actives_prev x OPA_prev) x AOV_prev
      Simpler exact split used below:
        dGMV = dActives*OPA_prev*AOV_prev            (more/less customers)
             + Actives_cur*dOPA*AOV_prev             (each ordering more/less)
             + Actives_cur*OPA_cur*dAOV              (bigger/smaller baskets)
      which telescopes exactly: check_diff should be ~0.
   --------------------------------------------------------------------------- */
WITH k AS (
    SELECT  order_month, gmv_rs, active_customers,
            1.0 * orders / active_customers  AS opa,
            1.0 * gmv_rs / orders            AS aov,
            LAG(gmv_rs)            OVER (ORDER BY order_month) AS gmv_prev,
            LAG(active_customers)  OVER (ORDER BY order_month) AS act_prev,
            LAG(1.0 * orders / active_customers) OVER (ORDER BY order_month) AS opa_prev,
            LAG(1.0 * gmv_rs / orders)           OVER (ORDER BY order_month) AS aov_prev
    FROM dbo.vw_monthly_kpis
)
SELECT  order_month,
        gmv_rs,
        gmv_rs - gmv_prev                                             AS gmv_change_rs,
        CAST((active_customers - act_prev) * opa_prev * aov_prev AS DECIMAL(12,0)) AS from_active_customers,
        CAST(active_customers * (opa - opa_prev) * aov_prev      AS DECIMAL(12,0)) AS from_order_frequency,
        CAST(active_customers * opa * (aov - aov_prev)           AS DECIMAL(12,0)) AS from_basket_size,
        CAST( (gmv_rs - gmv_prev)
            - (active_customers - act_prev) * opa_prev * aov_prev
            - active_customers * (opa - opa_prev) * aov_prev
            - active_customers * opa * (aov - aov_prev)          AS DECIMAL(12,0)) AS check_diff
FROM k
WHERE gmv_prev IS NOT NULL
ORDER BY order_month;

/* ---------------------------------------------------------------------------
   C. Growth accounting: each month's GMV split by customer state
        new         first-ever order this month
        retained    also ordered last month
        reactivated ordered before, but not last month
   --------------------------------------------------------------------------- */
WITH cust_month AS (
    SELECT  customer_id, order_month, SUM(item_total) AS gmv_rs,
            MIN(order_month) OVER (PARTITION BY customer_id) AS first_month,
            LAG(order_month) OVER (PARTITION BY customer_id ORDER BY order_month) AS prev_active_month
    FROM dbo.vw_orders_delivered
    GROUP BY customer_id, order_month
)
SELECT  order_month,
        SUM(CASE WHEN order_month = first_month THEN gmv_rs ELSE 0 END)                       AS gmv_new,
        SUM(CASE WHEN order_month > first_month
                  AND prev_active_month = DATEADD(MONTH, -1, order_month) THEN gmv_rs ELSE 0 END) AS gmv_retained,
        SUM(CASE WHEN order_month > first_month
                  AND (prev_active_month IS NULL
                       OR prev_active_month < DATEADD(MONTH, -1, order_month)) THEN gmv_rs ELSE 0 END) AS gmv_reactivated,
        SUM(gmv_rs)                                                                            AS gmv_total
FROM cust_month
GROUP BY order_month
ORDER BY order_month;

/* ---------------------------------------------------------------------------
   D1. Category GMV mix by month (feed for the mix-shift chart)
   --------------------------------------------------------------------------- */
SELECT  d.order_month,
        p.category,
        SUM(i.line_amount)                        AS gmv_rs,
        SUM(i.line_amount - i.quantity * p.unit_cost) AS item_margin_rs
FROM dbo.vw_orders_delivered d
JOIN dbo.fact_order_items i ON i.order_id = d.order_id
JOIN dbo.dim_product p      ON p.product_id = i.product_id
GROUP BY d.order_month, p.category
ORDER BY d.order_month, gmv_rs DESC;

/* ---------------------------------------------------------------------------
   D2. The monetization story (S5): contribution per order by customer tenure.
       Older customers attach more high-margin categories -> margin per order
       climbs with tenure even while AOV moves less.
   --------------------------------------------------------------------------- */
SELECT  CASE WHEN DATEDIFF(MONTH, cf.cohort_month, om.order_month) = 0            THEN '1_month_0'
             WHEN DATEDIFF(MONTH, cf.cohort_month, om.order_month) BETWEEN 1 AND 2 THEN '2_months_1_2'
             WHEN DATEDIFF(MONTH, cf.cohort_month, om.order_month) BETWEEN 3 AND 5 THEN '3_months_3_5'
             ELSE '4_months_6_plus' END                       AS tenure_bucket,
        COUNT(*)                                              AS orders,
        CAST(AVG(1.0 * om.item_total)      AS DECIMAL(8,0))   AS aov_rs,
        CAST(AVG(1.0 * om.item_margin)     AS DECIMAL(8,0))   AS item_margin_per_order_rs,
        CAST(AVG(1.0 * om.contribution_rs) AS DECIMAL(8,0))   AS contribution_per_order_rs,
        CAST(100.0 * SUM(om.item_margin) / SUM(om.item_total) AS DECIMAL(5,1)) AS item_margin_pct
FROM dbo.vw_order_margin om
JOIN dbo.vw_customer_first cf ON cf.customer_id = om.customer_id
GROUP BY CASE WHEN DATEDIFF(MONTH, cf.cohort_month, om.order_month) = 0            THEN '1_month_0'
              WHEN DATEDIFF(MONTH, cf.cohort_month, om.order_month) BETWEEN 1 AND 2 THEN '2_months_1_2'
              WHEN DATEDIFF(MONTH, cf.cohort_month, om.order_month) BETWEEN 3 AND 5 THEN '3_months_3_5'
              ELSE '4_months_6_plus' END
ORDER BY tenure_bucket;
