-- 05 CALENDAR (DATE DIMENSION)
-- One row per day, 2023-2027. Power BI marks bi.dim_date as its date table, so time slicers and
-- month/quarter/half-year groupings come from one place instead of being recomputed in every visual.
-- Month names are spelled out (not DATENAME) so they don't change with the server's language setting.
USE KestrelSales;
GO
DROP TABLE IF EXISTS core.calendar;
CREATE TABLE core.calendar (
    [date]          DATE        NOT NULL CONSTRAINT PK_calendar PRIMARY KEY,
    [year]          SMALLINT    NOT NULL,
    quarter_no      TINYINT     NOT NULL,
    quarter_label   CHAR(7)     NOT NULL,   -- 2026-Q3
    half_label      CHAR(7)     NOT NULL,   -- 2026-H2
    month_no        TINYINT     NOT NULL,
    month_name      VARCHAR(9)  NOT NULL,
    year_month      CHAR(7)     NOT NULL,   -- 2026-08, same format as the *_month columns in core
    month_start     DATE        NOT NULL,
    is_month_start  BIT         NOT NULL
);
WITH n AS (
    SELECT TOP (DATEDIFF(DAY, '2023-01-01', '2027-12-31') + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
)
INSERT INTO core.calendar ([date], [year], quarter_no, quarter_label, half_label, month_no, month_name, year_month, month_start, is_month_start)
SELECT d.[date],
       YEAR(d.[date]),
       DATEPART(QUARTER, d.[date]),
       CONCAT(YEAR(d.[date]), '-Q', DATEPART(QUARTER, d.[date])),
       CONCAT(YEAR(d.[date]), CASE WHEN MONTH(d.[date]) <= 6 THEN '-H1' ELSE '-H2' END),
       MONTH(d.[date]),
       CHOOSE(MONTH(d.[date]), 'January', 'February', 'March', 'April', 'May', 'June',
                               'July', 'August', 'September', 'October', 'November', 'December'),
       CONVERT(CHAR(7), d.[date], 126),
       DATEFROMPARTS(YEAR(d.[date]), MONTH(d.[date]), 1),
       CASE WHEN DAY(d.[date]) = 1 THEN 1 ELSE 0 END
FROM n
CROSS APPLY (SELECT DATEADD(DAY, n.i, CAST('2023-01-01' AS DATE)) AS [date]) AS d;

SELECT COUNT(*) AS calendar_days, MIN([date]) AS first_day, MAX([date]) AS last_day FROM core.calendar;  -- expected 1826
GO
