# Shared helpers, dot-sourced by the other scripts in this folder.
# Everything connects with Windows authentication - no passwords anywhere.

$ErrorActionPreference = 'Stop'

$script:RepoRoot     = Split-Path -Parent $PSScriptRoot
$script:RawDataDir   = Join-Path $RepoRoot 'data\raw'
$script:DatabaseName = 'FlightsRestaurantsDB'

# Default server name. The "lpc:" prefix forces the Shared Memory protocol, which is
# always enabled for local connections. A default SQL Server Express install has
# TCP/IP and Named Pipes disabled and the SQL Browser service stopped, so the plain
# name "localhost\SQLEXPRESS" fails in the Go-based sqlcmd with
# "Timed out waiting for pipe". Override with -ServerInstance on any script.
$script:DefaultServerInstance = 'lpc:localhost\SQLEXPRESS'

function Get-SqlcmdPath {
    $cmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Not on PATH (e.g. the terminal was opened before the install) - try known locations.
    $candidates = @(
        "$env:ProgramFiles\sqlcmd\sqlcmd.exe"
        "$env:ProgramFiles\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\SQLCMD.EXE"
        "$env:ProgramFiles\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    throw 'sqlcmd was not found. Install it with: winget install -e --id Microsoft.Sqlcmd'
}

# Runs one .sql file with sqlcmd and throws if SQL Server reports an error.
#   -E  Windows authentication
#   -C  trust the instance's self-signed certificate (the ODBC sqlcmd encrypts by default)
#   -b  exit with a non-zero code on a SQL error
#   -I  QUOTED_IDENTIFIER ON, same as SSMS
#   -W  trim trailing spaces from result columns
#   -v  sqlcmd scripting variables, referenced in the .sql file as $(Name)
function Invoke-SqlFile {
    param(
        [Parameter(Mandatory)] [string] $ServerInstance,
        [Parameter(Mandatory)] [string] $Path,
        [string] $Database = 'master',
        [hashtable] $Variables = @{}
    )
    $sqlcmd = Get-SqlcmdPath
    $arguments = @('-S', $ServerInstance, '-E', '-C', '-b', '-I', '-W', '-d', $Database, '-i', $Path)
    foreach ($name in $Variables.Keys) {
        $arguments += @('-v', "$name=$($Variables[$name])")
    }

    Write-Host "  sqlcmd -i $(Split-Path -Leaf $Path)" -ForegroundColor DarkGray
    & $sqlcmd @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed (exit code $LASTEXITCODE) while running $Path"
    }
}

# Opens an ADO.NET connection (used for SqlBulkCopy and for the verification script).
function New-SqlConnection {
    param(
        [Parameter(Mandatory)] [string] $ServerInstance,
        [string] $Database = 'master'
    )
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source']            = $ServerInstance
    $builder['Initial Catalog']        = $Database
    $builder['Integrated Security']    = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Connect Timeout']        = 15

    $connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
    $connection.Open()
    return $connection
}
