/* ============================================================================
   15 | RFM SEGMENTATION — one map of the whole customer base
   ----------------------------------------------------------------------------
   As-of: 2026-08-31. Delivered orders only.
     R = days since last order        (lower is better)
     F = lifetime delivered orders    (12-month window = lifetime here)
     M = lifetime net spend (Rs)
   Scoring: NTILE(5) per dimension -> 5 = best. R is ranked ascending days so
   the freshest customers score 5.

   Segment map (industry-standard, adapted): rules on (R score, F score) with
   M as a tiebreaker for the premium segments.

   Output
     A. vw_customer_rfm — persisted view (used by Power BI + module 19)
     B. Segment summary: size, GMV share, behaviour, avg rating
     C. Actionability: what to DO with each segment (comments)
   ============================================================================ */

USE quickkart_analytics;
GO

CREATE OR ALTER VIEW dbo.vw_customer_rfm
AS
WITH base AS (
    SELECT  d.customer_id,
            DATEDIFF(DAY, MAX(d.order_ts), '2026-08-31') AS recency_days,
            COUNT(*)                                     AS frequency,
            SUM(d.net_amount)                            AS monetary_rs,
            AVG(1.0 * d.rating)                          AS avg_rating
    FROM dbo.vw_orders_delivered d
    GROUP BY d.customer_id
),
scored AS (
    SELECT  b.*,
            NTILE(5) OVER (ORDER BY b.recency_days DESC) AS r_score,  -- most recent -> 5
            NTILE(5) OVER (ORDER BY b.frequency  ASC)    AS f_score,  -- most frequent -> 5
            NTILE(5) OVER (ORDER BY b.monetary_rs ASC)   AS m_score   -- biggest spend -> 5
    FROM base b
)
SELECT  s.customer_id,
        s.recency_days, s.frequency, s.monetary_rs, s.avg_rating,
        s.r_score, s.f_score, s.m_score,
        CONCAT(s.r_score, s.f_score, s.m_score) AS rfm_cell,
        CASE
            WHEN s.r_score >= 4 AND s.f_score >= 4                    THEN 'Champions'
            WHEN s.r_score >= 3 AND s.f_score >= 4                    THEN 'Loyal'
            WHEN s.r_score >= 4 AND s.f_score = 3                     THEN 'Potential Loyalist'
            WHEN s.r_score >= 4 AND s.f_score <= 2                    THEN 'New / Light'
            WHEN s.r_score = 3  AND s.f_score <= 3                    THEN 'Needs Attention'
            WHEN s.r_score = 2  AND s.f_score >= 3                    THEN 'At Risk'
            WHEN s.r_score <= 1 AND s.f_score >= 4                    THEN 'Cannot Lose Them'
            WHEN s.r_score = 2  AND s.f_score <= 2                    THEN 'Hibernating'
            ELSE                                                           'Lost'
        END AS rfm_segment
FROM scored s;
GO

/* ---------------------------------------------------------------------------
   B. Segment summary — size, value concentration, behaviour.
      Watch the GMV concentration: a healthy marketplace still expects the
      top two segments to carry an outsized share of revenue.
   --------------------------------------------------------------------------- */
SELECT  r.rfm_segment,
        COUNT(*)                                                   AS customers,
        CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_of_base,
        CAST(AVG(1.0 * r.recency_days) AS DECIMAL(6,0))            AS avg_recency_days,
        CAST(AVG(1.0 * r.frequency)    AS DECIMAL(6,1))            AS avg_orders,
        CAST(AVG(1.0 * r.monetary_rs)  AS DECIMAL(9,0))            AS avg_net_spend_rs,
        SUM(r.monetary_rs)                                         AS segment_net_spend_rs,
        CAST(100.0 * SUM(r.monetary_rs) / SUM(SUM(r.monetary_rs)) OVER () AS DECIMAL(5,1)) AS spend_share_pct,
        CAST(AVG(r.avg_rating) AS DECIMAL(4,2))                    AS avg_rating
FROM dbo.vw_customer_rfm r
GROUP BY r.rfm_segment
ORDER BY spend_share_pct DESC;

/* ---------------------------------------------------------------------------
   C. Recommended playbook per segment (analyst's action table)
      Champions          protect: early access, no discounts needed
      Loyal              grow basket: cross-category nudges (see module 16/19)
      Potential Loyalist habit-building: 3-orders-in-30-days challenge
      New / Light        onboarding journey; perfect first deliveries (module 14!)
      Needs Attention    targeted reminder + curated reorder list
      At Risk            win-back offer with deadline; ask-why survey
      Cannot Lose Them   high-touch: service recovery call, personal coupon
      Hibernating/Lost   quarterly re-engagement only (don't burn spend)
   The mapping from data -> action is the deliverable; keep it attached to
   every RFM output you present.
   --------------------------------------------------------------------------- */
SELECT  r.rfm_segment,
        COUNT(*) AS customers,
        CAST(100.0 * AVG(CASE WHEN cf.bad_first_experience = 1 THEN 1.0 ELSE 0 END)
             AS DECIMAL(5,1)) AS pct_bad_first_experience     -- links segments to module 14's driver
FROM dbo.vw_customer_rfm r
JOIN dbo.vw_customer_first cf ON cf.customer_id = r.customer_id
GROUP BY r.rfm_segment
ORDER BY pct_bad_first_experience DESC;
