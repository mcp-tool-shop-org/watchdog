@{
  # Directory for heartbeat, CSV, kill log, console log, and sentinels.
  # Must be absolute. The module will not write outside this directory.
  Root = 'C:\watchdog-state'

  # Interpreters the abort path is allowed to kill. Absolute paths only.
  # An empty list is valid config and a protection GAP — a breach will
  # write _watchdog_NO_TARGET rather than pretend the abort worked.
  Targets = @(
    'C:\path\to\venv\Scripts\python.exe'
  )

  # Hardware envelope — required, no silent default.
  # 31200 of 32607 MiB is the 32 GB / RTX 5090 training-correct bound
  # (~1.4 GB headroom = WDDM spill). Do NOT raise this to stop ComfyUI
  # trips; cap the consumer (--reserve-vram) instead.
  VramKillMiB = 31200
  RamKillPct  = 90
  TempKillC   = 87

  IntervalSec   = 2
  BreachSamples = 3
  StaleSec      = 15

  # WSL abort is opt-in. Empty pattern disables it (v1 public default).
  WslDistro      = 'Ubuntu'
  WslKillPattern = ''

  # Consent to kill guarded processes. Start-Watchdog also accepts -AllowKill.
  AllowKill = $false

  # External poller interval (scheduled task). Detects death; never restarts.
  PollIntervalSec = 30

  # WSL file-cache release (opt-in). On each poll, if the WSL VM (vmmemWSL) is large, the poller drops the
  # Linux page cache (`echo 1 > /proc/sys/vm/drop_caches`, as root in WslDistro). It never kills a process
  # and never wakes a stopped VM. Acts when vmmemWSL >= WslCacheHighGB, or Windows memory used >=
  # WslCacheWinHighPct with vmmemWSL >= WslCacheMinGB, and only if the Linux cache is >= WslCacheMinCacheGB.
  # Log: Root\_watchdog_wslcache.log (hourly heartbeat, each drop, ALERT if Windows stays >= WslCacheAlertPct).
  WslCacheRelease     = $false
  WslCacheHighGB      = 16
  WslCacheMinGB       = 8
  WslCacheWinHighPct  = 80
  WslCacheMinCacheGB  = 6
  WslCacheAlertPct    = 90
  WslCacheCooldownSec = 300
  WslCacheTimeoutSec  = 90
  WslCacheSettleSec   = 10
}
