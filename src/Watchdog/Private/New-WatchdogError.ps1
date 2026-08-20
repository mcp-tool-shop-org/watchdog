function New-WatchdogError {
  param(
    [Parameter(Mandatory)][string]$Code,
    [Parameter(Mandatory)][string]$Message,
    [string]$Hint = '',
    [string]$Cause = '',
    [bool]$Retryable = $false,
    [int]$ExitCode = 1
  )
  [pscustomobject]@{
    Kind       = 'Error'
    code       = $Code
    message    = $Message
    hint       = $Hint
    cause      = $Cause
    retryable  = $Retryable
    exitCode   = $ExitCode
  }
}

function Test-WatchdogError($Value) {
  return $null -ne $Value -and $Value.Kind -eq 'Error'
}

function Write-WatchdogError {
  param(
    [Parameter(Mandatory)]$ErrorObject,
    [switch]$IncludeStack
  )
  $lines = @(
    "WATCHDOG $($ErrorObject.code)"
    "message: $($ErrorObject.message)"
  )
  if ($ErrorObject.hint)  { $lines += "hint: $($ErrorObject.hint)" }
  if ($ErrorObject.cause) { $lines += "cause: $($ErrorObject.cause)" }
  $lines += "retryable: $($ErrorObject.retryable)"
  [Console]::Error.WriteLine(($lines -join [Environment]::NewLine))
  if ($IncludeStack -or $DebugPreference -eq 'Continue') {
    [Console]::Error.WriteLine(($ErrorObject | Format-List * | Out-String))
  }
}
