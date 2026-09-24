/* ============================================================================
   11 | ACTIVATION — do new signups reach their first order, and how fast?
   ----------------------------------------------------------------------------
   Definition: activated = first DELIVERED order within 7 days of signup.
   Why it matters: in quick commerce the habit forms (or dies) in week one.

   Business questions
     A. Activation rate by channel and by month (is onboarding improving?)
     B. How long does the first order take? (time-to-value distribution)
     C. The "aha moment": does reaching add_to_cart in the FIRST session
        predict activation?
   ============================================================================ */

USE quickkart_analytics;
GO

/* ---------------------------------------------------------------------------
   A. Activation rate by channel x month
   --------------------------------------------------------------------------- */
SELECT  cohort_month,
        acquisition_channel,
        COUNT(*)                                                 AS signups,
        SUM(activated_7d)                                        AS activated,
        CAST(100.0 * SUM(activated_7d) / COUNT(*) AS DECIMAL(5,1)) AS activation_pct
FROM dbo.vw_customer_first
GROUP BY cohort_month, acquisition_channel
ORDER BY cohort_month, acquisition_channel;

/* overall + platform cut */
SELECT  platform,
        COUNT(*) AS signups,
        CAST(100.0 * SUM(activated_7d) / COUNT(*) AS DECIMAL(5,1)) AS activation_pct
FROM dbo.vw_customer_first
GROUP BY platform;

/* ---------------------------------------------------------------------------
   B. Time-to-first-order distribution (time to value)
   --------------------------------------------------------------------------- */
SELECT  CASE
            WHEN never_ordered = 1            THEN '7_never'
            WHEN days_to_first_order < 1      THEN '1_same_day'
            WHEN days_to_first_order < 2      THEN '2_next_day'
            WHEN days_to_first_order <= 3     THEN '3_within_3d'
            WHEN days_to_first_order <= 7     THEN '4_within_7d'
            WHEN days_to_first_order <= 30    THEN '5_8_to_30d'
            ELSE                                   '6_over_30d'
        END                                          AS time_to_first_order,
        COUNT(*)                                     AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct
FROM dbo.vw_customer_first
GROUP BY CASE
            WHEN never_ordered = 1            THEN '7_never'
            WHEN days_to_first_order < 1      THEN '1_same_day'
            WHEN days_to_first_order < 2      THEN '2_next_day'
            WHEN days_to_first_order <= 3     THEN '3_within_3d'
            WHEN days_to_first_order <= 7     THEN '4_within_7d'
            WHEN days_to_first_order <= 30    THEN '5_8_to_30d'
            ELSE                                   '6_over_30d'
        END
ORDER BY time_to_first_order;

/* ---------------------------------------------------------------------------
   C. "Aha moment" analysis: depth of the customer's FIRST session vs
      activation. If add_to_cart in session 1 strongly predicts activation,
      onboarding should optimise for getting one item into the cart.
   --------------------------------------------------------------------------- */
WITH sessions AS (          -- one row per session with start time + depth flags
    SELECT  customer_id,
            session_id,
            MIN(event_ts) AS session_start,
            MAX(CASE WHEN event_name = 'product_view'    THEN 1 ELSE 0 END) AS viewed,
            MAX(CASE WHEN event_name = 'add_to_cart'     THEN 1 ELSE 0 END) AS carted,
            MAX(CASE WHEN event_name = 'payment_success' THEN 1 ELSE 0 END) AS ordered
    FROM dbo.fact_app_events
    GROUP BY customer_id, session_id
),
depth AS (                  -- keep each customer's chronologically FIRST session
    SELECT  customer_id,
            viewed  AS s1_viewed,
            carted  AS s1_carted,
            ordered AS s1_ordered
    FROM (
        SELECT s.*,
               ROW_NUMBER() OVER (PARTITION BY customer_id
                                  ORDER BY session_start, session_id) AS rn
        FROM sessions s
    ) x
    WHERE rn = 1
)
SELECT  CASE WHEN d.s1_ordered = 1 THEN '4_ordered_in_session_1'
             WHEN d.s1_carted  = 1 THEN '3_reached_cart'
             WHEN d.s1_viewed  = 1 THEN '2_viewed_product'
             ELSE                       '1_bounced_at_open' END AS first_session_depth,
        COUNT(*)                                                AS customers,
        CAST(100.0 * SUM(cf.activated_7d) / COUNT(*) AS DECIMAL(5,1)) AS activation_pct
FROM depth d
JOIN dbo.vw_customer_first cf ON cf.customer_id = d.customer_id
GROUP BY CASE WHEN d.s1_ordered = 1 THEN '4_ordered_in_session_1'
              WHEN d.s1_carted  = 1 THEN '3_reached_cart'
              WHEN d.s1_viewed  = 1 THEN '2_viewed_product'
              ELSE                       '1_bounced_at_open' END
ORDER BY first_session_depth;
