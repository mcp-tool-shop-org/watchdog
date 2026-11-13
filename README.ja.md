<p align="center">
  <a href="README.md">English</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

# watchdog

NVIDIA GPU用のWindows VRAM/RAM/一時ファイル監視プログラム。2秒ごとにサンプリングします。3回連続して違反が発生した場合、指定されたインタープリターのみを強制終了し、違反時に何も強制終了されなかった場合はその旨を表示します。

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

ハートビートのチェックを手動で実装しないでください。`_watchdog`を使用してプロセスを照合しないでください。この2つの間違いが原因で、正常に動作している監視プログラムとそうでない監視プログラムの見分けがつかなくなります。

**v1はWindows専用**（PowerShell 7、nvidia-smi、WDDMプロセスメモリカウンター、オプションのWSL `pkill`）。Linux版は後日リリースされます。

## インストール

PowerShell 7.1以上をインストールします。クローンし、サンプル設定ファイルをコピーして編集し、起動します。

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

**デフォルトのルートと強制終了リストはありません。** 設定ファイルがない場合、モジュールは起動しません。検索順序：`-ConfigPath`、`$env:WATCHDOG_CONFIG`、`./watchdog.config.psd1`、`~/.watchdog/config.psd1`。

必須フィールド：`Root`、`Targets`、`VramKillMiB`、`RamKillPct`、`TempKillC`。相対パスは拒否されます。書き込みは`Root`以下に制限されます。

`VramKillMiB = 31200`は、32GBのカードに対するドキュメント化された上限値です（32607 MiBのWDDMの上限より約1.4GB少ない）。ComfyUIの異常終了を防ぐために、この値を大きくしないでください。代わりに、ComfyUI（`--reserve-vram`）に制限を設けてください。

## コマンド

| コマンド | 実行内容 |
|---|---|
| `watchdog status` | 生存確認。唯一正しいチェック方法です。 |
| `watchdog start -AllowKill` | センチネルを停止し、待機し、クリアし、デタッチドモードで起動し、ハートビートを確認します。 |
| `watchdog stop` | センチネルを停止し、待機します。プロセス照合は行いません。 |
| `watchdog poll` | ワンショット：ハートビートが古い場合、外部から`_watchdog_DEAD`を書き込みます。 |
| `watchdog help` | フラグと終了コード |
| `watchdog version` | `1.0.0` |

`status` / `poll`の終了コード：**0**（実行中）、**1**（ハートビートなし）、**2**（古い）。`start`は、**3**（VRAMがすでに上限を超えている）、**4**（前のループが停止しなかった）、**5**（起動後にハートビートがない）も使用します。

ステータス時に`-Hook`を送信すると、Claude Code SessionStart JSONが出力され、常に終了コード0で終了するため、監視プログラムが正常に動作していない場合でもセッションの開始を妨げることはありません。

## 強制終了するプロセス

`Path`が`Targets`に含まれる`python`というプロセスのみを強制終了し、オプションでWSL `pkill -f`パターン（空の場合は無効）を追加します。他のPythonプロセスは保護されます。一致するものがない違反が発生した場合、`_watchdog_NO_TARGET`が書き込まれます。これは**保護のギャップ**であり、成功ではありません。

同意：`-AllowKill`（または設定内の`AllowKill = $true`）。ポーラーは強制終了せず、自動再起動も行いません。自動再起動によって実行中のジョブが中断される可能性があります。

## 脅威モデル

- **影響を受けるもの：** `Root`（ハートビート、CSVファイル、強制終了/コンソール/クラッシュログ、センチネル）、プロセスリスト、GPUカウンター、オプションのローカルWSL pkill。
- **影響を受けないもの：** ソースツリー、チェックポイント、認証情報、ネットワーク。
- **権限：** 起動したユーザーは、設定されたインタープリターを強制終了できます。追加のサービスアカウントはありません。
- **テレメトリーは送信されません。** ログに機密情報は含まれません。
- **不可逆的なアクション：** 中止。詳細は[docs/compensators.md](docs/compensators.md)を参照してください。

## テスト

```powershell
pwsh -File .\verify.ps1
```

32個のユニットテスト（GPUは使用しません）。パーサーフィクスチャには、2026年6月12日にループを強制終了させた誤ったnvidia-smi出力が含まれています。ハードウェア中止テストはローカルで実行され、CIではグリーン化されません。

## 起源

これは、すでに5090上で実行されていた監視プログラムから抽出されたものです。抽出前のスクリプトは、SHA-256ピンとともに[`origin/`](origin/)に保存されています。日付付きのインシデント（解析クラッシュ、5週間の空白期間、保護されていないai-toolkit、153個の空のABORT、1つのサンプルによる強制終了）は、[docs/incidents.md](docs/incidents.md)に記載されています。

## ライセンス

MIT。詳細は[LICENSE](LICENSE)を参照してください。サポート対象：1.x。

[MCP Tool Shop](https://mcp-tool-shop.github.io/)によって作成されました。
