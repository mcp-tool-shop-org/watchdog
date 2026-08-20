function Update-WatchdogBreach {
  param(
    [int]$Count,
    [string[]]$Reasons,
    [int]$BreachSamples
  )
  $list = @($Reasons | Where-Object { $_ })
  if ($list.Count -eq 0) {
    return [pscustomobject]@{ Count = 0; State = 'ok'; ShouldAbort = $false }
  }
  $n = $Count + 1
  if ($n -ge $BreachSamples) {
    return [pscustomobject]@{ Count = $n; State = 'KILL'; ShouldAbort = $true }
  }
  return [pscustomobject]@{ Count = $n; State = "WARN($n/$BreachSamples)"; ShouldAbort = $false }
}
