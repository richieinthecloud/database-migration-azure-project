<#
.SYNOPSIS
    Migrates local SQL Server databases to Azure SQL Database via BACPAC.

.DESCRIPTION
    For each database this script:
      1. Exports a .bacpac (schema + data in one portable file) from your LOCAL
         SQL Server instance using sqlpackage.
      2. Imports that .bacpac into the Azure logical SQL server.

    sqlpackage Import requires the target database to be EMPTY of user objects. If
    an import fails part-way, the target is left half-populated, and simply
    re-running would fail with "object already exists". To stay re-runnable, on an
    import failure this script uses Terraform to DESTROY and RECREATE that single
    database (making it empty again) and retries the import once.

    Run this AFTER `terraform apply` has provisioned the target server and the
    empty target databases. The import lands the data into those empty databases.

.PREREQUISITES
    - sqlpackage on your PATH:
      https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download
    - Terraform on your PATH (only needed if an import fails and must be retried).
    - The target server + databases already created by Terraform.
    - Your public IP allowed through the server firewall (Terraform does this).

.EXAMPLE
    $pw = Read-Host "Azure SQL admin password" -AsSecureString
    ./Migrate-Databases.ps1 `
        -LocalServer "localhost\SQLEXPRESS" `
        -AzureServer "sqlmig-lab-rac-001.database.windows.net" `
        -AzureAdminUser "sqladmin" `
        -AzureAdminPassword $pw

.NOTES
    A BACPAC is a point-in-time snapshot and is NOT transactionally consistent if
    the source database is being written to during export. For a real cutover,
    export from a copy/backup or during a quiet window. For a lab, this is fine.
#>

[CmdletBinding()]
param(
    [string]   $LocalServer = "localhost\SQLEXPRESS",
    [string[]] $Databases = @("Data_Warehouse", "MyDatabase", "nbadb", "SalesDB"),

    [Parameter(Mandatory)] [string]       $AzureServer,        # <name>.database.windows.net
    [Parameter(Mandatory)] [string]       $AzureAdminUser,     # e.g. sqladmin
    [Parameter(Mandatory)] [securestring] $AzureAdminPassword,

    [string] $BacpacDir = (Join-Path $PSScriptRoot "..\bacpacs"),
    [string] $TerraformDir = (Join-Path $PSScriptRoot "..\Terraform")
)

$ErrorActionPreference = "Stop"

# --- Helper: run one sqlpackage Import and return its exit code (does NOT throw,
#     so the caller can decide whether to recreate-and-retry). ---
function Invoke-BacpacImport {
    param(
        [string] $SourceFile,
        [string] $Server,
        [string] $Database,
        [string] $User,
        [string] $Password
    )
    sqlpackage /Action:Import `
        /SourceFile:$SourceFile `
        /TargetServerName:$Server `
        /TargetDatabaseName:$Database `
        /TargetUser:$User `
        /TargetPassword:$Password `
        /TargetEncryptConnection:True `
        /TargetTrustServerCertificate:False
    return $LASTEXITCODE
}

# --- Helper: destroy + recreate ONE database via Terraform, leaving it empty. ---
# `terraform apply -replace` targets just this database inside the for_each set,
# so its neighbours are left untouched. This is what makes a failed import
# recoverable without manual cleanup.
function Reset-AzureDatabase {
    param(
        [string] $DatabaseName,
        [string] $TerraformDir
    )
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw "Import of '$DatabaseName' failed and terraform is not on PATH, so the database cannot be recreated automatically. Install Terraform (or clear the database manually), then re-run."
    }

    # A for_each resource instance is addressed as <resource>["<key>"], where the
    # key is the database name. The inner double-quotes are escaped as \" so they
    # survive PowerShell and reach terraform.exe intact.
    $address = 'azurerm_mssql_database.dbs[\"' + $DatabaseName + '\"]'

    Write-Host "==> [$DatabaseName] Recreating empty database via Terraform:" -ForegroundColor Yellow
    Write-Host "    terraform -chdir=`"$TerraformDir`" apply -replace=$address -auto-approve" -ForegroundColor DarkGray

    terraform -chdir="$TerraformDir" apply -replace="$address" -auto-approve
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform failed to recreate '$DatabaseName' (exit $LASTEXITCODE). Recreate it manually, then re-run."
    }
}

# Confirm sqlpackage is available before doing anything.
if (-not (Get-Command sqlpackage -ErrorAction SilentlyContinue)) {
    throw "sqlpackage not found on PATH. Install it: https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download"
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
            /SourceDatabaseName:$db `
            /SourceTrustServerCertificate:True `
            /TargetFile:$bacpac
        if ($LASTEXITCODE -ne 0) { throw "Export of $db failed (exit $LASTEXITCODE)." }

        Write-Host "==> [$db] Importing into $AzureServer ..." -ForegroundColor Cyan
        $importCode = Invoke-BacpacImport -SourceFile $bacpac -Server $AzureServer `
            -Database $db -User $AzureAdminUser -Password $plainPwd

        if ($importCode -ne 0) {
            # The target may now be half-populated. Recreate it empty and retry ONCE.
            Write-Warning "[$db] Import failed (exit $importCode). Recreating the database and retrying once ..."
            Reset-AzureDatabase -DatabaseName $db -TerraformDir $TerraformDir

            Write-Host "==> [$db] Re-importing into $AzureServer ..." -ForegroundColor Cyan
            $importCode = Invoke-BacpacImport -SourceFile $bacpac -Server $AzureServer `
                -Database $db -User $AzureAdminUser -Password $plainPwd
            if ($importCode -ne 0) {
                throw "Import of $db failed again after recreate (exit $importCode). This usually means a schema/compatibility issue, not a transient error -- check the sqlpackage output above."
            }
        }

        Write-Host "==> [$db] Done." -ForegroundColor Green
    }

    Write-Host "`nAll databases migrated successfully." -ForegroundColor Green
}
finally {
    # Scrub the plaintext password from memory.
    if ($bstr) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $plainPwd = $null
}