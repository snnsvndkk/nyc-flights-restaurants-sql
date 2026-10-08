<#
.SYNOPSIS
    Checks that the SQL Server instance is reachable with Windows authentication.
.EXAMPLE
    .\scripts\test_connection.ps1
    .\scripts\test_connection.ps1 -ServerInstance localhost
#>
param(
    [string] $ServerInstance
)

. "$PSScriptRoot\common.ps1"
if (-not $ServerInstance) { $ServerInstance = $DefaultServerInstance }

$sqlcmd = Get-SqlcmdPath
Write-Host "sqlcmd : $sqlcmd"
Write-Host "server : $ServerInstance"

$query = @"
SET NOCOUNT ON;
SELECT CONCAT(@@SERVERNAME, ' | ',
              CAST(SERVERPROPERTY('Edition') AS nvarchar(60)), ' | ',
              CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(30)), ' | login: ',
              SUSER_SNAME());
"@

& $sqlcmd -S $ServerInstance -E -C -b -h -1 -W -Q $query
if ($LASTEXITCODE -ne 0) {
    throw "Could not connect to $ServerInstance. See 'Troubleshooting' in README.md."
}
Write-Host 'Connection OK.' -ForegroundColor Green
