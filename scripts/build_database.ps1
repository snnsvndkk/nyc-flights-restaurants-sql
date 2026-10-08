<#
.SYNOPSIS
    Builds FlightsRestaurantsDB: database, tables, data and views.

.DESCRIPTION
    Runs the numbered scripts in sql/ in order, then every view in views/.
    Safe to run again: the table script drops and re-creates the tables, so the data
    is always loaded into empty tables. Downloads the raw files first if they are missing.

    To also drop the database itself first, use reset.ps1.

.EXAMPLE
    .\scripts\build_database.ps1
    .\scripts\build_database.ps1 -ServerInstance localhost
#>
param(
    [string] $ServerInstance
)

. "$PSScriptRoot\common.ps1"
if (-not $ServerInstance) { $ServerInstance = $DefaultServerInstance }

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$sqlDir    = Join-Path $RepoRoot 'sql'
$viewsDir  = Join-Path $RepoRoot 'views'

# --- 0. Raw data ------------------------------------------------------------
$rawFiles = 'airports.dat', 'airlines.dat', 'routes.dat', 'nyc_restaurant_inspections.csv'
$missing  = $rawFiles | Where-Object { -not (Test-Path (Join-Path $RawDataDir $_)) }
if ($missing) {
    Write-Host "Raw files missing ($($missing -join ', ')) - downloading." -ForegroundColor Yellow
    & "$PSScriptRoot\download_data.ps1"
}

# --- 1. Database and tables ---------------------------------------------------
Write-Host "`n[1/4] Database and tables" -ForegroundColor Cyan
Invoke-SqlFile -ServerInstance $ServerInstance -Path "$sqlDir\01_create_database.sql"
Invoke-SqlFile -ServerInstance $ServerInstance -Path "$sqlDir\02_create_tables.sql"
Invoke-SqlFile -ServerInstance $ServerInstance -Path "$sqlDir\03_create_staging_tables.sql"

# --- 2. Raw files -> staging tables -----------------------------------------
Write-Host "`n[2/4] Bulk load raw files into staging" -ForegroundColor Cyan
Invoke-SqlFile -ServerInstance $ServerInstance -Path "$sqlDir\04_load_staging.sql" `
               -Variables @{ RawDataDir = $RawDataDir }

# --- 3. Staging -> clean tables ----------------------------------------------
Write-Host "`n[3/4] Clean and load into the normalized tables" -ForegroundColor Cyan
Invoke-SqlFile -ServerInstance $ServerInstance -Path "$sqlDir\05_load_openflights.sql"
Invoke-SqlFile -ServerInstance $ServerInstance -Path "$sqlDir\06_load_restaurants.sql"

# --- 4. Views -------------------------------------------------------------------
Write-Host "`n[4/4] Views" -ForegroundColor Cyan
$viewFiles = @(Get-ChildItem -Path $viewsDir -Filter '*.sql' -ErrorAction SilentlyContinue | Sort-Object Name)
if ($viewFiles.Count -eq 0) { Write-Host '  (no view scripts found)' -ForegroundColor DarkGray }
foreach ($file in $viewFiles) {
    Invoke-SqlFile -ServerInstance $ServerInstance -Path $file.FullName -Database $DatabaseName
}

# --- Summary --------------------------------------------------------------------
Write-Host "`nRow counts" -ForegroundColor Cyan
Invoke-SqlFile -ServerInstance $ServerInstance -Path "$sqlDir\07_row_counts.sql"

$stopwatch.Stop()
Write-Host ("`nBuild finished in {0:n1} s on {1}." -f $stopwatch.Elapsed.TotalSeconds, $ServerInstance) -ForegroundColor Green
