# Power Query + PivotTable workbook: guide

`dashboard/Kestrel_PowerQuery_Pivot.xlsx` does the core cleaning of `src/clean_data.py` a second time, in Excel
Power Query, straight from the raw exports in `data/raw/`. It then analyses the result with PivotTables and slicers,
and reconciles the PivotTables with the SQL outputs of the Python pipeline.

- M code: [`excel_power_query/queries/`](../excel_power_query/queries) (one `.m` file per query)
- Build script: [`excel_power_query/build_workbook.ps1`](../excel_power_query/build_workbook.ps1) (Windows, Excel 2016+)

```
powershell -ExecutionPolicy Bypass -File excel_power_query\build_workbook.ps1
```

The script adds the queries from the `.m` files, loads them, builds the PivotTables and slicers, and prints every check.
It exits with an error if any check fails.

## 1. Query design

```
Settings!B3 (named cell DataFolder)
   └─ pRawFolder ──► fnReadCsv(file) ──┬─ stg_Reps          (connection only)
                                       ├─ stg_Products      (connection only)
      map_Region, map_LeadSource ──────┼─ stg_Leads         (connection only)
      fnParseDate ─────────────────────┴─ fact_Opportunities ──► tblOpportunities ──► 4 PivotTables + 3 slicers
                                          qa_DataQuality     ──► tblDataQuality
```

| Query | Type | What it does |
|---|---|---|
| `pRawFolder` | parameter | Reads the folder path from the named cell `DataFolder`. The cell's formula works the path out from where the workbook is saved, so the file refreshes on any PC without editing M code. |
| `fnReadCsv` | function | `Csv.Document` + `Table.PromoteHeaders`. Keeps every column as text, so each query types its own columns. |
| `fnParseDate` | function | Parses `yyyy-mm-dd` and `dd/mm/yyyy` explicitly. Anything else raises an error instead of being guessed. |
| `map_Region`, `map_LeadSource` | table | Mapping tables: 14 raw region spellings → 6 regions, 12 raw source spellings → 7 sources. |
| `stg_Leads` | staging | Removes duplicates and test records, parses dates, merges the two mapping tables. |
| `stg_Reps`, `stg_Products` | staging | Removes the test user; adds a lower-case product key. |
| `fact_Opportunities` | fact, loaded | Strips `£`, types numbers with the `en-US` culture, matches products case-insensitively, recovers impossible discounts, labels blank loss reasons, flags impossible dates, merges leads (inner join), reps and products, and adds flags and calendar fields. |
| `qa_DataQuality` | checks, loaded | Counts every defect in the raw files and compares it with the Python cleaning log. |

### Decisions worth explaining

- **Culture.** `Number.FromText(x, "en-US")` and `Table.TransformColumnTypes(..., "en-US")`. On a PC with Serbian
  regional settings, `"25.0"` would otherwise be read with a comma decimal separator and fail or change its value.
- **Mapping tables instead of nested `if`s.** Adding a new spelling is one row in `map_Region`, not a code change.
  `qa_DataQuality` also checks that no region or source is left unmapped.
- **Recover, don't delete.** 54 discounts are impossible (150, 100, −10). The real value is
  `1 − net MRR / list price`, which holds exactly on every valid row, so the query recovers it. It also keeps a
  `discount_recovered` flag.
- **Flag, don't delete.** 36 deals close before they were created. They stay in win/loss counts but get no
  `sales_cycle_days`.
- **Inner join to leads** drops opportunities without a lead (0 here, but the rule is explicit).
- **Staging queries are connection only.** Only the fact table and the checks are loaded to sheets. This keeps the
  file small and gives the PivotTables one source.
- **FastCombine (ignore privacy levels).** The folder path comes from the workbook and the data comes from files.
  Without this setting, Power Query's privacy firewall blocks the combination (`Formula.Firewall`). Both sources are
  local, so nothing is sent anywhere.

## 2. PivotTables

All four PivotTables share one pivot cache on `tblOpportunities`. That is why one set of slicers (Region, Segment,
Close year) filters all of them.

| PivotTable | Rows × columns | Values | Filter |
|---|---|---|---|
| 1. Win rate by lead source | lead_source × close_year | calculated field `WinRate = is_won / is_closed` | is_closed = 1 |
| 2. Ordered MRR by team | team × close_year | Sum of mrr_gbp | is_won = 1 |
| 3. Where and why deals are lost | lost_reason × stage | Count of opp_id | outcome = Lost |
| 4. Door-to-Door discount vs win rate | discount_pct | Closed deals, WinRate | lead_source = Door-to-Door, is_closed = 1 |

The calculated field divides **sums**: Σ won / Σ closed. That is the correct win rate for any subtotal. An average
of per-row rates would be wrong.

## 3. Reconciliation (Checks sheet)

- **Win rate by lead source.** `GETPIVOTDATA` from PivotTable 1 next to
  `analysis/sql_outputs/03_win_rate_cycle_deal_size__channel_kpis.csv`.
- **Lost deals by stage and reason.** PivotTable 3 next to
  `analysis/sql_outputs/02_funnel_conversion__lost_reasons_by_stage.csv`.
- **Data quality.** Each defect count from Power Query next to `docs/data_quality_log.md`. This covers 924 duplicate
  leads, 1,602 UK dates, 4,596 region labels, 3,547 source labels, 1,472 `£` values, 879 product names, 54 discounts,
  1,434 blank loss reasons and 36 date errors. It ends with 28,847 clean opportunities and 77,005 clean leads.

The Excel route and the Python/SQL route are independent implementations of the same rules. When both give the same
numbers, the cleaning is reproducible.

## 4. Build it by hand (practice)

1. **Data → Get Data → From File → From Text/CSV** → `crm_opportunities_export.csv` → **Transform Data**.
2. Filter out `opp_id` containing `TEST` and `rep_id = R999`. Use **Remove Duplicates** on `opp_id`.
3. `mrr_gbp`: **Replace Values** `£` → nothing. Then **Change Type → Using Locale → Decimal Number, English (United States)**.
4. Load `product_catalogue.csv` and add a lower-case column on both sides (**Transform → Format → lowercase**).
   **Merge Queries** (left outer) and expand `product_id` and `list_mrr_gbp`.
5. **Add Column → Custom Column**:
   `if [discount_pct] >= 0 and [discount_pct] <= 50 then [discount_pct] else Number.Round((1 - [mrr_gbp]/[list_mrr_gbp])*100, 0)`.
6. Leads: **Remove Duplicates** on all columns. Map regions with a small mapping table and **Merge Queries**.
   Parse dates with **Change Type → Using Locale** (English (United Kingdom) for the dd/mm/yyyy rows).
7. Merge leads into opportunities (**inner join**) and reps (**left outer join**). Add `is_won` and `is_closed`
   with **Conditional Column**.
8. **Close & Load To… → Table**, then **Insert → PivotTable** from the table. Add the calculated field from
   **PivotTable Analyze → Fields, Items & Sets → Calculated Field**, and add slicers from **Insert → Slicer**.
   Connect them to every PivotTable with **Report Connections**.

## 5. Interview questions this answers

- *Why Power Query instead of formulas?* The steps are recorded and repeatable. A new export only needs
  **Refresh All**, and every step can be reviewed in the Applied Steps pane.
- *How do you handle mixed date formats?* Parse each known format explicitly and fail on anything else. Don't let
  the locale guess.
- *How do you know the PivotTable is right?* It is reconciled against an independent SQL implementation with
  `GETPIVOTDATA`, and every check is shown on the Checks sheet.
- *What is query folding?* Power Query pushes steps back to the source (for example as SQL). CSV files can't fold,
  so here every step runs locally. Against SQL Server, filters and column removal would fold.
