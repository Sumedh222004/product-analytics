/* ============================================================================
   10 | ACQUISITION & CAC — where do good customers come from, at what price?
   ----------------------------------------------------------------------------
   Business questions
     A. How many customers does each channel bring, and what do they cost?
     B. CAC is misleading if half the signups never order — what is the cost
        per ACTIVATED customer?
     C. How fast does each channel pay back its CAC in contribution?
     D. One scorecard: volume, cost, quality — per channel.

   Uses: dim_customer, fact_marketing_spend, vw_customer_first, vw_order_margin
   ============================================================================ */

USE quickkart_analytics;
GO

/* ---------------------------------------------------------------------------
   A. Monthly signups by channel (acquisition trend; note the May-2026 spike)
   --------------------------------------------------------------------------- */
SELECT  DATEFROMPARTS(YEAR(signup_ts), MONTH(signup_ts), 1) AS signup_month,
        acquisition_channel,
        COUNT(*) AS new_customers
FROM dbo.dim_customer
GROUP BY DATEFROMPARTS(YEAR(signup_ts), MONTH(signup_ts), 1), acquisition_channel
ORDER BY signup_month, acquisition_channel;

/* ---------------------------------------------------------------------------
   B. CAC per signup vs CAC per ACTIVATED customer, by channel.
      Organic has no paid spend -> CAC shows as NULL (excluded from paid CAC).
   --------------------------------------------------------------------------- */
WITH spend AS (
    SELECT channel, SUM(spend_inr) AS spend_inr
    FROM dbo.fact_marketing_spend
    GROUP BY channel
),
cust AS (
    SELECT acquisition_channel,
           COUNT(*)                    AS signups,
           SUM(activated_7d)           AS activated_7d,
           SUM(1 - never_ordered)      AS ever_ordered
    FROM dbo.vw_customer_first
    GROUP BY acquisition_channel
)
SELECT  c.acquisition_channel,
        c.signups,
        s.spend_inr,
        CAST(1.0 * s.spend_inr / NULLIF(c.signups, 0)      AS DECIMAL(8,0)) AS cac_per_signup,
        CAST(100.0 * c.activated_7d / c.signups            AS DECIMAL(5,1)) AS activation_rate_pct,
        CAST(1.0 * s.spend_inr / NULLIF(c.activated_7d, 0) AS DECIMAL(8,0)) AS cac_per_activated,
        CAST(100.0 * c.ever_ordered / c.signups            AS DECIMAL(5,1)) AS ever_ordered_pct
FROM cust c
LEFT JOIN spend s ON s.channel = c.acquisition_channel
ORDER BY cac_per_activated DESC;

/* ---------------------------------------------------------------------------
   C. CAC payback: cumulative contribution per acquired customer, by months
      since signup, vs the channel's CAC. The first tenure month where
      cum_contribution_per_customer >= CAC is the payback month.
      (Sequential logic: contribution accrues per calendar-month offset.)
   --------------------------------------------------------------------------- */
WITH per_customer_month AS (
    SELECT  cf.acquisition_channel,
            DATEDIFF(MONTH, cf.cohort_month, om.order_month) AS tenure_month,
            SUM(om.contribution_rs)                          AS contribution_rs
    FROM dbo.vw_order_margin om
    JOIN dbo.vw_customer_first cf ON cf.customer_id = om.customer_id
    GROUP BY cf.acquisition_channel,
             DATEDIFF(MONTH, cf.cohort_month, om.order_month)
),
cohort_size AS (
    SELECT acquisition_channel, COUNT(*) AS n_customers
    FROM dbo.vw_customer_first
    GROUP BY acquisition_channel
),
spend AS (
    SELECT channel, SUM(spend_inr) AS spend_inr
    FROM dbo.fact_marketing_spend
    GROUP BY channel
)
SELECT  p.acquisition_channel,
        p.tenure_month,
        CAST(1.0 * p.contribution_rs / cs.n_customers AS DECIMAL(8,1))
                                                     AS contribution_per_cust,
        CAST(SUM(1.0 * p.contribution_rs / cs.n_customers)
                 OVER (PARTITION BY p.acquisition_channel
                       ORDER BY p.tenure_month
                       ROWS UNBOUNDED PRECEDING) AS DECIMAL(8,1))
                                                     AS cum_contribution_per_cust,
        CAST(1.0 * s.spend_inr / cs.n_customers AS DECIMAL(8,0)) AS cac_per_signup,
        CASE WHEN SUM(1.0 * p.contribution_rs / cs.n_customers)
                      OVER (PARTITION BY p.acquisition_channel
                            ORDER BY p.tenure_month
                            ROWS UNBOUNDED PRECEDING)
                  >= 1.0 * s.spend_inr / cs.n_customers
             THEN 'paid back' ELSE '' END            AS payback_status
FROM per_customer_month p
JOIN cohort_size cs ON cs.acquisition_channel = p.acquisition_channel
LEFT JOIN spend s   ON s.channel = p.acquisition_channel
WHERE p.tenure_month <= 6
ORDER BY p.acquisition_channel, p.tenure_month;

/* ---------------------------------------------------------------------------
   D. Channel scorecard — the slide you would actually show.
      Quality metrics: activation, M1 repeat, 90-day orders & contribution.
   --------------------------------------------------------------------------- */
WITH m1 AS (   -- ordered again in calendar month +1 after signup month
    SELECT  cf.customer_id, cf.acquisition_channel,
            MAX(CASE WHEN DATEDIFF(MONTH, cf.cohort_month, d.order_month) = 1
                     THEN 1 ELSE 0 END) AS active_m1
    FROM dbo.vw_customer_first cf
    LEFT JOIN dbo.vw_orders_delivered d ON d.customer_id = cf.customer_id
    WHERE cf.cohort_month <= '2026-07-01'          -- cohorts with a full M1
    GROUP BY cf.customer_id, cf.acquisition_channel
),
d90 AS (       -- behaviour in the first 90 days after signup
    SELECT  cf.customer_id,
            COUNT(om.order_id)          AS orders_90d,
            SUM(om.contribution_rs)     AS contribution_90d
    FROM dbo.vw_customer_first cf
    LEFT JOIN dbo.vw_order_margin om
           ON om.customer_id = cf.customer_id
          AND om.order_ts < DATEADD(DAY, 90, cf.signup_ts)
    GROUP BY cf.customer_id
),
spend AS (
    SELECT channel, SUM(spend_inr) AS spend_inr FROM dbo.fact_marketing_spend GROUP BY channel
)
SELECT  cf.acquisition_channel,
        COUNT(*)                                                  AS signups,
        CAST(100.0 * AVG(1.0 * cf.activated_7d)  AS DECIMAL(5,1)) AS activation_pct,
        CAST(100.0 * AVG(1.0 * m1.active_m1)     AS DECIMAL(5,1)) AS m1_retention_pct,
        CAST(AVG(1.0 * d90.orders_90d)           AS DECIMAL(5,2)) AS avg_orders_90d,
        CAST(AVG(1.0 * d90.contribution_90d)     AS DECIMAL(8,0)) AS avg_contribution_90d,
        CAST(1.0 * MAX(s.spend_inr) / COUNT(*)   AS DECIMAL(8,0)) AS cac_per_signup
FROM dbo.vw_customer_first cf
JOIN m1  ON m1.customer_id = cf.customer_id
JOIN d90 ON d90.customer_id = cf.customer_id
LEFT JOIN spend s ON s.channel = cf.acquisition_channel
GROUP BY cf.acquisition_channel
ORDER BY signups DESC;
