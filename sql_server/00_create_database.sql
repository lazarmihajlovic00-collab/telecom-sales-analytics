-- 00 CREATE THE DATABASE AND SCHEMAS
-- Run once in SSMS on a local SQL Server 2019 or 2022 instance (Developer or Express edition).
--   stg  = raw text copies of the clean CSVs
--   core = typed tables with keys and constraints
--   bi   = star-schema views that Power BI imports
--   qa   = load log, conversion checks and validation results
IF DB_ID(N'KestrelSales') IS NULL
    CREATE DATABASE KestrelSales;
GO
USE KestrelSales;
GO
IF SCHEMA_ID(N'stg')  IS NULL EXEC (N'CREATE SCHEMA stg');
IF SCHEMA_ID(N'core') IS NULL EXEC (N'CREATE SCHEMA core');
IF SCHEMA_ID(N'bi')   IS NULL EXEC (N'CREATE SCHEMA bi');
IF SCHEMA_ID(N'qa')   IS NULL EXEC (N'CREATE SCHEMA qa');
GO
