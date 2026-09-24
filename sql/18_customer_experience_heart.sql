/* ============================================================================
   18 | CUSTOMER EXPERIENCE — the HEART framework, monthly
   ----------------------------------------------------------------------------
   Google's HEART framework mapped to the signals this dataset actually has:

     Happiness    avg order rating; % of rated orders >= 4
     Engagement   orders per active customer; sessions per active user
     Adoption     activation rate of that month's NEW signups (first order <=7d)
     Retention    M1 retention of the PREVIOUS month's cohort
     Task success session -> order conversion; perfect-order rate

   One row per month = an executive CX scorecard. Then two deep dives that
   connect experience to behaviour (ratings are not vanity metrics here).
   ============================================================================ */

USE quickkart_analytics;
GO

CREATE OR ALTER VIEW dbo.vw_heart_monthly
AS
WITH months AS (
    SELECT DISTINCT month_start FROM dbo.dim_date
    WHERE month_start BETWEEN '2025-09-01' AND '2026-08-01'
),
happiness AS (
    SELECT order_month,
           CAST(AVG(1.0 * rating) AS DECIMAL(4,2))  AS avg_rating,
           CAST(100.0 * AVG(CASE WHEN rating >= 4 THEN 1.0
                                 WHEN rating IS NOT NULL THEN 0 END) AS DECIMAL(5,1)) AS pct_rated_4plus
    FROM dbo.vw_orders_delivered
    GROUP BY order_month
),
engagement AS (
    SELECT order_month,
           CAST(1.0 * COUNT(*) / COUNT(DISTINCT customer_id) AS DECIMAL(5,2)) AS orders_per_active
    FROM dbo.vw_orders_delivered
    GROUP BY order_month
),
sessions_pm AS (
    SELECT session_month AS order_month,
           CAST(1.0 * COUNT(*) / COUNT(DISTINCT customer_id) AS DECIMAL(5,2)) AS sessions_per_user,
           CAST(100.0 * SUM(converted) / COUNT(*) AS DECIMAL(5,1))            AS session_conversion_pct
    FROM dbo.vw_session_funnel
    GROUP BY session_month
),
adoption AS (
    SELECT cohort_month AS order_month,
           CAST(100.0 * SUM(activated_7d) / COUNT(*) AS DECIMAL(5,1)) AS activation_pct
    FROM dbo.vw_customer_first
    GROUP BY cohort_month
),
retention AS (       -- M1 of the cohort that signed up the PREVIOUS month
    SELECT DATEADD(MONTH, 1, cf.cohort_month) AS order_month,
           CAST(100.0 * COUNT(DISTINCT CASE WHEN ca.month_offset = 1
                                            THEN ca.customer_id END)
                / COUNT(DISTINCT cf.customer_id) AS DECIMAL(5,1)) AS m1_retention_pct
    FROM dbo.vw_customer_first cf
    LEFT JOIN dbo.vw_cohort_activity ca ON ca.customer_id = cf.customer_id
    GROUP BY DATEADD(MONTH, 1, cf.cohort_month)
),
task AS (
    SELECT order_month,
           CAST(100.0 * AVG(1.0 * is_perfect_order) AS DECIMAL(5,1)) AS perfect_order_pct
    FROM dbo.vw_orders_delivered
    GROUP BY order_month
)
SELECT  m.month_start                AS [month],
        h.avg_rating,                h.pct_rated_4plus,          -- Happiness
        e.orders_per_active,         s.sessions_per_user,        -- Engagement
        a.activation_pct,                                        -- Adoption
        r.m1_retention_pct,                                      -- Retention
        s.session_conversion_pct,    t.perfect_order_pct         -- Task success
FROM months m
LEFT JOIN happiness  h ON h.order_month = m.month_start
LEFT JOIN engagement e ON e.order_month = m.month_start
LEFT JOIN sessions_pm s ON s.order_month = m.month_start
LEFT JOIN adoption   a ON a.order_month = m.month_start
LEFT JOIN retention  r ON r.order_month = m.month_start
LEFT JOIN task       t ON t.order_month = m.month_start;
GO

SELECT * FROM dbo.vw_heart_monthly ORDER BY [month];

/* ---------------------------------------------------------------------------
   Deep dive 1: does a bad rating predict leaving? Behaviour in the 30 days
   AFTER a rated order, by the rating given.
   --------------------------------------------------------------------------- */
SELECT  d.rating,
        COUNT(*)                                       AS rated_orders,
        CAST(100.0 * AVG(CASE WHEN nxt.order_id IS NOT NULL THEN 1.0 ELSE 0 END)
             AS DECIMAL(5,1))                          AS pct_reordered_within_30d
FROM dbo.vw_orders_delivered d
OUTER APPLY (
        SELECT TOP (1) n.order_id
        FROM dbo.vw_orders_delivered n
        WHERE n.customer_id = d.customer_id
          AND n.order_ts > d.order_ts
          AND n.order_ts <= DATEADD(DAY, 30, d.order_ts)
     ) nxt
WHERE d.rating IS NOT NULL
  AND d.order_ts <= '2026-07-31'          -- every order gets a full 30-day window
GROUP BY d.rating
ORDER BY d.rating DESC;

/* ---------------------------------------------------------------------------
   Deep dive 2: what drags ratings down? Rating distribution by experience type.
   --------------------------------------------------------------------------- */
SELECT  CASE WHEN items_missing = 1 AND is_late_5plus = 1 THEN '4_late_and_incomplete'
             WHEN items_missing = 1                       THEN '3_incomplete'
             WHEN is_late_5plus = 1                       THEN '2_late_5plus'
             WHEN is_on_time = 0                          THEN '1_slightly_late'
             ELSE '0_on_time_complete' END                AS experience,
        COUNT(*)                                          AS rated_orders,
        CAST(AVG(1.0 * rating) AS DECIMAL(4,2))           AS avg_rating,
        CAST(100.0 * AVG(CASE WHEN rating <= 2 THEN 1.0 ELSE 0 END) AS DECIMAL(5,1)) AS pct_1_2_star
FROM dbo.vw_orders_delivered
WHERE rating IS NOT NULL
GROUP BY CASE WHEN items_missing = 1 AND is_late_5plus = 1 THEN '4_late_and_incomplete'
              WHEN items_missing = 1                       THEN '3_incomplete'
              WHEN is_late_5plus = 1                       THEN '2_late_5plus'
              WHEN is_on_time = 0                          THEN '1_slightly_late'
              ELSE '0_on_time_complete' END
ORDER BY experience;
