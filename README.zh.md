<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.md">English</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

# 看门狗

用于 NVIDIA GPU 的 Windows VRAM/RAM/临时文件看门狗。它每隔 2 秒进行一次采样。在连续出现 3 次违规后，它只会终止你列出的解释器进程——并且会在发生违规但没有进程被终止时告知用户。

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

不要手动编写心跳检测代码。不要根据 `_watchdog` 进行进程匹配。这两个错误会导致正常的看门狗和失效的看门狗表现完全相同。

**v1 版本仅适用于 Windows**（PowerShell 7、nvidia-smi、WDDM 进程内存计数器，可选 WSL `pkill`）。Linux 版本将在后续版本中提供。

## 安装

PowerShell 7.1+。克隆代码，复制示例配置文件，编辑它，然后启动：

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

或者导入模块：

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog` 将模块复制到你的 CurrentUser 模块路径中。

## 配置

**没有默认的根目录，也没有默认的终止进程列表。** 如果没有配置文件，该模块将拒绝启动。搜索顺序：`-ConfigPath`、`$env:WATCHDOG_CONFIG`、`./watchdog.config.psd1`、`~/.watchdog/config.psd1`。

必需字段：`Root`、`Targets`、`VramKillMiB`、`RamKillPct`、`TempKillC`。不允许使用相对路径。写入操作将在 `Root` 范围内进行。

`VramKillMiB = 31200` 是针对 32GB 显卡的限制值（低于 32607 MiB 的 WDDM 上限）。**不要**提高此值以阻止 ComfyUI 崩溃——而是对 ComfyUI (`--reserve-vram`) 进行限制。

## 命令

| 命令 | 作用 |
|---|---|
| `watchdog status` | Liveness（存活检测）。这是唯一正确的检查方法。 |
| `watchdog start -AllowKill` | Sentinel-stop（哨兵停止）、wait（等待）、clear（清除）、detached launch（分离启动）、verify heartbeat（验证心跳）。 |
| `watchdog stop` | STOP sentinel，然后等待。绝不要进行进程匹配。 |
| `watchdog poll` | 单次执行：如果心跳信号陈旧，则从外部写入 `_watchdog_DEAD`。 |
| `watchdog help` | 标志和退出代码 |
| `watchdog version` | `1.0.0` |

`status` / `poll` 退出代码：**0**（正在运行）、**1**（没有心跳）、**2**（心跳信号陈旧）。`start` 还使用 **3**（VRAM 已超过上限）、**4**（之前的循环未停止）、**5**（启动后没有心跳）。

在状态输出时，`-Hook` 会发出 Claude Code SessionStart JSON 消息，并且始终以退出代码 0 结束，因此失效的看门狗无法中断会话开始。

## 它将终止哪些进程

仅终止 `python` 个进程，这些进程的 `Path` 位于 `Targets` 中，此外还有一个可选的 WSL `pkill -f` 模式（为空时禁用）。其他 Python 进程将被保留。如果违规行为没有匹配到任何进程，则会写入 `_watchdog_NO_TARGET`——这是一种**保护漏洞**，而不是成功。

同意：`-AllowKill`（或配置文件中的 `AllowKill = $true`）。轮询器永远不会终止进程，也不会自动重启；自动重启可能会中断正在运行的任务。

## 威胁模型

- **涉及的文件：**位于 `Root` 下的 文件（心跳、CSV、终止/控制台/崩溃日志、哨兵）；进程列表；GPU 计数器；可选的本地 WSL pkill。
- **不涉及的文件：**你的源代码树、检查点、凭据、网络。
- **权限：**启动该程序的用户可以终止已配置的解释器进程。没有额外的服务帐户。
- **没有遥测数据**会离开机器。日志中不包含任何敏感信息。
- **不可逆操作：**ABORT（中止）。请参阅 [docs/compensators.md](docs/compensators.md)。

## 测试

```powershell
pwsh -File .\verify.ps1
```

32 个单元测试，无需 GPU。解析器固定程序包括导致 2026-06-12 日循环崩溃的格式错误的 nvidia-smi 输出。硬件中止测试保持本地状态，并且不在 CI 中进行绿色标记。

## 来源

这是一个从已经运行在 5090 上的看门狗中提取出来的程序。提取前的脚本已冻结在 [`origin/`](origin/) 下，并带有 SHA-256 哈希值。有关事件（解析崩溃、持续五周的漏洞、未受保护的 ai-toolkit、153 次空 ABORT 操作、一次性死亡）的信息请参见 [docs/incidents.md](docs/incidents.md)。

## 许可证

MIT。请参阅 [LICENSE](LICENSE)。支持版本：1.x。

由 [MCP Tool Shop](https://mcp-tool-shop.github.io/) 构建。
