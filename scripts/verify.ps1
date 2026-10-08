<#
.SYNOPSIS
    Runs every view and query against the loaded database and fails on any problem.

.DESCRIPTION
    Checks, in this order:
      1. Tables  - every clean table contains rows.
      2. Views   - each views/*.sql script runs without error, and
                   SELECT COUNT(*) from the view it creates returns more than zero rows.
      3. Queries - each queries/*.sql file runs without error, and every SELECT in it
                   returns at least one row.

    A file is split into batches on GO (like sqlcmd and SSMS do) and each batch is
    executed through ADO.NET, which gives an exact row count per result set and turns
    every SQL error into an exception.

    Exit code 0 = everything passed, 1 = at least one check failed.

.EXAMPLE
    .\scripts\verify.ps1
    .\scripts\verify.ps1 -ServerInstance localhost
#>
param(
    [string] $ServerInstance
)

. "$PSScriptRoot\common.ps1"
if (-not $ServerInstance) { $ServerInstance = $DefaultServerInstance }

# Splits a script into batches on lines that contain only GO.
function Split-SqlBatches {
    param([string] $Sql)
    [regex]::Split($Sql, '(?im)^[ \t]*GO[ \t]*;?[ \t]*\r?$') |
        Where-Object { $_.Trim() -ne '' }
}

# Executes all batches of a .sql file. Returns the row count of every result set.
function Invoke-SqlFileCounted {
    param(
        [System.Data.SqlClient.SqlConnection] $Connection,
        [string] $Path
    )
    $rowCounts = New-Object System.Collections.Generic.List[int]
    $sql = [System.IO.File]::ReadAllText($Path)

    foreach ($batch in Split-SqlBatches $sql) {
        $command = $Connection.CreateCommand()
        $command.CommandText    = $batch
        $command.CommandTimeout = 120
        $reader = $command.ExecuteReader()
        try {
            do {
                if ($reader.FieldCount -gt 0) {          # a result set, not a DDL/USE statement
                    $rows = 0
                    while ($reader.Read()) { $rows++ }
                    $rowCounts.Add($rows)
                }
            } while ($reader.NextResult())               # errors in later statements surface here
        }
        finally {
            $reader.Dispose()
            $command.Dispose()
        }
    }
    return ,$rowCounts
}

function Invoke-Scalar {
    param(
        [System.Data.SqlClient.SqlConnection] $Connection,
        [string] $Sql
    )
    $command = $Connection.CreateCommand()
    $command.CommandText = $Sql
    try { return $command.ExecuteScalar() } finally { $command.Dispose() }
}

$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string] $Kind, [string] $Name, [bool] $Passed, [string] $Detail)
    $results.Add([pscustomobject]@{
        Check  = $Kind
        Name   = $Name
        Status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        Detail = $Detail
    })
}

Write-Host "Verifying $DatabaseName on $ServerInstance ..."
$connection = New-SqlConnection -ServerInstance $ServerInstance -Database $DatabaseName

try {
    # --- 1. Tables ------------------------------------------------------------
    $tables = 'Countries', 'Airports', 'Airlines', 'Routes', 'Boroughs', 'Cuisines',
              'Restaurants', 'Inspections', 'ViolationCodes', 'InspectionViolations'
    foreach ($table in $tables) {
        try {
            $count = [long](Invoke-Scalar $connection "SELECT COUNT_BIG(*) FROM dbo.[$table];")
            Add-Result 'table' "dbo.$table" ($count -gt 0) "$count rows"
        }
        catch {
            Add-Result 'table' "dbo.$table" $false $_.Exception.GetBaseException().Message
        }
    }

    # --- 2. Views ---------------------------------------------------------------
    # Convention: views/vw_Something.sql creates the view dbo.vw_Something.
    foreach ($file in Get-ChildItem (Join-Path $RepoRoot 'views') -Filter '*.sql' | Sort-Object Name) {
        $viewName = $file.BaseName
        try {
            Invoke-SqlFileCounted $connection $file.FullName | Out-Null
            $count = [long](Invoke-Scalar $connection "SELECT COUNT_BIG(*) FROM dbo.[$viewName];")
            Add-Result 'view' "views/$($file.Name)" ($count -gt 0) "$count rows"
        }
        catch {
            Add-Result 'view' "views/$($file.Name)" $false $_.Exception.GetBaseException().Message
        }
    }

    # --- 3. Queries ---------------------------------------------------------------
    foreach ($file in Get-ChildItem (Join-Path $RepoRoot 'queries') -Filter '*.sql' | Sort-Object Name) {
        try {
            $rowCounts = Invoke-SqlFileCounted $connection $file.FullName
            $detail    = "$($rowCounts.Count) result set(s): $($rowCounts -join ', ') rows"
            if ($rowCounts.Count -eq 0) {
                Add-Result 'query' "queries/$($file.Name)" $false 'no result set returned'
            }
            else {
                Add-Result 'query' "queries/$($file.Name)" (-not ($rowCounts -contains 0)) $detail
            }
        }
        catch {
            Add-Result 'query' "queries/$($file.Name)" $false $_.Exception.GetBaseException().Message
        }
    }
}
finally {
    $connection.Dispose()
}

$results | Format-Table -AutoSize -Wrap

$failed = @($results | Where-Object Status -eq 'FAIL')
$views   = @($results | Where-Object Check -eq 'view')
$queries = @($results | Where-Object Check -eq 'query')

if ($views.Count -eq 0 -or $queries.Count -eq 0) {
    Write-Host 'VERIFICATION FAILED: no view or query files were found.' -ForegroundColor Red
    exit 1
}
if ($failed.Count -gt 0) {
    Write-Host "VERIFICATION FAILED: $($failed.Count) of $($results.Count) checks failed." -ForegroundColor Red
    exit 1
}
Write-Host "VERIFICATION PASSED: $($results.Count) of $($results.Count) checks passed." -ForegroundColor Green
exit 0
