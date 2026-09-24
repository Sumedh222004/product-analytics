/* ============================================================================
   19 | HEALTH SCORES — one number per customer, one per product
   ----------------------------------------------------------------------------
   Why scores? Ops and CRM teams cannot act on nine metrics at once. A single
   0-100 composite (with transparent weights) turns analysis into worklists:
   "call these stores", "win back these customers", "review these SKUs".

   A. Customer Health Score (as-of 2026-08-31), 0-100:
        Recency (30) + Frequency last 56d (25) + Monetary last 56d (20)
        + Experience last 90d (15) + Trend 28d vs prior 28d (10)
      Tiers: Healthy >= 75 | Stable 50-74 | At Risk 25-49 | Critical < 25

   B. Product Health Score (last 56 days), 0-100:
        Sales velocity (25) + GMV (20) + Margin % (20) + Buyer reach (20)
        + Sales consistency across weeks (15)
      Tiers: Star >= 80 | Solid 60-79 | Watch 40-59 | Review < 40
   ============================================================================ */

USE quickkart_analytics;
GO

/* ------------------------------ A. customers ------------------------------ */
CREATE OR ALTER VIEW dbo.vw_customer_health
AS
WITH base AS (
    SELECT  c.customer_id,
            DATEDIFF(DAY, MAX(d.order_ts), '2026-08-31')                    AS recency_days,
            SUM(CASE WHEN d.order_ts >= '2026-07-06' THEN 1 ELSE 0 END)     AS orders_56d,
            SUM(CASE WHEN d.order_ts >= '2026-07-06' THEN d.net_amount ELSE 0 END) AS spend_56d,
            SUM(CASE WHEN d.order_ts >= '2026-08-03' THEN 1 ELSE 0 END)     AS orders_last28,
            SUM(CASE WHEN d.order_ts >= '2026-07-06'
                      AND d.order_ts <  '2026-08-03' THEN 1 ELSE 0 END)     AS orders_prior28,
            AVG(CASE WHEN d.order_ts >= '2026-06-02'
                     THEN 1.0 * d.is_perfect_order END)                     AS perfect_rate_90d
    FROM dbo.dim_customer c
    JOIN dbo.vw_orders_delivered d ON d.customer_id = c.customer_id
    GROUP BY c.customer_id
),
scored AS (
    SELECT  b.customer_id, b.recency_days, b.orders_56d, b.spend_56d,
            b.orders_last28, b.orders_prior28,
            /* Recency - 30 pts */
            CASE WHEN b.recency_days <= 7  THEN 30
                 WHEN b.recency_days <= 14 THEN 24
                 WHEN b.recency_days <= 28 THEN 18
                 WHEN b.recency_days <= 42 THEN 10
                 WHEN b.recency_days <= 56 THEN 5
                 ELSE 0 END
            /* Frequency - 25 pts */
          + CASE WHEN b.orders_56d >= 8 THEN 25
                 WHEN b.orders_56d >= 5 THEN 20
                 WHEN b.orders_56d >= 3 THEN 15
                 WHEN b.orders_56d =  2 THEN 10
                 WHEN b.orders_56d =  1 THEN 5
                 ELSE 0 END
            /* Monetary - 20 pts */
          + CASE WHEN b.spend_56d >= 4000 THEN 20
                 WHEN b.spend_56d >= 2500 THEN 16
                 WHEN b.spend_56d >= 1500 THEN 12
                 WHEN b.spend_56d >=  750 THEN 8
                 WHEN b.spend_56d >     0 THEN 4
                 ELSE 0 END
            /* Experience - 15 pts */
          + CASE WHEN b.perfect_rate_90d >= 0.90 THEN 15
                 WHEN b.perfect_rate_90d >= 0.75 THEN 12
                 WHEN b.perfect_rate_90d >= 0.60 THEN 8
                 WHEN b.perfect_rate_90d >= 0.40 THEN 4
                 WHEN b.perfect_rate_90d IS NULL THEN 0
                 ELSE 0 END
            /* Trend - 10 pts */
          + CASE WHEN b.orders_last28 > b.orders_prior28 THEN 10
                 WHEN b.orders_last28 = b.orders_prior28
                      AND b.orders_last28 > 0            THEN 6
                 WHEN b.orders_last28 < b.orders_prior28 THEN 2
                 ELSE 0 END                                    AS health_score
    FROM base b
)
SELECT  s.*,
        CASE WHEN s.health_score >= 75 THEN '1_Healthy'
             WHEN s.health_score >= 50 THEN '2_Stable'
             WHEN s.health_score >= 25 THEN '3_At_Risk'
             ELSE '4_Critical' END AS health_tier
FROM scored s;
GO

/* tier distribution + how much recent revenue each tier represents */
SELECT  health_tier,
        COUNT(*)                                                   AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_of_base,
        CAST(AVG(1.0 * health_score) AS DECIMAL(5,1))              AS avg_score,
        SUM(spend_56d)                                             AS spend_56d_rs,
        CAST(100.0 * SUM(spend_56d) / NULLIF(SUM(SUM(spend_56d)) OVER (), 0)
             AS DECIMAL(5,1))                                      AS spend_share_pct
FROM dbo.vw_customer_health
GROUP BY health_tier
ORDER BY health_tier;

/* cross-check: health tier x home zone — stressed zones should skew unhealthy */
SELECT  CASE WHEN c.home_store_id IN (4, 6) THEN 'stressed_zone' ELSE 'other_zones' END AS zone_group,
        h.health_tier,
        COUNT(*) AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY
             CASE WHEN c.home_store_id IN (4, 6) THEN 'stressed_zone' ELSE 'other_zones' END)
             AS DECIMAL(5,1)) AS pct_within_zone
FROM dbo.vw_customer_health h
JOIN dbo.dim_customer c ON c.customer_id = h.customer_id
GROUP BY CASE WHEN c.home_store_id IN (4, 6) THEN 'stressed_zone' ELSE 'other_zones' END,
         h.health_tier
ORDER BY zone_group, health_tier;
GO

/* ------------------------------- B. products ------------------------------ */
CREATE OR ALTER VIEW dbo.vw_product_health
AS
WITH sales AS (
    SELECT  i.product_id,
            SUM(i.quantity)                                   AS units_56d,
            SUM(i.line_amount)                                AS gmv_56d,
            SUM(i.line_amount - i.quantity * p.unit_cost)     AS margin_56d,
            COUNT(DISTINCT d.customer_id)                     AS buyers_56d,
            /* the 57-day window touches 9 Mondays; cap at 8 full weeks */
            CASE WHEN COUNT(DISTINCT dd.week_start) > 8 THEN 8
                 ELSE COUNT(DISTINCT dd.week_start) END       AS weeks_sold_of_8
    FROM dbo.fact_order_items i
    JOIN dbo.vw_orders_delivered d ON d.order_id = i.order_id
    JOIN dbo.dim_product p         ON p.product_id = i.product_id
    JOIN dbo.dim_date dd           ON dd.date_key = d.order_date
    WHERE d.order_ts >= '2026-07-06'
    GROUP BY i.product_id
),
scored AS (
    SELECT  p.product_id, p.product_name, p.category, p.is_private_label,
            COALESCE(s.units_56d, 0)  AS units_56d,
            COALESCE(s.gmv_56d, 0)    AS gmv_56d,
            COALESCE(s.buyers_56d, 0) AS buyers_56d,
            CAST(100.0 * s.margin_56d / NULLIF(s.gmv_56d, 0) AS DECIMAL(5,1)) AS margin_pct,
            COALESCE(s.weeks_sold_of_8, 0) AS weeks_sold_of_8,
            /* velocity 25 + gmv 20 + margin 20 + reach 20: quintile x weight */
            5 * NTILE(5) OVER (ORDER BY COALESCE(s.units_56d, 0))                        -- 5..25
          + 4 * NTILE(5) OVER (ORDER BY COALESCE(s.gmv_56d, 0))                          -- 4..20
          + 4 * NTILE(5) OVER (ORDER BY COALESCE(1.0 * s.margin_56d / NULLIF(s.gmv_56d, 0), 0)) -- 4..20
          + 4 * NTILE(5) OVER (ORDER BY COALESCE(s.buyers_56d, 0))                       -- 4..20
          + CAST(15.0 * COALESCE(s.weeks_sold_of_8, 0) / 8 AS INT)                       -- 0..15
                                        AS health_score
    FROM dbo.dim_product p
    LEFT JOIN sales s ON s.product_id = p.product_id
)
SELECT  sc.*,
        CASE WHEN sc.health_score >= 80 THEN '1_Star'
             WHEN sc.health_score >= 60 THEN '2_Solid'
             WHEN sc.health_score >= 40 THEN '3_Watch'
             ELSE '4_Review' END AS health_tier
FROM scored sc;
GO

/* tier mix by category + the bottom SKUs an analyst would flag for review
   (candidates for delisting, repricing, or bundling) */
SELECT  category,
        SUM(CASE WHEN health_tier = '1_Star'   THEN 1 ELSE 0 END) AS star,
        SUM(CASE WHEN health_tier = '2_Solid'  THEN 1 ELSE 0 END) AS solid,
        SUM(CASE WHEN health_tier = '3_Watch'  THEN 1 ELSE 0 END) AS watch,
        SUM(CASE WHEN health_tier = '4_Review' THEN 1 ELSE 0 END) AS review
FROM dbo.vw_product_health
GROUP BY category
ORDER BY review DESC;

SELECT TOP (20)
        product_id, product_name, category, health_score,
        units_56d, buyers_56d, margin_pct
FROM dbo.vw_product_health
ORDER BY health_score ASC, units_56d ASC;
