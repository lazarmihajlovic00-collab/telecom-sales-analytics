-- 02 BULK LOAD THE CLEAN CSVs INTO STAGING
-- 1. Set @path to the folder holding the clean CSVs (data\clean in this repo). Keep the trailing backslash.
-- 2. SQL Server itself reads the files, so its service account needs access to that folder.
--    "Operating system error 5 (Access is denied)" means it doesn't: copy the six CSVs to e.g. C:\KestrelData\
--    and point @path there.
-- Line endings: the files use LF. If Git converted them to CRLF on Windows, step 04 strips the extra CR.
USE KestrelSales;
GO
SET NOCOUNT ON;
DECLARE @path NVARCHAR(400) = N'D:\DataAnalysis\telecom-sales-analytics\data\clean\';

DECLARE @files TABLE (tbl SYSNAME, file_name NVARCHAR(100));
INSERT INTO @files VALUES (N'reps', N'reps.csv'), (N'products', N'products.csv'), (N'leads', N'leads.csv'),
                          (N'opportunities', N'opportunities.csv'), (N'customers', N'customers.csv'), (N'quotas', N'quotas.csv');

DECLARE @tbl SYSNAME, @file NVARCHAR(100), @sql NVARCHAR(MAX);
DECLARE f CURSOR LOCAL FAST_FORWARD FOR SELECT tbl, file_name FROM @files;
OPEN f;
FETCH NEXT FROM f INTO @tbl, @file;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'TRUNCATE TABLE stg.' + QUOTENAME(@tbl) + N';
BULK INSERT stg.' + QUOTENAME(@tbl) + N'
FROM ''' + REPLACE(@path + @file, N'''', N'''''') + N'''
WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'',
      CODEPAGE = ''65001'', KEEPNULLS, TABLOCK);';
    EXEC sys.sp_executesql @sql;
    PRINT CONCAT(N'Loaded stg.', @tbl, N' from ', @file);
    FETCH NEXT FROM f INTO @tbl, @file;
END
CLOSE f;
DEALLOCATE f;

-- Expected: reps 49, products 7, leads 77005, opportunities 28847, customers 9957, quotas 836
SELECT N'reps' AS tbl, COUNT(*) AS staged_rows FROM stg.reps
UNION ALL SELECT N'products', COUNT(*) FROM stg.products
UNION ALL SELECT N'leads', COUNT(*) FROM stg.leads
UNION ALL SELECT N'opportunities', COUNT(*) FROM stg.opportunities
UNION ALL SELECT N'customers', COUNT(*) FROM stg.customers
UNION ALL SELECT N'quotas', COUNT(*) FROM stg.quotas;
GO
