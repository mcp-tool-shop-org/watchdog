# Repo-root shim so `pwsh -File .\watchdog.ps1 status` works from a clone.
& (Join-Path $PSScriptRoot 'src\Watchdog\watchdog.ps1') @args
exit $LASTEXITCODE
