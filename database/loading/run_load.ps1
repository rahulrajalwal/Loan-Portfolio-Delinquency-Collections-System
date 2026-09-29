# =====================================================================
# Phase 4 - full load pipeline.
#
# Credentials come from MySQL's own obfuscated credential store, created once by:
#   mysql_config_editor set --login-path=loanproj --host=localhost --user=root --password
# No password appears in this script, in the shell history, or in any log.
#
# Usage:   powershell -File run_load.ps1
#          powershell -File run_load.ps1 -LoginPath myOtherPath
# =====================================================================
#
# Two ways to authenticate:
#   1. (default) login-path, set up once via mysql_config_editor - password stored obfuscated
#   2. -Prompt   ask for the password interactively at run time
#
# With -Prompt the password is read without echo and passed to mysql via the
# MYSQL_PWD environment variable of the child process only. It is never written
# to disk, never placed on a command line, and never appears in shell history
# or in the log files this script produces.
#
param(
    [string]$LoginPath = "loanproj",
    [string]$MysqlDir  = "C:\Program Files\MySQL\MySQL Server 8.0\bin",
    [switch]$Prompt,
    [string]$User      = "root"
)

$ErrorActionPreference = "Stop"

# Build the auth arguments once.
if ($Prompt) {
    $sec = Read-Host -Prompt "MySQL password for '$User'" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try   { $env:MYSQL_PWD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $authArgs = @("-u", $User, "-h", "localhost")
} else {
    $authArgs = @("--login-path=$LoginPath")
}
$mysql = Join-Path $MysqlDir "mysql.exe"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$db    = Split-Path -Parent $here          # ...\database
$logDir = Join-Path $here "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not (Test-Path $mysql)) { throw "mysql.exe not found at $mysql" }

function Invoke-SqlFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { throw "missing SQL file: $Path" }
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    $log  = Join-Path $logDir "$name.log"
    Write-Host ""
    Write-Host ("=" * 70)
    Write-Host "  $Label"
    Write-Host ("=" * 70)
    $sw = [Diagnostics.Stopwatch]::StartNew()

    # --local-infile=1 is required client-side for LOAD DATA LOCAL INFILE.
    # --show-warnings surfaces truncation/coercion that would otherwise pass silently.
    & $mysql @authArgs --local-infile=1 --show-warnings `
             --default-character-set=utf8mb4 -vv -e "source $($Path -replace '\\','/')" `
             *> $log
    $code = $LASTEXITCODE
    $sw.Stop()
    $mins = [math]::Round($sw.Elapsed.TotalMinutes, 2)

    if ($code -ne 0) {
        Write-Host "FAILED (exit $code) after $mins min. Last lines of $log :" -ForegroundColor Red
        Get-Content $log -Tail 25 | ForEach-Object { Write-Host "   $_" }
        throw "step '$Label' failed"
    }
    Write-Host ("  done in {0} min  ->  {1}" -f $mins, $log) -ForegroundColor Green
}

# --- connectivity check before doing anything expensive ------------------
Write-Host ("checking connection ({0}) ..." -f $(if ($Prompt) { "user $User" } else { "login-path '$LoginPath'" }))
$v = & $mysql @authArgs -N -B -e "SELECT VERSION();" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Cannot connect: $v" -ForegroundColor Red
    Write-Host "Either re-run with  -Prompt  to type the password interactively, or create" -ForegroundColor Yellow
    Write-Host "the stored credential once with:" -ForegroundColor Yellow
    Write-Host "   & '$MysqlDir\mysql_config_editor.exe' set --login-path=$LoginPath --host=localhost --user=root --password"
    throw "connection failed"
}
Write-Host "connected. server version: $v" -ForegroundColor Green

$total = [Diagnostics.Stopwatch]::StartNew()

Invoke-SqlFile (Join-Path $here "00_server_setup.sql")   "1/6  server settings (local_infile, buffer pool, durability)"
Invoke-SqlFile (Join-Path $db   "schema.sql")            "2/6  create database + 7 tables (primary keys only)"
Invoke-SqlFile (Join-Path $here "02_load_data.sql")      "3/6  bulk load 58.5M rows  <-- the long one"
Invoke-SqlFile (Join-Path $here "03_add_indexes.sql")    "4/6  build secondary indexes"
Invoke-SqlFile (Join-Path $here "04_verify_load.sql")    "5/6  verification + reconciliation"
Invoke-SqlFile (Join-Path $here "05_restore_settings.sql") "6/6  restore durable settings"

$total.Stop()
Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue   # clear the credential from this process
Write-Host ""
Write-Host ("ALL STEPS COMPLETE in {0} min" -f [math]::Round($total.Elapsed.TotalMinutes,2)) -ForegroundColor Green
Write-Host "Verification output: $logDir\04_verify_load.log"
