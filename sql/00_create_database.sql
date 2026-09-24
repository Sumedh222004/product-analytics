/* ============================================================================
   00 | CREATE DATABASE
   ----------------------------------------------------------------------------
   Creates the analytics database. Run once, connected to `master`.
   Tested on SQL Server 2019+ (Developer/Express editions are free).
   ============================================================================ */

IF DB_ID('quickkart_analytics') IS NULL
BEGIN
    CREATE DATABASE quickkart_analytics;
END;
GO

ALTER DATABASE quickkart_analytics SET RECOVERY SIMPLE;
GO

USE quickkart_analytics;
GO

PRINT 'Database quickkart_analytics ready.';
