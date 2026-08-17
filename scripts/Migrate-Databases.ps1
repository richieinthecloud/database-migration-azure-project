<#
.SYNOPSIS
    Migrates local SQL Server databases to Azure SQL Database via BACPAC.

.DESCRIPTION
    For each database, this script:
        1. Exports a .BACPAC (Schema + data in one file) from your local SQL server instance using sqlpackage. 
        2. Imports that .BACPAC into the Azure logical SQL Server. 

    Run this AFTER 'terraform apply' has provisioned the target server and the empty target databases. The import lands the data into those empty databases.

.PREREQUISITES
    - sqlpackage on your PATH:
    https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download 
    - The target server + databases already created by Terraform 
    - Your public IP allowed through the server firewall (Terraform manages this).

.EXAMPLE
    $pw = Read-Host "Azure SQL admin password" -AsSecureString
    ./Migrate-Databases.ps1 `
        -LocalServer "localhost" `
        -AzureServer "sqlmig-lab-rac-001.database.windows.net" `
        -AzureAdminUser "sqladmin" `
        -AzureAdminPassword $pw `

.NOTES
    A BACPAC is a point-in-time snapshot and is NOT transactionally consistent if the source database is
    being written to during export. For a real cutover, export from a copy/backup or during a quiet window.
    For a lab, this is okay. 
#>

[CmdletBinding()]
param (
    [string] $LocalServer = "localhost",
    [string] $Databases = @("Data_Warehouse", "MyDatabase", "nbadb", "SalesDB"),

    [Parameter(Mandatory)] [string] $AzureServer, #sqlmig-lab-rac-001.database.windows.net
    [Parameter(Mandatory)] [string] $AzureAdminUser, #sqladmin
    [Parameter(Mandatory)] [SecureString] $AzureAdminPassword,

    [string] $BacpacDir = (Join-Path $PSScriptRoot "..\bacpacs")
)

$ErrorActionPreference = "Stop"

# Confirm sqlpackage is available before doing anything.
if (-not (Get-Command sqlpackage -ErrorAction SilentlyContinue)) {
    throw "sqlpackage not found on PATH. Install it from https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download"
}

New-Item -ItemType Directory -Force -Path $BacpacDir | Out-Null

# Convert the SecureString to plain text only for the sqlpackage argument. 
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AzureAdminPassword)
$plainPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

try {
    foreach ($db in $Databases) {
        $bacpac = Join-Path $BacpacDir "$db.bacpac"

        Write-Host "==> [$db] Exporting from $LocalServer ..." -ForegroundColor Cyan
        sqlpackage /Action:Export `
            /SourceServerName:$LocalServer `
            /SourceDatabasesName:$db `
            /SourceTrustServerCertificate:True `
            /TargetFile:$bacpac
        if ($LASTEXITCODE -ne 0) { throw "Export of $db failed (exit $LASTEXITCODE)" }

        Write-Host "==> [$db] Importing into $AzureServer ..." -ForegroundColor Cyan
        sqlpackage /Action:Import `
            /SourceFile:$bacpac `
            /TargetServerName:$AzureServer `
            /TargetDatabaseName:$db `
            /TargetUser:$AzureAdminUser `
            /TargetPassword:$plainPwd `
            /TargetEncryptConnection:True `
            /TargetTrustServerCertificate:False
        if ($LASTEXITCODE -ne 0) { throw "Import of $db failed (exit $LASTEXITCODE)" }

        Write-Host "==> [$db] Done." -ForegroundColor Green
    }

    Write-Host "`nAll databases migrated successfully." -ForegroundColor Green
}
finally {
    # Scrub the plaintext password from memory.
    if (bstr) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $plainPwd = $null
}