$ErrorActionPreference = 'Stop'

Set-Location -Path $PSScriptRoot

# Keep one previous generation so the log cannot grow without bound.
$log = 'archive.log'
if ((Test-Path $log) -and ((Get-Item $log).Length -gt 1MB)) {
    Move-Item -Force $log "$log.1"
}

Write-Output "=== run started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') ==="

if (-not (Test-Path 'node_modules')) {
    npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

node ./archive-version
$rc = $LASTEXITCODE

Write-Output "=== run finished rc=$rc $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K') ==="
exit $rc
