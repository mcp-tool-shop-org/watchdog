# Validate the watchdog abort path WITHOUT a real spill: a dummy venv-python target + an always-trip threshold.
# Confirms (a) it kills the sd-scripts venv python, (b) writes _watchdog_TRIPPED, (c) spares non-target python.
$ErrorActionPreference='Continue'
$root='E:\AI\training'; $venvPy="$root\sd-scripts\.venv\Scripts\python.exe"
Remove-Item "$root\_watchdog_STOP","$root\_watchdog_TRIPPED" -EA SilentlyContinue

# 1) dummy venv-python target (no spaces in -c to avoid Start-Process arg splitting)
$dummy = Start-Process -FilePath $venvPy -ArgumentList '-c',"__import__('time').sleep(120)" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$dummyId=$dummy.Id
"dummy venv-python PID=$dummyId alive=$([bool](Get-Process -Id $dummyId -EA SilentlyContinue))"

# 2) targeting check
$matched=@(Get-Process python -EA SilentlyContinue | Where-Object {$_.Path -eq $venvPy} | Select-Object -Expand Id)
$others =@(Get-Process python,pythonw -EA SilentlyContinue | Where-Object {$_.Path -ne $venvPy} | Select-Object -Expand Id)
"targeting: matched venv pids=[$($matched -join ',')]  | spared non-target python=[$($others -join ',')]"

# 3) real watchdog, always-trip (temp>=0), fast — detached
$wd = Start-Process -FilePath 'pwsh' -ArgumentList '-NonInteractive','-File',"$root\_watchdog.ps1",'-TempKillC','0','-BreachSamples','2','-IntervalSec','2' -PassThru -WindowStyle Hidden

# 4) wait up to ~16s for abort
$killed=$false
for($i=0;$i -lt 8;$i++){ Start-Sleep -Seconds 2; if(-not (Get-Process -Id $dummyId -EA SilentlyContinue)){$killed=$true;break} }

# 5) stop test watchdog
New-Item -ItemType File "$root\_watchdog_STOP" -Force | Out-Null; Start-Sleep -Seconds 3
Stop-Process -Id $wd.Id -Force -EA SilentlyContinue

# 6) report
"dummy killed by watchdog = $killed"
"_watchdog_TRIPPED = $(Get-Content "$root\_watchdog_TRIPPED" -EA SilentlyContinue)"
"--- _watchdog_KILL.log tail ---"; Get-Content "$root\_watchdog_KILL.log" -Tail 3 -EA SilentlyContinue
$survivors=@(Get-Process python,pythonw -EA SilentlyContinue | Where-Object {$_.Path -ne $venvPy} | Select-Object -Expand Id)
"non-target python still alive (good): [$($survivors -join ',')]"

# cleanup
Remove-Item "$root\_watchdog_STOP","$root\_watchdog_TRIPPED" -EA SilentlyContinue
if(-not (Get-Process -Id $dummyId -EA SilentlyContinue)){ "=== WATCHDOG TEST: PASS ===" }
else { Stop-Process -Id $dummyId -Force -EA SilentlyContinue; "=== WATCHDOG TEST: FAIL (dummy not killed) ===" }