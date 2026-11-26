<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.md">English</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://codecov.io/gh/mcp-tool-shop-org/watchdog"><img src="https://codecov.io/gh/mcp-tool-shop-org/watchdog/graph/badge.svg" alt="Coverage"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
  <a href="https://mcp-tool-shop-org.github.io/watchdog/"><img src="https://img.shields.io/badge/Landing_Page-live-blue" alt="Landing Page"></a>
</p>

# 看门狗

**Windows 系统中，对长时间运行的 GPU 任务设置硬性上限。** 看门狗会每隔 2 秒检查您的 NVIDIA 显卡的 VRAM 和温度，以及系统 RAM。当某个限制持续超出设定值时，它会停止您允许它停止的 Python 解释器，仅此而已。

您启动一个训练任务或大型渲染，然后离开，这时，由于内存泄漏、过大的批处理或显卡过热，系统可能会崩溃。看门狗是一个始终保持运行的小进程：它会强制执行您设置的限制，记录它所看到的内容，并明确地告诉您，当它无法保护您的系统时。

## 您将获得什么

- **您选择的限制。** VRAM（以 MiB 为单位），RAM（以百分比为单位），GPU 温度（以 °C 为单位）。没有隐藏的默认值。
- **有针对性的停止。** 只有您列出的解释器路径（以及可选的 WSL 进程模式）才会被停止。
机器上的所有其他 Python 进程都将保持不变。
- **不会提供虚假的安慰。** 如果超出限制，但没有匹配到您列出的任何进程，则会将其记录为保护漏洞，并显示占用 VRAM 的进程的名称。
- **一个用于监控看门狗的看门狗。** 一个可选的计划任务会每分钟检查一次心跳，如果看门狗停止运行，则从外部将其标记为已停止。它绝不会自行重新启动任何进程。
- **清晰的运行状态指示。** `watchdog status` 退出代码：0（正在运行），1（未运行）或 2（严重故障）。
- **每次运行的记录。** CSV 格式的样本数据、停止日志、控制台转录和崩溃日志，所有这些都保存在您选择的同一个文件夹中。
- **可选的 WSL 内存释放。** 如果 WSL 的文件缓存占用 Windows 内存过多，则轮询器可以释放该缓存。
它绝不会停止任何进程，也不会启动任何已停止的发行版。

## 快速入门

要求：Windows，PowerShell 7.1 或更高版本，以及带有 `nvidia-smi` 的 NVIDIA 驱动程序，该驱动程序可在 `PATH` 上使用。

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill` 是您的同意：如果没有它，或者配置中没有 `AllowKill = $true`，看门狗将不会启动。
要将其安装为模块并添加外部检查：

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## 工作原理

1. **采样。** 每隔 `IntervalSec` 秒（默认情况下为 2 秒），它会从 `nvidia-smi` 读取 GPU 温度、功耗和 VRAM，并从 Windows 读取系统 RAM。
2. **等待模式出现，而不是峰值。** 必须连续 `BreachSamples` 次（默认情况下为 3 次）超出限制，才会发生任何操作。在过程中会记录警告信息。
3. **仅停止您列出的进程。** 在持续超出限制的情况下，它会停止路径位于 `Targets` 中的 `python` 个进程，并运行可选的 WSL `pkill` 模式。它会记录它停止的内容，或者它没有停止任何内容。
4. **证明它正在运行。** 循环会在每次采样时重写一个心跳文件。`watchdog status` 和计划任务轮询器会根据该心跳来判断运行状态，因此，一个已停止的看门狗永远不会显示为健康的。

## 命令

| 命令 | 它执行的操作 |
|---|---|
| `watchdog status` | 运行状态检查。退出代码：0（正在运行），1（未运行），2（严重故障）。 |
| `watchdog start -AllowKill` | 干净地停止任何旧的循环，在后台启动一个新的循环，并等待其心跳。 |
| `watchdog stop` | 通过一个哨兵文件请求循环停止，并等待其停止。 |
| `watchdog poll` | 由计划任务运行的外部检查。 |
| `watchdog install` / `uninstall` | 复制或删除模块。`install -Poll` 还会注册计划检查。 |
| `watchdog help` / `version` | 标志、退出代码和版本。 |

`start` 如果 VRAM 已经超过您的上限，则会拒绝并返回退出代码 3（仅当您确实希望这样做时才使用 `-Force`）。`status -Hook` 会打印一条 Claude Code SessionStart 消息，并且始终返回退出代码 0，因此，即使看门狗停止运行，也不会中断会话。完整参考：[handbook → Reference](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/)。

## 配置

如果没有配置文件，看门狗将不会启动。它会依次查找 `-ConfigPath`、`$env:WATCHDOG_CONFIG`、`./watchdog.config.psd1` 和 `~/.watchdog/config.psd1`。

| 必需 | 含义 |
|---|---|
| `Root` | 用于存储心跳文件、日志和哨兵文件的绝对文件夹。看门狗不会将任何内容写入其他位置。 |
| `Targets` | 它可以停止的绝对解释器路径。 |
| `VramKillMiB` | VRAM 上限（以 MiB 为单位）。对于 32GB 的显卡，`31200` 留出大约 1.4GB 的可用空间。 |
| `RamKillPct` | 系统 RAM 上限（以百分比为单位）。 |
| `TempKillC` | GPU 温度上限（以 °C 为单位）。 |

如果某个作业在正常使用中触发了 VRAM 上限，请限制该作业（对于 ComfyUI，`--reserve-vram`），而不是提高上限。所有其他设置，包括 WSL 缓存释放，都可以在 [handbook → Configuration](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/) 中找到。

## 安全

- **首先需要您的同意。** 没有 `-AllowKill` 或 `AllowKill = $true`，任何内容都不会被停止。
- **受影响的文件：** `Root` 下的文件、进程列表、GPU 计数器；并且，如果您启用了它们，还会影响 WSL `pkill` 模式和 WSL 页面缓存释放。
- **不受影响的文件：** 您的源代码树、检查点、凭据和网络。没有遥测数据会离开该机器。
- **唯一不可逆的操作是停止。** 停止的作业会丢失所有未保存的内容。丢失的内容以及如何恢复，请参见 [docs/compensators.md](docs/compensators.md)。

请参阅 [SECURITY.md](SECURITY.md) 以报告漏洞。

## 平台

版本 1 仅适用于 Windows：它依赖于 PowerShell 7、`nvidia-smi`、Windows GPU 进程内存计数器，以及可选的 WSL。Linux 支持计划在后续版本中提供。

## 开发

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

测试中的每个停止、启动和计划任务调用都进行了模拟，因此运行它们不会影响真实的进程。预提取脚本保存在 [`origin/`](origin/) 中，并且已进行哈希固定，而影响设计的事件则在 [docs/incidents.md](docs/incidents.md) 中。

## 许可证

MIT。请参阅 [LICENSE](LICENSE)。

由 [MCP Tool Shop](https://mcp-tool-shop.github.io/) 构建。
