<#
.SYNOPSIS
    Builds dashboard\Kestrel_PowerQuery_Pivot.xlsx: Power Query (M) cleaning of the raw CRM exports,
    PivotTables with slicers on the clean table, and a sheet that reconciles the pivots with the SQL outputs.

.DESCRIPTION
    The M code lives in excel_power_query\queries\*.m (one file per query) so it can be read and reviewed
    on GitHub. This script only assembles the workbook through Excel's COM object model:
      1. Settings sheet with the named cell DataFolder (path of data\raw\, worked out from the workbook location)
      2. Power Query queries added from the .m files; fact_Opportunities and qa_DataQuality loaded to tables
      3. Four PivotTables on one shared pivot cache, with Region and Segment slicers connected to all four
      4. Checks sheet: GETPIVOTDATA results next to the SQL outputs in analysis\sql_outputs\
    At the end it prints every check and exits with code 1 if any check fails.

    Requirements: Windows, Excel 2016 or later (Microsoft 365 recommended).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File excel_power_query\build_workbook.ps1
#>
param(
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$QueryDir = Join-Path $PSScriptRoot 'queries'
$SqlOut = Join-Path $Root 'analysis\sql_outputs'
if (-not $OutFile) { $OutFile = Join-Path $Root 'dashboard\Kestrel_PowerQuery_Pivot.xlsx' }
$Missing = [System.Reflection.Missing]::Value
$Pound = [char]163

# Excel constants
$xlSrcExternal = 0; $xlYes = 1; $xlCmdSql = 2; $xlDatabase = 1; $xlPivotVersion = 5
$xlRowField = 1; $xlColumnField = 2; $xlPageField = 3
$xlSum = -4157; $xlCount = -4112; $xlTabularRow = 1; $xlOpenXMLWorkbook = 51

$QueryOrder = @(
    'pRawFolder', 'fnReadCsv', 'fnParseDate', 'map_Region', 'map_LeadSource',
    'stg_Reps', 'stg_Products', 'stg_Leads', 'fact_Opportunities', 'qa_DataQuality'
)

function Add-Sheet($wb, [string]$name) {
    $ws = $wb.Worksheets.Add($Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
    $ws.Name = $name
    return $ws
}

function Load-QueryToTable($ws, [string]$queryName, [string]$tableName) {
    $conn = "OLEDB;Provider=Microsoft.Mashup.OleDb.1;Data Source=`$Workbook`$;Location=$queryName;Extended Properties=`"`""
    $lo = $ws.ListObjects.Add($xlSrcExternal, $conn, $Missing, $xlYes, $ws.Range('A1'))
    $lo.Name = $tableName
    $qt = $lo.QueryTable
    $qt.CommandType = $xlCmdSql
    $qt.CommandText = "SELECT * FROM [$queryName]"
    $qt.BackgroundQuery = $false
    $qt.AdjustColumnWidth = $true
    $qt.PreserveColumnInfo = $true
    [void]$qt.Refresh($false)
    $lo.TableStyle = 'TableStyleLight9'
    return $lo
}

function Set-Title($ws, [string]$cell, [string]$text, [int]$size = 12) {
    $r = $ws.Range($cell)
    $r.Value2 = $text
    $r.Font.Bold = $true
    $r.Font.Size = $size
}

if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
Write-Host "Building $OutFile"

$xl = New-Object -ComObject Excel.Application
$xl.Visible = $false
$xl.DisplayAlerts = $false
$wb = $null
$failures = 0
try {
    $wb = $xl.Workbooks.Add()
    $wsAbout = $wb.Worksheets.Item(1); $wsAbout.Name = 'About'
    $wsPivot = Add-Sheet $wb 'Pivots'
    $wsChecks = Add-Sheet $wb 'Checks'
    $wsDq = Add-Sheet $wb 'DataQuality'
    $wsOpp = Add-Sheet $wb 'Opportunities'
    $wsSet = Add-Sheet $wb 'Settings'

    # ---------------------------------------------------------------- Settings + DataFolder
    Set-Title $wsSet 'A1' 'Settings' 14
    $wsSet.Range('A3').Value2 = 'Raw data folder'
    $wsSet.Range('B3').Formula = '=IFERROR(SUBSTITUTE(LEFT(CELL("filename",$A$1),FIND("[",CELL("filename",$A$1))-1),"\dashboard\","\data\raw\"),"")'
    $wsSet.Range('A5').Value2 = 'B3 works out <repository>\data\raw\ from where this workbook is saved (<repository>\dashboard\).'
    $wsSet.Range('A6').Value2 = 'If the CSV files are somewhere else, type that folder into B3 (for example D:\data\raw\), then Data > Refresh All.'
    $wsSet.Columns.Item(1).ColumnWidth = 18
    $wsSet.Columns.Item(2).ColumnWidth = 90
    [void]$wb.Names.Add('DataFolder', '=Settings!$B$3')

    # Save first so CELL("filename") returns the real path, then recalculate.
    $wb.SaveAs($OutFile, $xlOpenXMLWorkbook)
    $xl.CalculateFull()
    Write-Host ("DataFolder = " + $wsSet.Range('B3').Text)

    # ---------------------------------------------------------------- Power Query
    foreach ($q in $QueryOrder) {
        $m = Get-Content -Raw -Encoding UTF8 (Join-Path $QueryDir "$q.m")
        $desc = (($m -split "`n")[0] -replace '^//\s*', '').Trim()
        [void]$wb.Queries.Add($q, $m, $desc)
    }
    # The folder path comes from the workbook and the data from files: tell Power Query to combine them
    # without privacy-level partitioning (otherwise Formula.Firewall stops the refresh).
    $wb.Queries.FastCombine = $true

    Write-Host 'Loading fact_Opportunities ...'
    $loOpp = Load-QueryToTable $wsOpp 'fact_Opportunities' 'tblOpportunities'
    Write-Host ("  rows: " + $loOpp.ListRows.Count)
    Write-Host 'Loading qa_DataQuality ...'
    $loDq = Load-QueryToTable $wsDq 'qa_DataQuality' 'tblDataQuality'

    # ---------------------------------------------------------------- PivotTables (one shared cache)
    $pc = $wb.PivotCaches().Create($xlDatabase, 'tblOpportunities', $xlPivotVersion)

    function New-Pivot([string]$anchor, [string]$name) {
        $pt = $pc.CreatePivotTable($wsPivot.Range($anchor), $name, $true, $xlPivotVersion)
        $pt.RowAxisLayout($xlTabularRow)
        $pt.TableStyle2 = 'PivotStyleMedium2'
        $pt.ShowDrillIndicators = $false
        return $pt
    }
    function Set-Page($pt, [string]$field, [string]$item) {
        $pf = $pt.PivotFields($field)
        $pf.Orientation = $xlPageField
        $pf.CurrentPage = $item
    }

    Set-Title $wsPivot 'B1' 'Kestrel Fibre: sales PivotTables on Power Query output (synthetic data)' 14
    $wsPivot.Range('B2').Value2 = 'Source: table tblOpportunities (Opportunities sheet), built by Power Query from data\raw\. Use the slicers on the right; Data > Refresh All reloads everything.'

    # 1. Win rate by lead source and close year
    Set-Title $wsPivot 'B5' '1. Win rate by lead source (closed deals)'
    $pt1 = New-Pivot 'B9' 'ptWinRateBySource'
    [void]$pt1.CalculatedFields().Add('WinRate', '=is_won/is_closed', $true)
    Set-Page $pt1 'is_closed' '1'
    $pt1.PivotFields('lead_source').Orientation = $xlRowField
    $pt1.PivotFields('close_year').Orientation = $xlColumnField
    $df = $pt1.AddDataField($pt1.PivotFields('WinRate'), 'Win rate', $xlSum)
    $df.NumberFormat = '0.0%'

    # 2. Ordered MRR by team and close year
    Set-Title $wsPivot 'J5' '2. Ordered MRR by team (won deals)'
    $pt2 = New-Pivot 'J9' 'ptOrderedMrrByTeam'
    Set-Page $pt2 'is_won' '1'
    $pt2.PivotFields('team').Orientation = $xlRowField
    $pt2.PivotFields('close_year').Orientation = $xlColumnField
    $df = $pt2.AddDataField($pt2.PivotFields('mrr_gbp'), "Ordered MRR ($Pound)", $xlSum)
    $df.NumberFormat = "[`$$Pound-809]#,##0"

    # 3. Lost deals by reason and stage
    Set-Title $wsPivot 'B27' '3. Where and why deals are lost'
    $pt3 = New-Pivot 'B31' 'ptLostReasons'
    Set-Page $pt3 'outcome' 'Lost'
    $pt3.PivotFields('lost_reason').Orientation = $xlRowField
    $pt3.PivotFields('stage').Orientation = $xlColumnField
    $df = $pt3.AddDataField($pt3.PivotFields('opp_id'), 'Lost deals', $xlCount)
    $df.NumberFormat = '#,##0'

    # 4. Door-to-door win rate by discount
    Set-Title $wsPivot 'J27' '4. Door-to-Door: does a bigger discount win more deals?'
    $pt4 = New-Pivot 'J31' 'ptDiscountWinRate'
    Set-Page $pt4 'lead_source' 'Door-to-Door'
    Set-Page $pt4 'is_closed' '1'
    $pt4.PivotFields('discount_pct').Orientation = $xlRowField
    $df = $pt4.AddDataField($pt4.PivotFields('is_closed'), 'Closed deals', $xlSum)
    $df.NumberFormat = '#,##0'
    $df = $pt4.AddDataField($pt4.PivotFields('WinRate'), 'Win rate', $xlSum)
    $df.NumberFormat = '0.0%'
    $wsPivot.Range('J45').Value2 = 'Win rate rises from 0% to 10% discount, then stops rising: discounts above 10% buy no extra wins (README finding 3).'
    $wsPivot.Range('J45').Font.Italic = $true

    # Slicers connected to all four PivotTables
    $left = $wsPivot.Range('Q5').Left
    $top = $wsPivot.Range('Q5').Top
    $sliceDefs = @(@('region', 'Region', 200), @('segment', 'Segment', 90), @('close_year', 'Close year', 110))
    foreach ($s in $sliceDefs) {
        $sc = $wb.SlicerCaches.Add2($pt1, $s[0])
        foreach ($pt in @($pt2, $pt3, $pt4)) { $sc.PivotTables.AddPivotTable($pt) }
        [void]$sc.Slicers.Add($wsPivot, $Missing, ('sl_' + $s[0]), $s[1], $top, $left, 160, $s[2])
        $top += $s[2] + 10
    }
    $wsPivot.Columns.Item(1).ColumnWidth = 2

    # ---------------------------------------------------------------- Checks (pivot vs SQL outputs)
    Set-Title $wsChecks 'A1' 'Reconciliation: PivotTables (Power Query data) vs SQL outputs (Python/SQLite pipeline)' 14
    $wsChecks.Range('A2').Value2 = 'Clear all slicers on the Pivots sheet before reading this sheet: the pivot values below follow the slicers.'
    $row = 4
    Set-Title $wsChecks "A$row" 'A. Win rate by lead source (sql_outputs\03_win_rate_cycle_deal_size__channel_kpis.csv)'
    $row++
    $hdr = @('Lead source', 'SQL win rate', 'Pivot win rate', 'Difference', 'Status')
    for ($c = 0; $c -lt $hdr.Count; $c++) { $wsChecks.Cells.Item($row, $c + 1).Value2 = $hdr[$c] }
    $wsChecks.Range("A${row}:E${row}").Font.Bold = $true
    $pt1Anchor = 'Pivots!' + $pt1.TableRange1.Cells.Item(1, 1).Address($true, $true)
    foreach ($r in (Import-Csv (Join-Path $SqlOut '03_win_rate_cycle_deal_size__channel_kpis.csv'))) {
        $row++
        $wsChecks.Cells.Item($row, 1).Value2 = $r.lead_source
        $wsChecks.Cells.Item($row, 2).Value2 = [double]::Parse($r.win_rate, [Globalization.CultureInfo]::InvariantCulture)
        $wsChecks.Cells.Item($row, 3).Formula = "=GETPIVOTDATA(`"Win rate`",$pt1Anchor,`"lead_source`",A$row)"
        $wsChecks.Cells.Item($row, 4).Formula = "=ROUND(C$row,3)-B$row"
        $wsChecks.Cells.Item($row, 5).Formula = "=IF(ABS(D$row)<0.0005,`"OK`",`"CHECK`")"
        $wsChecks.Range("B${row}:D${row}").NumberFormat = '0.0%'
    }

    $row += 2
    Set-Title $wsChecks "A$row" 'B. Lost deals by stage and reason (sql_outputs\02_funnel_conversion__lost_reasons_by_stage.csv)'
    $row++
    $hdr = @('Stage', 'Lost reason', 'SQL count', 'Pivot count', 'Status')
    for ($c = 0; $c -lt $hdr.Count; $c++) { $wsChecks.Cells.Item($row, $c + 1).Value2 = $hdr[$c] }
    $wsChecks.Range("A${row}:E${row}").Font.Bold = $true
    $pt3Anchor = 'Pivots!' + $pt3.TableRange1.Cells.Item(1, 1).Address($true, $true)
    foreach ($r in (Import-Csv (Join-Path $SqlOut '02_funnel_conversion__lost_reasons_by_stage.csv'))) {
        $row++
        $wsChecks.Cells.Item($row, 1).Value2 = $r.lost_at_stage
        $wsChecks.Cells.Item($row, 2).Value2 = $r.lost_reason
        $wsChecks.Cells.Item($row, 3).Value2 = [int]$r.n
        $wsChecks.Cells.Item($row, 4).Formula = "=GETPIVOTDATA(`"Lost deals`",$pt3Anchor,`"stage`",A$row,`"lost_reason`",B$row)"
        $wsChecks.Cells.Item($row, 5).Formula = "=IF(C$row=D$row,`"OK`",`"CHECK`")"
    }

    $row += 2
    Set-Title $wsChecks "A$row" 'C. Data-quality findings: Power Query vs Python cleaning log (see DataQuality sheet)'
    $row++
    $wsChecks.Cells.Item($row, 1).Value2 = 'Checks marked OK'
    $wsChecks.Cells.Item($row, 2).Formula = '=COUNTIF(tblDataQuality[status],"OK")&" of "&ROWS(tblDataQuality[status])'
    $row += 2
    $wsChecks.Cells.Item($row, 1).Value2 = 'All checks'
    $wsChecks.Cells.Item($row, 1).Font.Bold = $true
    $lastCheckRow = $row - 3
    $wsChecks.Cells.Item($row, 2).Formula = "=IF(AND(COUNTIF(E5:E$lastCheckRow,`"CHECK`")=0,COUNTIF(tblDataQuality[status],`"CHECK`")=0),`"ALL OK`",`"SEE CHECK ROWS`")"
    $wsChecks.Cells.Item($row, 2).Font.Bold = $true
    $wsChecks.Columns.Item(1).ColumnWidth = 18
    $wsChecks.Columns.Item(2).ColumnWidth = 28
    $wsChecks.Range('C:E').ColumnWidth = 14

    # ---------------------------------------------------------------- About
    $about = @(
        @('Kestrel Fibre: Power Query + PivotTable workbook (synthetic data)', 14),
        @('', 0),
        @('What it does', 12),
        @('Power Query reads the RAW CRM, HR and product exports in data\raw\ (with their deliberate defects) and cleans them in Excel:', 0),
        @('removes duplicate and test records, parses ISO and UK (dd/mm/yyyy) dates, maps 15 region and 12 lead-source spellings to canonical values,', 0),
        @('strips the pound sign from MRR stored as text, matches product names case-insensitively, recovers 54 impossible discounts from list price vs net MRR,', 0),
        @('labels blank loss reasons, flags impossible close dates, and merges lead, product and rep attributes into one fact table (tblOpportunities).', 0),
        @('', 0),
        @('Sheets', 12),
        @('Pivots: four PivotTables on one pivot cache (win rate by source and year, ordered MRR by team, lost deals by stage and reason, discount vs win rate) with Region, Segment and Close year slicers.', 0),
        @('Checks: the PivotTable results next to the SQL pipeline outputs (GETPIVOTDATA). Every row should say OK.', 0),
        @('DataQuality: what Power Query found in the raw files next to what the Python cleaning log found.', 0),
        @('Opportunities: the clean fact table loaded by Power Query (about 28,800 rows).', 0),
        @('Settings: the folder of the raw CSV files (named cell DataFolder).', 0),
        @('', 0),
        @('Queries (Data > Queries & Connections)', 12),
        @('pRawFolder, fnReadCsv, fnParseDate: parameter and helper functions | map_Region, map_LeadSource: mapping tables | stg_Reps, stg_Products, stg_Leads: staging (connection only) | fact_Opportunities: loaded table | qa_DataQuality: checks', 0),
        @('The M code of every query is also in excel_power_query\queries\ in the repository.', 0),
        @('', 0),
        @('Refresh', 12),
        @('Keep the workbook in <repository>\dashboard\ (or type the data folder on the Settings sheet), then Data > Refresh All.', 0),
        @('Synthetic data: Kestrel Fibre is fictional. Numbers illustrate the method, not a real company.', 0)
    )
    for ($i = 0; $i -lt $about.Count; $i++) {
        $cell = $wsAbout.Cells.Item($i + 1, 1)
        $cell.Value2 = $about[$i][0]
        if ($about[$i][1] -gt 0) { $cell.Font.Bold = $true; $cell.Font.Size = $about[$i][1] }
    }

    foreach ($ws in @($wsAbout, $wsPivot, $wsChecks, $wsDq, $wsOpp, $wsSet)) { $ws.Activate(); $xl.ActiveWindow.DisplayGridlines = $false }
    $wsPivot.Activate()
    $wsPivot.Range('A1').Select()
    $xl.CalculateFull()
    $wb.Save()

    # ---------------------------------------------------------------- Report
    Write-Host ''
    Write-Host 'Data-quality checks (Power Query vs Python):'
    foreach ($lr in $loDq.ListRows) {
        $t = @(1..6 | ForEach-Object { $lr.Range.Cells.Item(1, $_).Text })
        Write-Host ('  {0,-14} {1,-48} PQ={2,-7} Py={3,-7} {4}' -f $t[0], $t[1], $t[2], $t[3], $t[5])
        if ($t[5] -ne 'OK') { $failures++ }
    }
    Write-Host ''
    Write-Host 'Pivot vs SQL checks:'
    for ($r = 5; $r -le $lastCheckRow; $r++) {
        $status = $wsChecks.Cells.Item($r, 5).Text
        if ($status -eq 'OK' -or $status -eq 'CHECK') {
            Write-Host ('  {0,-14} {1,-28} {2,-10} {3,-10} {4}' -f $wsChecks.Cells.Item($r, 1).Text, $wsChecks.Cells.Item($r, 2).Text, $wsChecks.Cells.Item($r, 3).Text, $wsChecks.Cells.Item($r, 4).Text, $status)
            if ($status -ne 'OK') { $failures++ }
        }
        elseif ($status.StartsWith('#')) {
            Write-Host ('  row {0}: {1}' -f $r, $status); $failures++
        }
    }
    Write-Host ''
    if ($failures -eq 0) { Write-Host "ALL CHECKS OK. Saved $OutFile" -ForegroundColor Green }
    else { Write-Host "$failures check(s) failed. Saved $OutFile" -ForegroundColor Red }
}
finally {
    if ($wb) { $wb.Close($false) }
    $xl.Quit()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($xl)
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
if ($failures -gt 0) { exit 1 }
