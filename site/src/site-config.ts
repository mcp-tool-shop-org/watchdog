import type { SiteConfig } from '@mcptoolshop/site-theme';

export const config: SiteConfig = {
  title: 'watchdog',
  description: 'A hard ceiling for long GPU jobs on Windows: VRAM, RAM and temperature limits that stop only the interpreters you allow.',
  logoBadge: 'WD',
  brandName: 'watchdog',
  repoUrl: 'https://github.com/mcp-tool-shop-org/watchdog',
  footerText: 'MIT Licensed — built by <a href="https://mcp-tool-shop.github.io/" style="color:var(--color-muted);text-decoration:underline">MCP Tool Shop</a>',

  hero: {
    badge: 'Windows · PowerShell 7 · NVIDIA',
    headline: 'Walk away from a long GPU job.',
    headlineAccent: 'watchdog stays awake.',
    description: 'It checks VRAM, RAM and GPU temperature every 2 seconds. When a limit you set stays crossed for three checks, it stops only the interpreters you allowed, records what it saw, and tells you plainly when it could not protect you.',
    primaryCta: { href: '#quickstart', label: 'Get started' },
    secondaryCta: { href: 'handbook/', label: 'Read the Handbook' },
    previews: [
      {
        label: 'Start',
        code: 'watchdog start -AllowKill',
      },
      {
        label: 'Status',
        code: 'watchdog status   → 0 running · 1 not running · 2 died hard',
      },
      {
        label: 'Limits',
        code: 'VramKillMiB = 31200 · RamKillPct = 90 · TempKillC = 87',
      },
    ],
  },

  sections: [
    {
      kind: 'features',
      id: 'why',
      title: 'What you get',
      subtitle: 'A small process with one job: keep a runaway GPU job from taking the machine down with it.',
      features: [
        {
          title: 'Limits you choose',
          desc: 'VRAM in MiB, RAM in percent, GPU temperature in °C. No hidden defaults: watchdog will not start until you set them.',
        },
        {
          title: 'Targeted stops',
          desc: 'Only the interpreter paths you list, plus an optional WSL pattern, can be stopped. Every other Python process is left alone.',
        },
        {
          title: 'Patterns, not spikes',
          desc: 'A limit has to be crossed three checks in a row before anything happens, with warnings logged on the way.',
        },
        {
          title: 'Honest when it cannot help',
          desc: 'A breach that matched none of your processes is recorded as a protection gap, with the processes holding the VRAM named.',
        },
        {
          title: 'A watchdog for the watchdog',
          desc: 'An optional scheduled task checks the heartbeat once a minute and marks the watchdog dead from outside. It never restarts anything on its own.',
        },
        {
          title: 'WSL memory, given back',
          desc: 'Opt-in: when WSL file cache crowds Windows memory, the poller drops it. It never stops a process and never starts a stopped distro.',
        },
      ],
    },
    {
      kind: 'code-cards',
      id: 'quickstart',
      title: 'Get started',
      cards: [
        {
          title: '1. Write a config',
          code: 'mkdir $HOME\\.watchdog\ncopy src\\Watchdog\\config\\watchdog.example.psd1 $HOME\\.watchdog\\config.psd1\n# set Root, Targets, VramKillMiB, RamKillPct, TempKillC',
        },
        {
          title: '2. Start with consent',
          code: 'pwsh -File .\\watchdog.ps1 start -AllowKill\npwsh -File .\\watchdog.ps1 status   # exit 0 = protected',
        },
        {
          title: '3. Add the outside check',
          code: 'Import-Module .\\src\\Watchdog\\Watchdog.psd1\nRegister-WatchdogPoll\n# detects a dead watchdog; never restarts it',
        },
      ],
    },
    {
      kind: 'data-table',
      id: 'contract',
      title: 'What the files under Root tell you',
      subtitle: 'Everything watchdog knows is in one folder you choose.',
      columns: ['File', 'Meaning'],
      rows: [
        ['_watchdog_HEARTBEAT', 'Rewritten every check. Its age is how status and the poller judge liveness.'],
        ['_watchdog_DEAD', 'The loop exited for a reason other than a clean stop, or the poller found the heartbeat stale.'],
        ['_watchdog_NO_TARGET', 'A breach stopped nothing: a protection gap. Add the holder to Targets.'],
        ['_watchdog_TRIPPED', 'Why the last stop fired, and what it did.'],
        ['_watchdog_log.csv', 'Every sample: temperature, power, VRAM, RAM and state, appended across restarts.'],
      ],
    },
  ],
};
