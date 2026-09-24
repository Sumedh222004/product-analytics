/* ============================================================================
   02 | BULK LOAD THE CSVs
   ----------------------------------------------------------------------------
   HOW TO RUN (pick one):

   A) SSMS:  Query menu -> "SQLCMD Mode" ON, edit :setvar below, execute.
   B) sqlcmd:
        sqlcmd -S localhost -d quickkart_analytics -E ^
               -v DataPath="C:\path\to\repo\data\output" -i 02_load_data.sql
   C) No BULK INSERT permission / server can't see your files?
        Use the Python loader instead:  python scripts/load_to_sqlserver.py

   Notes:
     * FORMAT='CSV' (SQL Server 2017+) parses RFC-4180 CSVs and turns empty
       fields into NULLs for nullable columns (rating, actual_delivery_min,
       order_id on events).
     * The path must be visible to the SQL SERVER SERVICE, not just to you —
       keep the repo on a local drive.
   ============================================================================ */

:setvar DataPath "C:\projects\blinkit-product-analytics\data\output"

USE quickkart_analytics;
GO

/* re-runnable: clear in FK-safe order */
TRUNCATE TABLE dbo.fact_app_events;
TRUNCATE TABLE dbo.fact_order_items;
DELETE FROM dbo.fact_orders;
DELETE FROM dbo.fact_marketing_spend;
DELETE FROM dbo.dim_customer;
DELETE FROM dbo.dim_product;
DELETE FROM dbo.dim_store;
GO

BULK INSERT dbo.dim_store
FROM '$(DataPath)\stores.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.dim_product
FROM '$(DataPath)\products.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.dim_customer
FROM '$(DataPath)\customers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.fact_orders
FROM '$(DataPath)\orders.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK, BATCHSIZE = 100000);

BULK INSERT dbo.fact_order_items
FROM '$(DataPath)\order_items.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK, BATCHSIZE = 200000);

BULK INSERT dbo.fact_app_events
FROM '$(DataPath)\app_events.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK, BATCHSIZE = 500000);

BULK INSERT dbo.fact_marketing_spend
FROM '$(DataPath)\marketing_spend.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);
GO

SELECT 'dim_store'            AS table_name, COUNT(*) AS rows_loaded FROM dbo.dim_store
UNION ALL SELECT 'dim_product',          COUNT(*) FROM dbo.dim_product
UNION ALL SELECT 'dim_customer',         COUNT(*) FROM dbo.dim_customer
UNION ALL SELECT 'fact_orders',          COUNT(*) FROM dbo.fact_orders
UNION ALL SELECT 'fact_order_items',     COUNT(*) FROM dbo.fact_order_items
UNION ALL SELECT 'fact_app_events',      COUNT(*) FROM dbo.fact_app_events
UNION ALL SELECT 'fact_marketing_spend', COUNT(*) FROM dbo.fact_marketing_spend;
