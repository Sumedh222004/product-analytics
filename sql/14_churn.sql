/* ============================================================================
   14 | CHURN & LIFECYCLE — who is slipping away, and why?
   ----------------------------------------------------------------------------
   Snapshot date: 2026-08-31 (end of the data window).
   Lifecycle buckets by recency of last delivered order:
       active   <= 28 days      (quick-commerce is a weekly habit)
       at_risk  29 - 56 days
       churned  > 56 days
   Why 28? Median actives order ~3x/month; a 4-week silence is a broken habit.

   Business questions
     A. Lifecycle distribution + how much historical GMV sits in each bucket
     B. WHY churn happens: first-order experience, channel, home zone
     C. Store-stress churn: did May's ops failure cost us customers?
     D. Win-back: how often do 56+ day sleepers come back? (reactivation)
   ============================================================================ */

USE quickkart_analytics;
GO

DECLARE @asof DATE = '2026-08-31';

/* ---------------------------------------------------------------------------
   A. Lifecycle snapshot + GMV weight of each bucket
   --------------------------------------------------------------------------- */
WITH last_order AS (
    SELECT  customer_id,
            MAX(order_ts)     AS last_order_ts,
            COUNT(*)          AS lifetime_orders,
            SUM(item_total)   AS lifetime_gmv
    FROM dbo.vw_orders_delivered
    GROUP BY customer_id
),
lifecycle AS (
    SELECT  customer_id, lifetime_orders, lifetime_gmv,
            DATEDIFF(DAY, last_order_ts, @asof) AS days_since_last,
            CASE WHEN DATEDIFF(DAY, last_order_ts, @asof) <= 28 THEN '1_active'
                 WHEN DATEDIFF(DAY, last_order_ts, @asof) <= 56 THEN '2_at_risk'
                 ELSE '3_churned' END AS bucket
    FROM last_order
)
SELECT  bucket,
        COUNT(*)                                                  AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_of_ever_ordered,
        CAST(AVG(1.0 * lifetime_orders) AS DECIMAL(5,1))          AS avg_lifetime_orders,
        SUM(lifetime_gmv)                                         AS lifetime_gmv_rs,
        CAST(100.0 * SUM(lifetime_gmv) / SUM(SUM(lifetime_gmv)) OVER () AS DECIMAL(5,1)) AS gmv_share_pct
FROM lifecycle
GROUP BY bucket
ORDER BY bucket;

/* ---------------------------------------------------------------------------
   B0. The activation cliff in one number: share of customers whose SECOND
       delivered order lands within 28 days of the first, split by the quality
       of that first order. (No signup-age cutoff here — right-censoring near
       the window edge hits both groups equally; adding
       AND cf.first_order_ts <= DATEADD(DAY, -28, @asof) barely moves the gap.)
   --------------------------------------------------------------------------- */
WITH second_order AS (
    SELECT  cf.customer_id,
            cf.bad_first_experience,
            cf.first_order_ts,
            MIN(d.order_ts) AS second_order_ts
    FROM dbo.vw_customer_first cf
    LEFT JOIN dbo.vw_orders_delivered d
           ON d.customer_id = cf.customer_id
          AND d.order_ts > cf.first_order_ts
    WHERE cf.first_order_ts IS NOT NULL
    GROUP BY cf.customer_id, cf.bad_first_experience, cf.first_order_ts
)
SELECT  CASE bad_first_experience WHEN 1 THEN 'bad_first_order (late>5m or incomplete)'
                                  ELSE 'good_first_order' END AS first_experience,
        COUNT(*)                                              AS customers,
        CAST(100.0 * SUM(CASE WHEN DATEDIFF(DAY, first_order_ts, second_order_ts) <= 28
                              THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1))
                                                              AS repeat_within_28d_pct
FROM second_order
GROUP BY bad_first_experience;

/* ---------------------------------------------------------------------------
   B. Churn drivers. The headline: churn rate by FIRST-order experience.
      (Only customers with >= 90 days of possible history, so every customer
      had a fair chance to demonstrate retention.)
   --------------------------------------------------------------------------- */
WITH last_order AS (
    SELECT customer_id, MAX(order_ts) AS last_order_ts
    FROM dbo.vw_orders_delivered
    GROUP BY customer_id
),
base AS (
    SELECT  cf.customer_id,
            cf.acquisition_channel,
            cf.bad_first_experience,
            CASE WHEN DATEDIFF(DAY, lo.last_order_ts, @asof) > 56 THEN 1 ELSE 0 END AS churned
    FROM dbo.vw_customer_first cf
    JOIN last_order lo ON lo.customer_id = cf.customer_id
    WHERE cf.signup_ts <= DATEADD(DAY, -90, @asof)
)
SELECT  CASE bad_first_experience WHEN 1 THEN 'bad_first_order (late>5m or incomplete)'
                                  ELSE 'good_first_order' END AS first_experience,
        COUNT(*)                                              AS customers,
        CAST(100.0 * SUM(churned) / COUNT(*) AS DECIMAL(5,1)) AS churn_rate_pct
FROM base
GROUP BY bad_first_experience;

/* same cut by channel */
WITH last_order AS (
    SELECT customer_id, MAX(order_ts) AS last_order_ts
    FROM dbo.vw_orders_delivered GROUP BY customer_id
)
SELECT  cf.acquisition_channel,
        COUNT(*)                                              AS customers,
        CAST(100.0 * SUM(CASE WHEN DATEDIFF(DAY, lo.last_order_ts, @asof) > 56
                              THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS churn_rate_pct
FROM dbo.vw_customer_first cf
JOIN last_order lo ON lo.customer_id = cf.customer_id
WHERE cf.signup_ts <= DATEADD(DAY, -90, @asof)
GROUP BY cf.acquisition_channel
ORDER BY churn_rate_pct DESC;

/* ---------------------------------------------------------------------------
   C. The ops -> churn chain: churn among customers who experienced the
      stressed stores (home zone Whitefield/Marathahalli) AFTER May vs the
      same zones BEFORE (their earlier cohorts) and vs other zones.
   --------------------------------------------------------------------------- */
WITH last_order AS (
    SELECT customer_id, MAX(order_ts) AS last_order_ts
    FROM dbo.vw_orders_delivered GROUP BY customer_id
)
SELECT  CASE WHEN cf.home_store_id IN (4, 6) THEN 'stressed_zone' ELSE 'other_zones' END AS zone_group,
        CASE WHEN cf.cohort_month >= '2026-05-01' THEN 'joined_may_onward'
             ELSE 'joined_before_may' END                     AS cohort_period,
        COUNT(*)                                              AS customers,
        CAST(100.0 * SUM(CASE WHEN DATEDIFF(DAY, lo.last_order_ts, @asof) > 56
                              THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS churn_rate_pct
FROM dbo.vw_customer_first cf
JOIN last_order lo ON lo.customer_id = cf.customer_id
WHERE cf.signup_ts <= DATEADD(DAY, -90, @asof)
GROUP BY CASE WHEN cf.home_store_id IN (4, 6) THEN 'stressed_zone' ELSE 'other_zones' END,
         CASE WHEN cf.cohort_month >= '2026-05-01' THEN 'joined_may_onward'
              ELSE 'joined_before_may' END
ORDER BY zone_group, cohort_period;

/* ---------------------------------------------------------------------------
   D. Reactivation: sleepers (gap > 56 days between consecutive orders) who
      came back anyway. Sizes the win-back opportunity for lifecycle CRM.
   --------------------------------------------------------------------------- */
WITH gaps AS (
    SELECT  customer_id,
            DATEDIFF(DAY,
                     LAG(order_ts) OVER (PARTITION BY customer_id ORDER BY order_ts),
                     order_ts) AS gap_days
    FROM dbo.vw_orders_delivered
)
SELECT  COUNT(DISTINCT CASE WHEN gap_days > 56 THEN customer_id END) AS reactivated_customers,
        COUNT(DISTINCT customer_id)                                  AS customers_with_2plus_orders,
        CAST(100.0 * COUNT(DISTINCT CASE WHEN gap_days > 56 THEN customer_id END)
             / COUNT(DISTINCT customer_id) AS DECIMAL(5,1))          AS reactivation_share_pct
FROM gaps
WHERE gap_days IS NOT NULL;
