/* ============================================================================
   03 | POST-LOAD: INDEXES, FOREIGN KEYS, DATA QUALITY CHECKS
   ----------------------------------------------------------------------------
   Indexes and FKs are created after the load (faster than loading into
   indexed tables). The quality section is a self-auditing checklist — every
   row of the final result should say PASS.
   ============================================================================ */

USE quickkart_analytics;
GO

/* ------------------------------ 3.1 indexes ------------------------------ */
CREATE NONCLUSTERED INDEX ix_orders_customer_ts
    ON dbo.fact_orders (customer_id, order_ts) INCLUDE (status, item_total);
CREATE NONCLUSTERED INDEX ix_orders_store_ts
    ON dbo.fact_orders (store_id, order_ts);
CREATE NONCLUSTERED INDEX ix_orders_ts
    ON dbo.fact_orders (order_ts) INCLUDE (status, item_total, net_amount);
CREATE NONCLUSTERED INDEX ix_items_product
    ON dbo.fact_order_items (product_id) INCLUDE (quantity, line_amount);
CREATE CLUSTERED INDEX cix_events_session_ts
    ON dbo.fact_app_events (session_id, event_ts);
CREATE NONCLUSTERED INDEX ix_events_customer
    ON dbo.fact_app_events (customer_id, event_ts);
CREATE NONCLUSTERED INDEX ix_customer_channel
    ON dbo.dim_customer (acquisition_channel) INCLUDE (signup_ts, home_store_id);
GO

/* ---------------------------- 3.2 foreign keys ---------------------------- */
ALTER TABLE dbo.dim_customer  WITH CHECK ADD CONSTRAINT fk_customer_store
    FOREIGN KEY (home_store_id) REFERENCES dbo.dim_store (store_id);
ALTER TABLE dbo.fact_orders   WITH CHECK ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES dbo.dim_customer (customer_id);
ALTER TABLE dbo.fact_orders   WITH CHECK ADD CONSTRAINT fk_orders_store
    FOREIGN KEY (store_id) REFERENCES dbo.dim_store (store_id);
ALTER TABLE dbo.fact_order_items WITH CHECK ADD CONSTRAINT fk_items_order
    FOREIGN KEY (order_id) REFERENCES dbo.fact_orders (order_id);
ALTER TABLE dbo.fact_order_items WITH CHECK ADD CONSTRAINT fk_items_product
    FOREIGN KEY (product_id) REFERENCES dbo.dim_product (product_id);
ALTER TABLE dbo.fact_app_events  WITH CHECK ADD CONSTRAINT fk_events_customer
    FOREIGN KEY (customer_id) REFERENCES dbo.dim_customer (customer_id);
GO

/* ------------------------- 3.3 data quality audit ------------------------- */
;WITH checks AS
(
    SELECT 1 AS ord, 'row counts within expected range' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM dbo.fact_orders) BETWEEN 120000 AND 260000
                 AND (SELECT COUNT(*) FROM dbo.dim_customer) BETWEEN 18000 AND 32000
                 AND (SELECT COUNT(*) FROM dbo.fact_app_events) > 1000000
                THEN 'PASS' ELSE 'FAIL' END AS result

    UNION ALL
    SELECT 2, 'no duplicate order ids',
           CASE WHEN NOT EXISTS (SELECT order_id FROM dbo.fact_orders
                                 GROUP BY order_id HAVING COUNT(*) > 1)
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 3, 'no orphan order_items (FK integrity)',
           CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.fact_order_items i
                                 LEFT JOIN dbo.fact_orders o ON o.order_id = i.order_id
                                 WHERE o.order_id IS NULL)
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 4, 'basket reconciliation: SUM(line_amount) = orders.item_total',
           CASE WHEN NOT EXISTS (
                    SELECT o.order_id
                    FROM dbo.fact_orders o
                    JOIN (SELECT order_id, SUM(line_amount) AS s
                          FROM dbo.fact_order_items GROUP BY order_id) i
                      ON i.order_id = o.order_id
                    WHERE i.s <> o.item_total)
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 5, 'net_amount arithmetic holds on every order',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM dbo.fact_orders
                    WHERE net_amount <> item_total - discount_amount
                                        + delivery_fee + handling_fee)
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 6, 'cancelled orders have NULL delivery time; delivered never do',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM dbo.fact_orders
                    WHERE (status = 'cancelled' AND actual_delivery_min IS NOT NULL)
                       OR (status = 'delivered' AND actual_delivery_min IS NULL))
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 7, 'all order timestamps inside 2025-09-01 .. 2026-08-31',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM dbo.fact_orders
                    WHERE order_ts <  '2025-09-01'
                       OR order_ts >= '2026-09-01')
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 8, 'no order placed before its customer signed up',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM dbo.fact_orders o
                    JOIN dbo.dim_customer c ON c.customer_id = o.customer_id
                    WHERE o.order_ts < c.signup_ts)
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 9, 'ratings only on delivered orders and within 1..5',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM dbo.fact_orders
                    WHERE (rating IS NOT NULL AND status = 'cancelled')
                       OR rating < 1 OR rating > 5)
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 10, 'every payment_success event maps to a real order',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM dbo.fact_app_events e
                    LEFT JOIN dbo.fact_orders o ON o.order_id = e.order_id
                    WHERE e.event_name = 'payment_success'
                      AND (e.order_id IS NULL OR o.order_id IS NULL))
                THEN 'PASS' ELSE 'FAIL' END

    UNION ALL
    SELECT 11, 'non-negative money everywhere',
           CASE WHEN NOT EXISTS (
                    SELECT 1 FROM dbo.fact_orders
                    WHERE item_total < 0 OR discount_amount < 0 OR net_amount < 0)
                THEN 'PASS' ELSE 'FAIL' END
)
SELECT check_name, result
FROM checks
ORDER BY ord;
GO

/* quick profile — handy sanity glance */
SELECT status,
       COUNT(*)                                   AS orders,
       CAST(AVG(1.0 * item_total) AS DECIMAL(8,0)) AS avg_basket_rs,
       SUM(item_total)                            AS gmv_rs
FROM dbo.fact_orders
GROUP BY status;
