<p align="center">
  <a href="README.md">English</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

# 監視プログラム

NVIDIA GPU用のWindows VRAM / RAM / 一時ファイル監視プログラム。2秒ごとにサンプリングします。3回連続して違反が発生した場合、指定されたインタープリターのみを強制終了します。また、違反が発生しても何も強制終了されない場合は、その旨を通知します。

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

手動でハートビートのチェックを行う処理を実装しないでください。`_watchdog`を使用してプロセスを照合しないでください。これらの2つの間違いが原因で、正常に動作している監視プログラムと、動作していない監視プログラムが区別できなくなります。

**v1はWindows専用です**（PowerShell 7、nvidia-smi、WDDMプロセスメモリカウンター、オプションのWSL `pkill`およびWSLファイルキャッシュの解放）。Linux版は後日リリースされます。

## インストール

PowerShell 7.1以上。クローンし、サンプル設定ファイルをコピーして編集し、起動します。

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

または、モジュールをインポートします。

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog`は、モジュールをCurrentUserモジュールパスにコピーします。

## 設定

**デフォルトのルートとデフォルトの強制終了リストはありません。**設定ファイルなしでモジュールを起動することはできません。検索順序：`-ConfigPath`、`$env:WATCHDOG_CONFIG`、`./watchdog.config.psd1`、`~/.watchdog/config.psd1`。

必須フィールド：`Root`、`Targets`、`VramKillMiB`、`RamKillPct`、`TempKillC`。相対パスは許可されません。書き込みは`Root`以下に制限されます。

`VramKillMiB = 31200`は、32GBのカードに対するドキュメントに記載されている上限値です（32607 MiB WDDMの上限値より約1.4GB少ない）。ComfyUIのトリガーを停止するために、この値を上げないでください。代わりに、ComfyUI（`--reserve-vram`）を制限してください。

### WSLファイルキャッシュの解放（オプトイン）

`WslCacheRelease = $true`を使用すると、各ポーリング時にWSL VMのメモリをWindows側からチェックします（停止中のVMを決して起動しません）。`vmmemWSL`が大きい場合、またはWindowsのメモリが逼迫しており`vmmemWSL`が中程度のサイズの場合、ポーラーは`WslDistro`内のLinuxページキャッシュを破棄します（root権限で`echo 1 > /proc/sys/vm/drop_caches`を実行、タイムアウトとクールダウンあり）。WSL自身の`autoMemoryReclaim`はVMがアイドル状態の場合にのみ作動し、実行中のコンテナエンジンがVMを稼働状態に保つため、大きなイメージのプルによって数十GBのキャッシュがWindows側のメモリを圧迫したまま残ることがあります。

このツールはプロセスを決して強制終了せず、停止したディストリビューションを決して起動しません。別のディストリビューションが、`WslDistro`が停止している間に仮想マシンを稼働させている場合、このツールはキャッシュの解放をスキップし、その旨をログに記録します。ログファイル`Root\_watchdog_wslcache.log`には、1時間ごとのハートビート、各キャッシュ解放の前後のメモリ使用量、一連のスキップにつき1行、そして解放の後もWindowsが依然として`WslCacheAlertPct`を超えている場合に上位のプロセス名を示す`ALERT`が記録されます。閾値は、サンプル設定ファイルに記載されています。

## コマンド

| コマンド | 実行内容 |
|---|---|
| `watchdog status` | 生存確認。唯一正しいチェックです。 |
| `watchdog start -AllowKill` | センチネルを停止し、待機し、クリアし、デタッチドモードで起動し、ハートビートを検証します。 |
| `watchdog stop` | センチネルを停止し、待機します。プロセスを照合することは行いません。 |
| `watchdog poll` | ワンショット：ハートビートが古い場合、外部から`_watchdog_DEAD`を書き込みます。 |
| `watchdog help` | フラグと終了コード |
| `watchdog version` | `1.1.2` |

`status`/`poll`の終了コード：**0**（正常終了）、**1**（ハートビートが途絶）、**2**（タイムアウト）。`start`では、さらに**3**（VRAMの使用量が上限を超えた）、**4**（古いループが停止しなかった）、**5**（起動後にハートビートが途絶）も使用されます。

ステータスに関する`-Hook`は、Claude Code SessionStart JSONを出力し、常に0で終了するため、動作していない監視プログラムがセッションの開始を妨げることはありません。

## 強制終了するプロセス

`Targets`に含まれる`Path`を持つ`python`プロセスのみを強制終了します。さらに、オプションでWSL `pkill -f`パターン（空の場合は無効）も使用します。他のPythonプロセスは強制終了されません。どのプロセスにも一致しない違反が発生した場合、`_watchdog_NO_TARGET`が書き込まれます。これは、保護の**ギャップ**であり、成功ではありません。

同意：`-AllowKill`（または設定の`AllowKill = $true`）。ポーラーはプロセスを強制終了せず、自動的に再起動も行いません。自動再起動は、実行中のジョブを中断する可能性があります。

## 脅威モデル

- **アクセス対象：**`Root`配下のファイル（ハートビート、CSV、強制終了/コンソール/クラッシュログ、センチネル）、プロセスリスト、GPUカウンター、オプションのローカルWSL pkill、オプションのWSLページキャッシュ破棄（オプトイン、プロセスは決して強制終了しません）。
- **アクセス対象外：**ソースツリー、チェックポイント、認証情報、ネットワーク。
- **権限：**モジュールを起動するユーザーは、設定されたインタープリターを強制終了できます。追加のサービスアカウントはありません。
- **テレメトリは送信されません。**ログに機密情報は含まれません。
- **不可逆的な操作：**ABORT。詳細については、[docs/compensators.md](docs/compensators.md)を参照してください。

## テスト

```powershell
pwsh -File .\verify.ps1
```

182個のユニットテスト、GPUは使用しません。パーサーのテストデータには、2026年6月12日にループを停止させた、不正なnvidia-smiの出力が含まれています。ハードウェア異常テストはローカルで実行され、CI環境ではグリーン化されません。

`pwsh -File .\verify.ps1 -Coverage`により、`src/Watchdog`の行カバレッジが追加され、90%未満の場合にはテストが失敗します。CI（継続的インテグレーション）システムでは、このテストが実行され、その結果がCodecovにアップロードされます。Codecovでは、モジュール全体および各変更に対して、少なくとも90%のカバレッジが必要です。

## 起源

これは、すでに5090で実行されていた監視プログラムから抽出されたものです。抽出前のスクリプトは、[`origin/`](origin/)に固定され、SHA-256ピンが設定されています。日付付きのインシデント（解析クラッシュ、5週間の空白、保護されていないai-toolkit、153個の空のABORT、1サンプルの異常終了）は、[docs/incidents.md](docs/incidents.md)に記載されています。

## ライセンス

MIT。詳細については、[LICENSE](LICENSE)を参照してください。サポート対象：1.x。

[MCP Tool Shop](https://mcp-tool-shop.github.io/)によって作成されました。
