# SQL Server version

The same nine analyses as `sql/` (SQLite), rebuilt on SQL Server as a small warehouse:
**staging → core → BI views**, with a validation script that checks 41 results against the
original Python/SQLite pipeline.

| Layer | Schema | What it holds |
|---|---|---|
| Staging | `stg` | Raw text copies of the six clean CSVs (bulk load never fails on a value) |
| Core | `core` | Typed tables with primary keys, foreign keys and CHECK constraints; a calendar; one settings row |
| BI | `bi` | Star-schema views for Power BI: 5 dimensions, 5 facts |
| Audit | `qa` | Conversion checks, load log, validation results (kept across runs) |

## Run order (SSMS, about 2 minutes)

| Script | Does | You should see |
|---|---|---|
| `00_create_database.sql` | Creates `KestrelSales` and the four schemas | "Commands completed" |
| `01_staging.sql` | Creates the staging tables | "Commands completed" |
| `02_load_staging.sql` | Bulk-loads the CSVs. **Edit `@path` first** | 49 / 7 / 77,005 / 28,847 / 9,957 / 836 rows |
| `03_core_tables.sql` | Creates typed tables, keys, constraints, indexes, settings, audit tables | "Commands completed" |
| `04_transform_load.sql` | Checks every conversion, then loads core in foreign-key order | Six rows, all `OK` |
| `05_calendar.sql` | Builds the date dimension | 1,826 days, 2023-01-01 to 2027-12-31 |
| `06_bi_views.sql` | Creates the Power BI views | 10 views |
| `07_analyses.sql` | Runs the nine analyses | 21 result sets |
| `08_validation.sql` | Compares 41 results with the original pipeline | Every row `PASS`, then `41 / 41` |

The last validation run is saved in [validation_results.csv](validation_results.csv): 41 checks, all `PASS`.

Requirements: SQL Server 2019 or later (free Developer or Express edition; tested on SQL Server 2025) and SSMS. `BULK INSERT ... FORMAT = 'CSV'` needs 2017+.

## If something fails

- **Access is denied (operating system error 5)** in 02: SQL Server's service account can't read your folder. Copy the six CSVs from `data/clean` to `C:\KestrelData\` and set `@path = N'C:\KestrelData\'`.
- **Named instance**: connect SSMS (and Power BI) to `localhost\<instance>` instead of `localhost`, e.g. `localhost\MSSQLSERVER01`, or `.\SQLEXPRESS` for Express.
- **"Invalid object name" in the SSMS Error List** right after the scripts create tables or views: IntelliSense's cache is stale; the script did not fail. Refresh it with Edit → IntelliSense → Refresh Local Cache (**Ctrl+Shift+R**). The Messages tab shows the real execution result.
- **04 stops with "Type conversion problems found"**: the result grid lists the table, column and number of bad values. Core tables are left untouched.
- **A FAIL in 08**: the row names the metric that differs. Run the matching block in 07 and compare with `analysis/sql_outputs/`.

## Design decisions

- **Staging is all text.** Types are applied in 04 with `TRY_CONVERT`, and every failure is counted per column, so bad data is reported instead of silently becoming NULL.
- **Integers stored as "12.0".** pandas writes integer columns that contain blanks as floats. Converting `'12.0'` straight to `INT` fails, so 04 converts through `DECIMAL` first.
- **Windows line endings.** If Git converts the CSVs to CRLF, the last column of every row would carry a hidden `\r`; 04 strips it.
- **0/1 flags are `TINYINT`, not `BIT`**, so `SUM(is_won)` counts rows exactly as in the original SQL.
- **Settings in one row** (`core.settings`): snapshot date, cohort cut-off, pipeline look-back and stub-quota threshold are defined once instead of being hard-coded across views.
- **Business rules live in the views**, not in Power BI: stage win probabilities, the quality cohort, stub quotas and the MRR running total are computed once in SQL, so the report and the SQL analyses can't drift apart.
