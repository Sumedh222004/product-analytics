/* ============================================================================
   12 | CONVERSION FUNNEL — session event log -> stage conversion
   ----------------------------------------------------------------------------
   Funnel stages (one session = one visit):
     app_open -> product_view -> add_to_cart -> checkout_start -> payment_success

   Technique: collapse the event log to one row per session with conditional
   aggregation (MAX CASE), then aggregate flags. This is the standard pattern
   for funnel analysis on raw event streams.

   Business questions
     A. Overall funnel + step-by-step conversion (where do we leak?)
     B. Trend: session -> order conversion by month
     C. Platform and channel cuts
     D. Search vs browse: which path converts better? (task-success metric)
     E. Cart -> checkout drop in stressed zones after May (availability story)
   ============================================================================ */

USE quickkart_analytics;
GO

/* one row per session with reached-stage flags — reused by every query below */
CREATE OR ALTER VIEW dbo.vw_session_funnel
AS
SELECT  e.session_id,
        e.customer_id,
        MIN(e.event_ts)                                                  AS session_start,
        DATEFROMPARTS(YEAR(MIN(e.event_ts)), MONTH(MIN(e.event_ts)), 1)  AS session_month,
        MAX(e.platform)                                                  AS platform,
        MAX(CASE WHEN e.event_name = 'search'          THEN 1 ELSE 0 END) AS used_search,
        MAX(CASE WHEN e.event_name = 'product_view'    THEN 1 ELSE 0 END) AS reached_pv,
        MAX(CASE WHEN e.event_name = 'add_to_cart'     THEN 1 ELSE 0 END) AS reached_cart,
        MAX(CASE WHEN e.event_name = 'checkout_start'  THEN 1 ELSE 0 END) AS reached_checkout,
        MAX(CASE WHEN e.event_name = 'payment_success' THEN 1 ELSE 0 END) AS converted,
        MAX(CASE WHEN e.event_name = 'payment_success' THEN e.event_ts END) AS payment_ts
FROM dbo.fact_app_events e
GROUP BY e.session_id, e.customer_id;
GO

/* ---------------------------------------------------------------------------
   A. Overall funnel: absolute counts, % of sessions, and step conversion
   --------------------------------------------------------------------------- */
WITH f AS (
    SELECT  COUNT(*)              AS sessions,
            SUM(reached_pv)       AS pv,
            SUM(reached_cart)     AS cart,
            SUM(reached_checkout) AS checkout,
            SUM(converted)        AS paid
    FROM dbo.vw_session_funnel
)
SELECT  stage, reached,
        CAST(100.0 * reached / sessions AS DECIMAL(5,1))            AS pct_of_sessions,
        CAST(100.0 * reached / NULLIF(prev_stage, 0) AS DECIMAL(5,1)) AS step_conversion_pct
FROM f
CROSS APPLY (VALUES
        (1, 'app_open',        sessions, sessions),
        (2, 'product_view',    pv,       sessions),
        (3, 'add_to_cart',     cart,     pv),
        (4, 'checkout_start',  checkout, cart),
        (5, 'payment_success', paid,     checkout)
     ) v (stage_order, stage, reached, prev_stage)
ORDER BY stage_order;

/* ---------------------------------------------------------------------------
   B. Session -> order conversion trend by month
   --------------------------------------------------------------------------- */
SELECT  session_month,
        COUNT(*)                                              AS sessions,
        SUM(converted)                                        AS orders,
        CAST(100.0 * SUM(converted) / COUNT(*) AS DECIMAL(5,1)) AS conversion_pct
FROM dbo.vw_session_funnel
GROUP BY session_month
ORDER BY session_month;

/* ---------------------------------------------------------------------------
   C. Funnel by platform (android vs ios)
   --------------------------------------------------------------------------- */
SELECT  platform,
        COUNT(*)                                                     AS sessions,
        CAST(100.0 * SUM(reached_pv)       / COUNT(*) AS DECIMAL(5,1)) AS pv_pct,
        CAST(100.0 * SUM(reached_cart)     / COUNT(*) AS DECIMAL(5,1)) AS cart_pct,
        CAST(100.0 * SUM(reached_checkout) / COUNT(*) AS DECIMAL(5,1)) AS checkout_pct,
        CAST(100.0 * SUM(converted)        / COUNT(*) AS DECIMAL(5,1)) AS conversion_pct
FROM dbo.vw_session_funnel
GROUP BY platform;

/* ---------------------------------------------------------------------------
   D. Search vs browse sessions: conversion and time-to-order.
      (Task success: can users find what they came for?)
   --------------------------------------------------------------------------- */
SELECT  CASE WHEN used_search = 1 THEN 'searched' ELSE 'browsed_only' END AS path,
        COUNT(*)                                                AS sessions,
        CAST(100.0 * SUM(converted) / COUNT(*) AS DECIMAL(5,1)) AS conversion_pct,
        CAST(AVG(CASE WHEN converted = 1
                 THEN 1.0 * DATEDIFF(SECOND, session_start, payment_ts) / 60 END)
             AS DECIMAL(5,1))                                   AS avg_min_to_order
FROM dbo.vw_session_funnel
GROUP BY CASE WHEN used_search = 1 THEN 'searched' ELSE 'browsed_only' END;

/* ---------------------------------------------------------------------------
   E. Cart -> checkout continuation, stressed zones vs rest, pre vs post May.
      A widening gap after May in Whitefield/Marathahalli points to stock-outs
      and slot unavailability, consistent with the ops degradation in module 17.
   --------------------------------------------------------------------------- */
SELECT  CASE WHEN c.home_store_id IN (4, 6) THEN 'stressed_zone' ELSE 'other_zones' END AS zone_group,
        CASE WHEN f.session_month >= '2026-05-01' THEN 'may_onward' ELSE 'before_may' END AS period,
        SUM(f.reached_cart)                       AS cart_sessions,
        SUM(f.reached_checkout)                   AS checkout_sessions,
        CAST(100.0 * SUM(f.reached_checkout) / NULLIF(SUM(f.reached_cart), 0)
             AS DECIMAL(5,1))                     AS cart_to_checkout_pct
FROM dbo.vw_session_funnel f
JOIN dbo.dim_customer c ON c.customer_id = f.customer_id
GROUP BY CASE WHEN c.home_store_id IN (4, 6) THEN 'stressed_zone' ELSE 'other_zones' END,
         CASE WHEN f.session_month >= '2026-05-01' THEN 'may_onward' ELSE 'before_may' END
ORDER BY zone_group, period;
