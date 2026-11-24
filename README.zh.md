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

用于 NVIDIA GPU 的 Windows VRAM/RAM/临时文件看门狗。它每 2 秒采样一次。连续出现 3 次违规后，它只会终止你列出的解释器——并且在出现违规但没有进程被终止时，它会说明这一点。

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

不要手动编写心跳检测。不要对 `_watchdog` 进行进程匹配。这两个错误会导致一个已停止运行的看门狗和一个正常运行的看门狗看起来完全相同。

**v1 仅适用于 Windows**（PowerShell 7、nvidia-smi、WDDM 进程内存计数器、可选的 WSL `pkill` 和 WSL 文件缓存释放）。Linux 版本将在后续发布。

## 安装

PowerShell 7.1+。克隆，复制示例配置文件，编辑它，然后启动：

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

**没有默认的根目录，也没有默认的终止列表。** 如果没有配置文件，模块将拒绝启动。搜索顺序：`-ConfigPath`、`$env:WATCHDOG_CONFIG`、`./watchdog.config.psd1`、`~/.watchdog/config.psd1`。

必需字段：`Root`、`Targets`、`VramKillMiB`、`RamKillPct`、`TempKillC`。拒绝使用相对路径。写入操作将限制在 `Root` 范围内。

`VramKillMiB = 31200` 是 32GB 显卡的文档化限制（低于 32607 MiB WDDM 限制约 1.4GB）。不要提高此限制以阻止 ComfyUI 触发——而是限制 ComfyUI（`--reserve-vram`）。

### WSL 文件缓存释放（默认关闭，需显式启用）

启用 `WslCacheRelease = $true` 后，每次轮询都会从 Windows 侧检查 WSL 虚拟机的内存（绝不会唤醒已停止的虚拟机）。当 `vmmemWSL` 较大，或 Windows 内存承压且 `vmmemWSL` 为中等大小时，轮询器会在 `WslDistro` 中丢弃 Linux 页面缓存（以 root 身份运行 `echo 1 > /proc/sys/vm/drop_caches`，带超时和冷却时间）。WSL 自身的 `autoMemoryReclaim` 仅在虚拟机空闲时触发，而运行中的容器引擎会使其保持繁忙，因此拉取大型镜像可能会占用数十 GB 缓存而不归还给 Windows。

它绝不会终止任何进程，也绝不会启动已停止的发行版：当另一个发行版保持虚拟机运行，而`WslDistro`停止时，它会跳过缓存释放并记录这次跳过。它的日志文件`Root\_watchdog_wslcache.log`会记录每小时的心跳信息；每次缓存释放及其前后的内存；每一段连续跳过记录一行；如果释放后 Windows 仍然高于`WslCacheAlertPct`，还会记录一个`ALERT`，其中包含占用资源最多的进程的名称。阈值设置请参考示例配置文件。

## 命令

| 命令 | 作用 |
|---|---|
| `watchdog status` | 活动性。这是唯一正确的检查。 |
| `watchdog start -AllowKill` | 哨兵停止、等待、清除、分离启动、验证心跳 |
| `watchdog stop` | 停止哨兵，等待。不要进行进程匹配。 |
| `watchdog poll` | 单次执行：如果心跳已过期，则从外部写入 `_watchdog_DEAD` |
| `watchdog help` | 标志和退出代码 |
| `watchdog version` | `1.1.2` |

`status` / `poll` 退出代码：**0** 正在运行 · **1** 没有心跳 · **2** 已过期。`start` 还会使用 **3**（VRAM 已经超过限制）、**4**（旧循环未停止）、**5**（启动后没有心跳）。

`-Hook` 在状态时会发出 Claude Code SessionStart JSON，并且始终退出代码为 0，因此一个已停止运行的看门狗不会破坏会话启动。

## 它会终止哪些进程

仅终止 `python` 进程，这些进程的 `Path` 位于 `Targets` 中，以及可选的 WSL `pkill -f` 模式（为空 = 禁用）。其他 Python 进程将被保留。如果违规行为没有匹配到任何进程，则会写入 `_watchdog_NO_TARGET`——这是一种**保护漏洞**，而不是成功。

同意：`-AllowKill`（或配置文件中的 `AllowKill = $true`）。轮询器永远不会终止进程，也不会自动重新启动；自动重新启动可能会中止正在运行的任务。

## 威胁模型

- **已访问：** `Root` 下的文件（心跳、CSV、终止/控制台/崩溃日志、哨兵）；进程列表；GPU 计数器；可选的本地 WSL pkill；可选的 WSL 页面缓存丢弃（默认关闭，需显式启用；绝不会终止进程）。
- **未访问：** 你的源代码树、检查点、凭据、网络。
- **权限：** 启动它的人可以终止配置的解释器。没有额外的服务帐户。
- **没有遥测数据** 会离开机器。日志中没有秘密信息。
- **不可逆操作：** ABORT。请参阅 [docs/compensators.md](docs/compensators.md)。

## 测试

```powershell
pwsh -File .\verify.ps1
```

166 个单元测试，未使用 GPU。解析器测试用例包括导致 2026-06-12 日循环中断的格式错误的 nvidia-smi 输出。硬件中止测试保持本地状态，不会在 CI 中进行绿色测试。

`pwsh -File .\verify.ps1 -Coverage` 添加了对 `src/Watchdog` 的行覆盖率测试，并且当覆盖率低于 90% 时，测试会失败。持续集成（CI）系统会以这种方式运行测试，并将报告上传到 Codecov，Codecov 要求整个模块以及每次更改的覆盖率都至少达到 90%。

## 来源

这是一个已经在一个 5090 上运行的看门狗的提取版本。提取前的脚本已冻结在 [`origin/`](origin/) 中，并带有 SHA-256 固定版本。已记录的事件（解析崩溃、五周漏洞、未受保护的 ai-toolkit、153 个空 ABORT、单次样本死亡）位于 [docs/incidents.md](docs/incidents.md) 中。

## 许可证

MIT。请参阅 [LICENSE](LICENSE)。支持：1.x。

由 [MCP Tool Shop](https://mcp-tool-shop.github.io/) 构建。
