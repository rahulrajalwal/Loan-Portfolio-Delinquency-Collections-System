# =====================================================================
# Generic SQL runner for the analytical phases.
#
#   powershell -File run_sql.ps1 -Prompt  <path-to-sql>       # type password
#   powershell -File run_sql.ps1          <path-to-sql>       # use stored login-path
#
# Output goes to <same-folder>\logs\<sqlfilename>.log as UTF-8, so results can
# be read back and reviewed. Errors stop the run and print the tail.
# =====================================================================
param(
    [Parameter(Mandatory=$true, Position=0)][string]$SqlFile,
    [switch]$Prompt,
    [string]$LoginPath = "loanproj",
    [string]$User      = "root",
    [string]$MysqlDir  = "C:\Program Files\MySQL\MySQL Server 8.0\bin"
)

$ErrorActionPreference = "Stop"
$mysql = Join-Path $MysqlDir "mysql.exe"
if (-not (Test-Path $mysql))   { throw "mysql.exe not found at $mysql" }
if (-not (Test-Path $SqlFile)) { throw "SQL file not found: $SqlFile" }

if ($Prompt) {
    $sec  = Read-Host -Prompt "MySQL password for '$User'" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try   { $env:MYSQL_PWD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $authArgs = @("-u", $User, "-h", "localhost")
} else {
    $authArgs = @("--login-path=$LoginPath")
}

$sqlPath = (Resolve-Path $SqlFile).Path
$logDir  = Join-Path (Split-Path -Parent $sqlPath) "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("{0}.log" -f [IO.Path]::GetFileNameWithoutExtension($sqlPath))

Write-Host "running: $sqlPath"
$sw = [Diagnostics.Stopwatch]::StartNew()

# --table gives aligned output; results are written as UTF-8 so they read back cleanly.
& $mysql @authArgs --local-infile=1 --default-character-set=utf8mb4 --table `
         -e "source $($sqlPath -replace '\\','/')" 2>&1 |
    Out-File -FilePath $log -Encoding utf8

$code = $LASTEXITCODE
$sw.Stop()
Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue

if ($code -ne 0) {
    Write-Host ("FAILED (exit {0}) after {1:N1}s" -f $code, $sw.Elapsed.TotalSeconds) -ForegroundColor Red
    Get-Content $log -Tail 30 | ForEach-Object { Write-Host "   $_" }
    exit $code
}
Write-Host ("done in {0:N1}s  ->  {1}" -f $sw.Elapsed.TotalSeconds, $log) -ForegroundColor Green
