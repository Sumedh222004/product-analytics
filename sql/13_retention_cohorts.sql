/* ============================================================================
   13 | RETENTION COHORTS — does the product keep the customers it wins?
   ----------------------------------------------------------------------------
   Definitions
     Cohort        = calendar month of SIGNUP.
     Active in Mk  = placed >= 1 delivered order k calendar months after the
                     cohort month (M0 = the signup month itself).
     Retention %   = active customers / cohort size. Denominator is ALL
                     signups (not just activated) — so M0 also shows
                     activation quality.
     Right-censoring: a cohort that hasn't lived k months yet shows NULL,
     never a misleading 0.

   Business questions
     A. Classic cohort triangle (counts, then percentages)
     B. M1/M3/M6 summary per cohort — and the May-2026 promo cohort flag
     C. M1 retention by acquisition channel (quality, not volume)
     D. Inside May 2026: who exactly churned? (discount-hunter diagnosis)
   ============================================================================ */

USE quickkart_analytics;
GO

/* customer x month-offset activity, reused by all queries below */
CREATE OR ALTER VIEW dbo.vw_cohort_activity
AS
SELECT DISTINCT
        cf.customer_id,
        cf.cohort_month,
        cf.acquisition_channel,
        DATEDIFF(MONTH, cf.cohort_month, d.order_month) AS month_offset
FROM dbo.vw_customer_first cf
JOIN dbo.vw_orders_delivered d ON d.customer_id = cf.customer_id;
GO

/* ---------------------------------------------------------------------------
   A. Cohort retention triangle (%). NULL = cohort too young for that offset.
   --------------------------------------------------------------------------- */
WITH size_ AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM dbo.vw_customer_first
    GROUP BY cohort_month
),
act AS (
    SELECT cohort_month, month_offset, COUNT(*) AS actives
    FROM dbo.vw_cohort_activity
    GROUP BY cohort_month, month_offset
),
maxoff AS (
    SELECT cohort_month,
           DATEDIFF(MONTH, cohort_month, '2026-08-01') AS max_offset
    FROM size_
)
SELECT  s.cohort_month,
        s.cohort_size,
        CAST(100.0 * MAX(CASE WHEN a.month_offset = 0 THEN a.actives END) / s.cohort_size AS DECIMAL(5,1)) AS m0,
        CASE WHEN mo.max_offset >= 1  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 1  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m1,
        CASE WHEN mo.max_offset >= 2  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 2  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m2,
        CASE WHEN mo.max_offset >= 3  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 3  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m3,
        CASE WHEN mo.max_offset >= 4  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 4  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m4,
        CASE WHEN mo.max_offset >= 5  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 5  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m5,
        CASE WHEN mo.max_offset >= 6  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 6  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m6,
        CASE WHEN mo.max_offset >= 7  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 7  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m7,
        CASE WHEN mo.max_offset >= 8  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 8  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m8,
        CASE WHEN mo.max_offset >= 9  THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 9  THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m9,
        CASE WHEN mo.max_offset >= 10 THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 10 THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m10,
        CASE WHEN mo.max_offset >= 11 THEN CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 11 THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m11
FROM size_ s
JOIN maxoff mo ON mo.cohort_month = s.cohort_month
LEFT JOIN act a ON a.cohort_month = s.cohort_month
GROUP BY s.cohort_month, s.cohort_size, mo.max_offset
ORDER BY s.cohort_month;

/* ---------------------------------------------------------------------------
   B. M1 / M3 / M6 per cohort, with the promo cohort flagged
   --------------------------------------------------------------------------- */
WITH size_ AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM dbo.vw_customer_first GROUP BY cohort_month
),
act AS (
    SELECT cohort_month, month_offset, COUNT(*) AS actives
    FROM dbo.vw_cohort_activity GROUP BY cohort_month, month_offset
)
SELECT  s.cohort_month,
        s.cohort_size,
        CASE WHEN s.cohort_month = '2026-05-01' THEN 'PROMO COHORT' ELSE '' END AS note,
        CASE WHEN DATEDIFF(MONTH, s.cohort_month, '2026-08-01') >= 1 THEN
        CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 1 THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m1_pct,
        CASE WHEN DATEDIFF(MONTH, s.cohort_month, '2026-08-01') >= 3 THEN
        CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 3 THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m3_pct,
        CASE WHEN DATEDIFF(MONTH, s.cohort_month, '2026-08-01') >= 6 THEN
        CAST(100.0 * COALESCE(MAX(CASE WHEN a.month_offset = 6 THEN a.actives END), 0) / s.cohort_size AS DECIMAL(5,1)) END AS m6_pct
FROM size_ s
LEFT JOIN act a ON a.cohort_month = s.cohort_month
GROUP BY s.cohort_month, s.cohort_size
ORDER BY s.cohort_month;

/* ---------------------------------------------------------------------------
   C. M1 retention by channel (cohorts through Jul-2026, which have a full M1)
   --------------------------------------------------------------------------- */
WITH base AS (
    SELECT  cf.acquisition_channel,
            cf.customer_id,
            MAX(CASE WHEN ca.month_offset = 1 THEN 1 ELSE 0 END) AS active_m1
    FROM dbo.vw_customer_first cf
    LEFT JOIN dbo.vw_cohort_activity ca ON ca.customer_id = cf.customer_id
    WHERE cf.cohort_month <= '2026-07-01'
    GROUP BY cf.acquisition_channel, cf.customer_id
)
SELECT  acquisition_channel,
        COUNT(*) AS customers,
        CAST(100.0 * SUM(active_m1) / COUNT(*) AS DECIMAL(5,1)) AS m1_retention_pct
FROM base
GROUP BY acquisition_channel
ORDER BY m1_retention_pct DESC;

/* ---------------------------------------------------------------------------
   D. Diagnosing May-2026: split the cohort into discount-led vs organic-intent
      customers. Proxy: >= 50% of their lifetime orders carried a discount.
      Expected: the promo pulled in deal-hunters whose retention collapses —
      the average hides two very different populations.
   --------------------------------------------------------------------------- */
WITH discount_profile AS (
    SELECT  d.customer_id,
            AVG(CASE WHEN d.discount_amount > 0 THEN 1.0 ELSE 0.0 END) AS discounted_share
    FROM dbo.vw_orders_delivered d
    GROUP BY d.customer_id
),
base AS (
    SELECT  cf.customer_id,
            CASE WHEN cf.cohort_month = '2026-05-01' THEN 'may_2026' ELSE 'other_cohorts' END AS cohort_group,
            CASE WHEN dp.discounted_share >= 0.5 THEN 'discount_led' ELSE 'full_price_led' END AS buyer_type,
            MAX(CASE WHEN ca.month_offset = 1 THEN 1 ELSE 0 END)      AS active_m1
    FROM dbo.vw_customer_first cf
    JOIN discount_profile dp ON dp.customer_id = cf.customer_id
    LEFT JOIN dbo.vw_cohort_activity ca ON ca.customer_id = cf.customer_id
    WHERE cf.cohort_month <= '2026-07-01'
    GROUP BY cf.customer_id,
             CASE WHEN cf.cohort_month = '2026-05-01' THEN 'may_2026' ELSE 'other_cohorts' END,
             CASE WHEN dp.discounted_share >= 0.5 THEN 'discount_led' ELSE 'full_price_led' END
)
SELECT  cohort_group, buyer_type,
        COUNT(*)                                              AS customers,
        CAST(100.0 * SUM(active_m1) / COUNT(*) AS DECIMAL(5,1)) AS m1_retention_pct
FROM base
GROUP BY cohort_group, buyer_type
ORDER BY cohort_group, buyer_type;
