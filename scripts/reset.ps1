<#
.SYNOPSIS
    One command to drop FlightsRestaurantsDB and rebuild it from scratch.

.DESCRIPTION
    1. Drops the database (open connections to it are closed).
    2. Runs build_database.ps1: database, tables, data, views.

    -Download also re-downloads the raw files instead of reusing data/raw/.

.EXAMPLE
    .\scripts\reset.ps1
    .\scripts\reset.ps1 -Download
    .\scripts\reset.ps1 -ServerInstance localhost
#>
param(
    [string] $ServerInstance,
    [switch] $Download
)

. "$PSScriptRoot\common.ps1"
if (-not $ServerInstance) { $ServerInstance = $DefaultServerInstance }

if ($Download) {
    & "$PSScriptRoot\download_data.ps1" -Force
}

Write-Host "`n[reset] Dropping $DatabaseName" -ForegroundColor Cyan
Invoke-SqlFile -ServerInstance $ServerInstance -Path (Join-Path $RepoRoot 'sql\00_drop_database.sql')

& "$PSScriptRoot\build_database.ps1" -ServerInstance $ServerInstance
