<#
.SYNOPSIS
    Downloads the raw source files into data/raw/ (git-ignored).

.DESCRIPTION
    OpenFlights  : airports.dat, airlines.dat, routes.dat from the official GitHub repo.
    NYC DOHMH    : Restaurant Inspection Results (dataset 43nn-pn8j) through the
                   NYC Open Data SODA API, restricted to a subset - see $nycQuery below.

    Existing files are kept unless -Force is given.

.EXAMPLE
    .\scripts\download_data.ps1
    .\scripts\download_data.ps1 -Force
#>
param(
    [switch] $Force
)

. "$PSScriptRoot\common.ps1"

# Windows PowerShell 5.1 defaults to old TLS versions and a very slow progress bar.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

New-Item -ItemType Directory -Force -Path $RawDataDir | Out-Null

# ---------------------------------------------------------------------------
# NYC restaurant inspections: the exact subset
# ---------------------------------------------------------------------------
# The full dataset has ~300,000 rows (one row per violation cited in an inspection).
# We take every row whose inspection happened in calendar year 2025:
#   - a closed date range, so the subset does not grow every day like "last N months"
#   - it also drops the 1900-01-01 placeholder rows (restaurants not yet inspected)
# Only the columns the schema uses are requested.
# $limit is a safety cap well above the expected ~87,000 rows; the script fails if
# the cap is ever reached, because that would mean the subset was silently truncated.
$nycLimit = 200000
$nycQuery = [ordered]@{
    '$select' = 'camis,dba,boro,building,street,zipcode,phone,cuisine_description,' +
                'inspection_date,inspection_type,action,score,grade,grade_date,' +
                'violation_code,violation_description,critical_flag,latitude,longitude'
    '$where'  = "inspection_date between '2025-01-01T00:00:00' and '2025-12-31T23:59:59'"
    '$order'  = 'camis,inspection_date,inspection_type,violation_code'
    '$limit'  = $nycLimit
}
$nycUrl = 'https://data.cityofnewyork.us/resource/43nn-pn8j.csv?' + (
    ($nycQuery.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join '&'
)

$openFlightsBase = 'https://raw.githubusercontent.com/jpatokal/openflights/master/data'

$downloads = @(
    @{ File = 'airports.dat';                   Url = "$openFlightsBase/airports.dat" }
    @{ File = 'airlines.dat';                   Url = "$openFlightsBase/airlines.dat" }
    @{ File = 'routes.dat';                     Url = "$openFlightsBase/routes.dat" }
    @{ File = 'nyc_restaurant_inspections.csv'; Url = $nycUrl }
)

foreach ($item in $downloads) {
    $target = Join-Path $RawDataDir $item.File
    if ((Test-Path $target) -and -not $Force) {
        Write-Host "skip      $($item.File) (already downloaded, use -Force to refresh)"
        continue
    }
    Write-Host "download  $($item.File)"
    Write-Host "          $($item.Url)" -ForegroundColor DarkGray

    # Download to a temp name first so a failed download never leaves a half-written file.
    $partial = "$target.tmp"
    Invoke-WebRequest -Uri $item.Url -OutFile $partial -UseBasicParsing
    Move-Item -Force $partial $target
}

# ---------------------------------------------------------------------------
# Sanity checks and summary
# ---------------------------------------------------------------------------
Write-Host ''
$summary = foreach ($item in $downloads) {
    $target = Join-Path $RawDataDir $item.File
    if (-not (Test-Path $target) -or (Get-Item $target).Length -eq 0) {
        throw "$($item.File) is missing or empty."
    }
    # Physical line count (a quoted CSV field may span lines, so this is approximate
    # for the NYC file; load_data.ps1 reports the exact parsed row counts).
    $lines = 0
    $reader = [System.IO.File]::OpenText($target)
    try { while ($null -ne $reader.ReadLine()) { $lines++ } } finally { $reader.Dispose() }

    [pscustomobject]@{
        File   = $item.File
        SizeKB = [math]::Round((Get-Item $target).Length / 1KB)
        Lines  = $lines
    }
}
$summary | Format-Table -AutoSize

$nycLines = ($summary | Where-Object File -eq 'nyc_restaurant_inspections.csv').Lines
if ($nycLines - 1 -ge $nycLimit) {
    throw "The NYC download hit the `$limit cap ($nycLimit rows) - raise `$nycLimit so the subset is complete."
}

Write-Host "Raw files are in $RawDataDir" -ForegroundColor Green
