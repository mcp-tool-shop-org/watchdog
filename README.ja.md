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

# watchdog

**Windowsにおける、長時間のGPUジョブに対するハードリミット。** watchdogは、NVIDIAカードのVRAMと温度、およびシステムRAMを2秒ごとにチェックします。リミットが連続して3回を超えた場合、許可されたPythonインタープリターを停止し、それ以外は何も行いません。

トレーニングの実行や大規模なレンダリングを開始し、放置すると、メモリリーク、過剰なバッチサイズ、またはGPUの過熱により、システムがフリーズすることがあります。watchdogは、常に監視し続ける小さなプロセスです。設定したリミットを強制し、監視した内容を記録し、保護できなかった場合に明確に通知します。

## 得られるもの

- **ユーザーが選択するリミット。** VRAMはMiBで、RAMはパーセントで、GPU温度は℃で指定します。隠れたデフォルト値はありません。
- **ターゲットを絞った停止。** リストに登録されたインタープリターのパス（オプションでWSLプロセスパターン）のみを停止できます。それ以外のPythonプロセスはそのままです。
- **誤った安心感を与えない。** リストに登録されたプロセスに一致しない違反が発生した場合、保護のギャップとして記録され、VRAMを保持しているプロセスが名前で示されます。
- **watchdogのためのwatchdog。** オプションのスケジュールされたタスクが、1分間に1回ハートビートをチェックし、watchdogが停止した場合、外部からwatchdogが停止したと判断します。watchdogは、それ自体で何も再起動しません。
- **明確な稼働状況の確認。** `watchdog status`は、0（実行中）、1（実行されていない）、2（致命的なエラーで停止）を返します。
- **すべての実行の記録。** サンプルのCSV、キルログ、コンソールトランスクリプト、クラッシュログを、ユーザーが選択した1つのフォルダーに保存します。
- **オプションのWSLメモリ解放。** WSLのファイルキャッシュがWindowsのメモリを圧迫する場合、ポーラーがそのキャッシュを解放できます。プロセスは停止せず、停止したディストリビューションも起動しません。

## クイックスタート

要件：Windows、PowerShell 7.1以降、および`PATH`で`nvidia-smi`が有効になっているNVIDIAドライバー。

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill`はあなたの同意です。watchdogは、これがない場合、または構成に`AllowKill = $true`がない場合は起動しません。モジュールとしてインストールし、外部チェックを追加するには、

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## 動作原理

1. **サンプル。** `IntervalSec`（デフォルトでは2秒ごと）に、GPUの温度、電力、およびVRAMを`nvidia-smi`から、システムRAMをWindowsから読み取ります。
2. **特定のパターンを待つ。急激な変化ではない。** 何らかの処理が行われる前に、ある閾値が連続して`BreachSamples`回（デフォルトでは3回）超えなければなりません。その過程で警告が記録されます。
3. **リストに記載されたものだけを停止する。** 継続的に閾値を超えた場合、パスが`Targets`にある`python`のプロセスを停止し、オプションのWSL `pkill`パターンを実行します。停止したプロセス、または何も停止しなかったことを記録します。
4. **正常に動作していることを証明する。** ループは、各サンプルのたびにハートビートファイルを書き換えます。`watchdog status`とスケジュールされたポーラーが、そのハートビートから正常に動作しているかどうかを判断するため、動作が停止した監視プログラムは、正常に動作しているように見せることはできません。

## コマンド

| コマンド | 実行内容 |
|---|---|
| `watchdog status` | 稼働状況の確認。終了コードは、0（実行中）、1（実行されていない）、2（致命的なエラーで停止）です。 |
| `watchdog start -AllowKill` | 古いループをクリーンに停止し、バックグラウンドで新しいループを開始し、ハートビートを待ちます。 |
| `watchdog stop` | センチネルファイルを通じてループを停止するように要求し、完了するまで待ちます。 |
| `watchdog poll` | スケジュールされたタスクによって実行される、外部チェックを1回実行します。 |
| `watchdog install` / `uninstall` | モジュールをコピーまたは削除します。`install -Poll`は、スケジュールされたチェックも登録します。 |
| `watchdog help` / `version` | フラグ、終了コード、およびバージョンを表示します。 |

`start`は、VRAMがすでに設定した上限を超えている場合、終了コード3で拒否します（`-Force`を使用する場合は、本当にそうしたいことを意味します）。`status -Hook`は、Claude Code SessionStartメッセージを出力し、常に終了コード0を返します。これにより、停止したwatchdogが、セッションを中断することなく報告されます。完全なリファレンス：[handbook → Reference](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/)。

## 設定

watchdogは、設定ファイルがないと起動しません。最初に`-ConfigPath`、次に`$env:WATCHDOG_CONFIG`、次に`./watchdog.config.psd1`、最後に`~/.watchdog/config.psd1`を検索します。

| 必須 | 意味 |
|---|---|
| `Root` | ハートビート、ログ、センチネルファイルの絶対パス。watchdogは、他の場所に書き込みません。 |
| `Targets` | 停止する可能性のある、絶対パスで指定されたインタープリターのパス。 |
| `VramKillMiB` | VRAMの上限をMiBで指定します。32GBのカードの場合、`31200`は、約1.4GBのヘッドルームを残します。 |
| `RamKillPct` | システムRAMの上限をパーセントで指定します。 |
| `TempKillC` | GPU温度の上限を℃で指定します。 |

通常の使用時にVRAMの上限に達した場合、上限を引き上げるのではなく、ジョブを制限します（ComfyUI、`--reserve-vram`）。その他の設定（WSLキャッシュの解放を含む）は、[handbook → Configuration](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/)にあります。

## 安全性

- **最初に同意を得る。** `-AllowKill`または`AllowKill = $true`がない限り、何も停止されません。
- **アクセスするファイル：** `Root`内のファイル、プロセスリスト、GPUカウンター。また、有効にした場合は、WSL `pkill`パターンとWSLページキャッシュの解放。
- **アクセスしないファイル：** ソースツリー、チェックポイント、認証情報、ネットワーク。テレメトリーは、マシンから送信されません。
- **唯一不可逆的な操作は、停止することです。** 停止されたジョブは、保存されていないものを失います。失われるものと、回復する方法については、[docs/compensators.md](docs/compensators.md)を参照してください。

脆弱性を報告するには、[SECURITY.md](SECURITY.md)を参照してください。

## プラットフォーム

バージョン1はWindows専用です。PowerShell 7、`nvidia-smi`、Windows GPUプロセスメモリカウンター、およびオプションでWSLに依存します。Linuxのサポートは、今後のバージョンで計画されています。

## 開発

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

テスト内のすべての停止、起動、およびスケジュールされたタスクの呼び出しはモックされているため、テストを実行しても実際のプロセスには影響しません。事前抽出スクリプトは、[`origin/`](origin/)に保存され、ハッシュで固定されており、設計に影響を与えたインシデントは、[docs/incidents.md](docs/incidents.md)にあります。

## ライセンス

MIT。 [LICENSE](LICENSE)を参照してください。

[MCP Tool Shop](https://mcp-tool-shop.github.io/)によって作成されました。
