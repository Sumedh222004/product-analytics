/* ============================================================================
   17 | MARKETPLACE / OPS HEALTH — the supply side of the growth loop
   ----------------------------------------------------------------------------
   Quick commerce lives or dies on the promise. This module builds the store
   scorecard and quantifies the May-2026 degradation in Whitefield &
   Marathahalli — then connects ops failure to demand-side damage.

   Business questions
     A. Store x month ops scorecard (the ops review table)
     B. Before/after May: which stores broke, and by how much?
     C. Demand heatmap (day-of-week x hour) — staffing/capacity planning input
     D. Ops -> demand: next-month repeat rate of a store's customers vs the
        store's on-time rate that month (the marketplace flywheel, quantified)
   ============================================================================ */

USE quickkart_analytics;
GO

/* ---------------------------------------------------------------------------
   A. Store x month scorecard (delivered + cancelled both matter here)
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_store_month_ops
AS
SELECT  o.store_id,
        s.zone_name,
        DATEFROMPARTS(YEAR(o.order_ts), MONTH(o.order_ts), 1)    AS order_month,
        COUNT(*)                                                 AS orders_placed,
        SUM(CASE WHEN o.status = 'cancelled' THEN 1 ELSE 0 END)  AS cancelled,
        CAST(100.0 * SUM(CASE WHEN o.status = 'cancelled' THEN 1 ELSE 0 END)
             / COUNT(*) AS DECIMAL(5,1))                         AS cancel_pct,
        CAST(AVG(CASE WHEN o.status = 'delivered'
                 THEN 1.0 * o.actual_delivery_min END) AS DECIMAL(5,1)) AS avg_delivery_min,
        CAST(100.0 * AVG(CASE WHEN o.status = 'delivered' THEN
                 CASE WHEN o.actual_delivery_min <= o.promised_min THEN 1.0 ELSE 0 END END)
             AS DECIMAL(5,1))                                    AS on_time_pct,
        CAST(100.0 * AVG(CASE WHEN o.status = 'delivered' THEN
                 CASE WHEN o.actual_delivery_min > o.promised_min + 5 THEN 1.0 ELSE 0 END END)
             AS DECIMAL(5,1))                                    AS late_5plus_pct,
        CAST(100.0 * AVG(CASE WHEN o.status = 'delivered'
                 THEN 1.0 * o.items_missing END) AS DECIMAL(5,1)) AS items_missing_pct,
        CAST(100.0 * AVG(CASE WHEN o.status = 'delivered' THEN
                 CASE WHEN o.actual_delivery_min <= o.promised_min AND o.items_missing = 0
                      THEN 1.0 ELSE 0 END END) AS DECIMAL(5,1))  AS perfect_order_pct,
        CAST(AVG(1.0 * o.rating) AS DECIMAL(4,2))                AS avg_rating
FROM dbo.fact_orders o
JOIN dbo.dim_store s ON s.store_id = o.store_id
GROUP BY o.store_id, s.zone_name,
         DATEFROMPARTS(YEAR(o.order_ts), MONTH(o.order_ts), 1);
GO

SELECT * FROM dbo.vw_store_month_ops
ORDER BY order_month, store_id;

/* ---------------------------------------------------------------------------
   B. Pre vs post May per store — rank the damage
   --------------------------------------------------------------------------- */
SELECT  store_id,
        zone_name,
        CAST(AVG(CASE WHEN order_month <  '2026-05-01' THEN on_time_pct END) AS DECIMAL(5,1)) AS on_time_pre_may,
        CAST(AVG(CASE WHEN order_month >= '2026-05-01' THEN on_time_pct END) AS DECIMAL(5,1)) AS on_time_post_may,
        CAST(AVG(CASE WHEN order_month >= '2026-05-01' THEN on_time_pct END)
           - AVG(CASE WHEN order_month <  '2026-05-01' THEN on_time_pct END) AS DECIMAL(5,1)) AS on_time_delta_pp,
        CAST(AVG(CASE WHEN order_month <  '2026-05-01' THEN avg_rating END) AS DECIMAL(4,2))  AS rating_pre_may,
        CAST(AVG(CASE WHEN order_month >= '2026-05-01' THEN avg_rating END) AS DECIMAL(4,2))  AS rating_post_may
FROM dbo.vw_store_month_ops
GROUP BY store_id, zone_name
ORDER BY on_time_delta_pp ASC;

/* ---------------------------------------------------------------------------
   C. Demand heatmap: orders by day-of-week x hour band (capacity planning).
      Peak concentration justifies dynamic rider shifts + prep before 6 pm.
   --------------------------------------------------------------------------- */
SELECT  dd.day_of_week,
        dd.day_name,
        DATEPART(HOUR, o.order_ts)                     AS hour_of_day,
        COUNT(*)                                       AS orders,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()  AS DECIMAL(5,2)) AS pct_of_orders
FROM dbo.fact_orders o
JOIN dbo.dim_date dd ON dd.date_key = CAST(o.order_ts AS DATE)
GROUP BY dd.day_of_week, dd.day_name, DATEPART(HOUR, o.order_ts)
ORDER BY dd.day_of_week, hour_of_day;

/* ---------------------------------------------------------------------------
   D. The flywheel, quantified: store-month on-time rate vs the share of that
      month's customers who order again NEXT month from any store.
      Read it as: when a store breaks its promise, next month's demand pays.
   --------------------------------------------------------------------------- */
WITH store_month_customers AS (
    SELECT DISTINCT d.store_id, d.order_month, d.customer_id
    FROM dbo.vw_orders_delivered d
),
customer_months AS (
    SELECT DISTINCT d.customer_id, d.order_month
    FROM dbo.vw_orders_delivered d
),
next_month_repeat AS (
    SELECT  smc.store_id,
            smc.order_month,
            COUNT(*)                                                AS customers,
            SUM(CASE WHEN nm.customer_id IS NOT NULL THEN 1 ELSE 0 END) AS repeated_next_month
    FROM store_month_customers smc
    LEFT JOIN customer_months nm
           ON nm.customer_id = smc.customer_id
          AND nm.order_month = DATEADD(MONTH, 1, smc.order_month)
    WHERE smc.order_month < '2026-08-01'          -- Aug has no "next month"
    GROUP BY smc.store_id, smc.order_month
)
SELECT  nmr.store_id,
        ops.zone_name,
        nmr.order_month,
        ops.on_time_pct,
        CAST(100.0 * nmr.repeated_next_month / nmr.customers AS DECIMAL(5,1)) AS next_month_repeat_pct
FROM next_month_repeat nmr
JOIN dbo.vw_store_month_ops ops
  ON ops.store_id = nmr.store_id AND ops.order_month = nmr.order_month
ORDER BY nmr.store_id, nmr.order_month;
