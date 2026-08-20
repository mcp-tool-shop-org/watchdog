import type { SiteConfig } from '@mcptoolshop/site-theme';

export const config: SiteConfig = {
  title: 'watchdog',
  description: 'Windows VRAM/RAM/temp watchdog for NVIDIA GPUs. Kills guarded interpreters on a sustained breach.',
  logoBadge: 'WD',
  brandName: 'watchdog',
  repoUrl: 'https://github.com/mcp-tool-shop-org/watchdog',
  footerText: 'MIT Licensed — built by <a href="https://mcp-tool-shop.github.io/" style="color:var(--color-muted);text-decoration:underline">MCP Tool Shop</a>',

  hero: {
    badge: 'PowerShell 7 · Windows',
    headline: 'The GPU is unprotected',
    headlineAccent: 'unless you ask.',
    description: 'Sample VRAM, RAM, and temp every 2 seconds. After 3 consecutive breaches, kill only the interpreters you listed. A dead watchdog and a healthy one look identical unless you ask — this asks.',
    primaryCta: { href: '#quickstart', label: 'Get started' },
    secondaryCta: { href: 'handbook/', label: 'Read the Handbook' },
    previews: [
      {
        label: 'Status',
        code: 'pwsh -File .\\watchdog.ps1 status\n# 0 running · 1 no heartbeat · 2 stale (died hard)',
      },
      {
        label: 'Start',
        code: 'pwsh -File .\\watchdog.ps1 start -AllowKill\n# sentinel-stop, wait, launch, verify heartbeat',
      },
      {
        label: 'Config',
        code: '# No default Root. No default kill list.\n# Copy src/Watchdog/config/watchdog.example.psd1\n# to ~/.watchdog/config.psd1 and edit it.',
      },
    ],
  },

  sections: [
    {
      kind: 'features',
      id: 'why',
      title: 'Why it exists',
      subtitle: 'The tooling was already correct. Operators still hand-rolled a worse check.',
      features: [
        {
          title: 'Something polls',
          desc: 'Liveness is not pull-once at session start. A scheduled poller writes _watchdog_DEAD from the outside when the heartbeat is stale. It detects. It never restarts.',
        },
        {
          title: 'The right check is named',
          desc: 'watchdog status. Exit 0/1/2. Do not process-match on _watchdog. Do not invent a heartbeat-age check.',
        },
        {
          title: 'The next hard death leaves a body',
          desc: 'CSV is appended, not truncated. Timestamps are UTC. The child transcripts to _watchdog_console.log. Unhandled exceptions land in _watchdog_crash.log.',
        },
      ],
    },
    {
      kind: 'code-cards',
      id: 'quickstart',
      title: 'Get started',
      cards: [
        {
          title: 'Config (required)',
          code: 'mkdir $HOME\\.watchdog\ncopy src\\Watchdog\\config\\watchdog.example.psd1 $HOME\\.watchdog\\config.psd1\n# Root, Targets, VramKillMiB, RamKillPct, TempKillC — all required\n# 31200 is the 32 GB card example. Do not raise it to silence ComfyUI.',
        },
        {
          title: 'Start with consent',
          code: 'pwsh -File .\\watchdog.ps1 start -AllowKill\npwsh -File .\\watchdog.ps1 status',
        },
        {
          title: 'Verify (no GPU)',
          code: 'pwsh -File .\\verify.ps1\n# 32 unit tests. The abort test stays local.',
        },
      ],
    },
    {
      kind: 'data-table',
      id: 'contract',
      title: 'Liveness contract',
      subtitle: 'Heartbeat age is the signal. A frozen CSV is not.',
      columns: ['Sentinel', 'Meaning'],
      rows: [
        ['_watchdog_HEARTBEAT', 'Rewritten every sample. Age > ~3x interval = dead or hard-killed.'],
        ['_watchdog_DEAD', 'Loop exit other than STOP, or the poller when the heartbeat is stale.'],
        ['_watchdog_NO_TARGET', 'ABORT killed nothing. Protection gap, not success.'],
        ['_watchdog_TRIPPED', 'Last abort reasons and acts.'],
        ['_watchdog_STOP', 'Clean stop request. Never process-match.'],
      ],
    },
  ],
};
