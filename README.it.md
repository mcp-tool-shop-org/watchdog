<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.md">English</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
  <a href="https://mcp-tool-shop-org.github.io/watchdog/"><img src="https://img.shields.io/badge/Landing_Page-live-blue" alt="Landing Page"></a>
</p>

# watchdog

Watchdog per VRAM/RAM/temperatura di Windows per GPU NVIDIA. Esegue un controllo ogni 2 secondi. Dopo 3 violazioni consecutive, termina **solo** gli interpreti elencati e lo comunica quando una violazione non causa l'interruzione di alcun processo.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

Non implementare manualmente un controllo dell'attività (heartbeat). Non effettuare il confronto dei processi in base a `_watchdog`. Questi due errori sono ciò che fa sembrare identici un watchdog funzionante e uno non funzionante.

**La versione 1 è disponibile solo per Windows** (PowerShell 7, nvidia-smi, contatori di memoria dei processi WDDM, WSL `pkill` opzionale). Linux sarà disponibile in una versione successiva.

## Installazione

PowerShell 7.1 o superiore. Clona, copia il file di configurazione di esempio, modificalo e avvia:

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

Oppure importa il modulo:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog` copia il modulo nella directory dei moduli CurrentUser.

## Configurazione

**Non sono presenti impostazioni predefinite per la directory principale né per l'elenco di processi da terminare.** Il modulo si rifiuta di avviarsi senza un file di configurazione. Ordine di ricerca: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Campi obbligatori: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. I percorsi relativi non sono accettati. Le scritture rimangono al di sotto di `Root`.

`VramKillMiB = 31200` è il limite documentato per una scheda da 32 GB (~1,4 GB inferiore al limite WDDM di 32607 MiB). **Non** aumentarlo per evitare che ComfyUI si blocchi; limita invece ComfyUI (`--reserve-vram`).

## Comandi

| Comando | Funzione |
|---|---|
| `watchdog status` | Controllo dell'attività. L'unico controllo corretto. |
| `watchdog start -AllowKill` | Arresto del sentinel, attesa, cancellazione, avvio in background, verifica dell'attività. |
| `watchdog stop` | ARRESTO del sentinel, attesa. Non effettuare mai il confronto dei processi. |
| `watchdog poll` | Esecuzione singola: se l'attività è scaduta, scrivi `_watchdog_DEAD` dall'esterno. |
| `watchdog help` | Flag e codici di uscita |
| `watchdog version` | `1.0.0` |

Codici di uscita `status` / `poll`: **0** in esecuzione · **1** nessuna attività · **2** scaduta. `start` utilizza anche **3** (VRAM già oltre il limite), **4** (il ciclo precedente non si è arrestato), **5** (nessuna attività dopo l'avvio).

`-Hook` on status emits Claude Code SessionStart JSON and always exits 0
so a dead watchdog cannot break session start.

## Processi terminati

Solo i processi `python` il cui `Path` è presente in `Targets`, più un pattern WSL `pkill -f` opzionale (vuoto = disabilitato). Gli altri processi Python vengono risparmiati. Una violazione che non corrisponde a nulla scrive `_watchdog_NO_TARGET`: si tratta di una **lacuna** nella protezione, non di un successo.

Consenso: `-AllowKill` (o `AllowKill = $true` nel file di configurazione). Il processo di polling non termina mai i processi né li riavvia automaticamente; il riavvio automatico può interrompere un lavoro in corso.

## Modello delle minacce

- **Accesso:** ai file presenti in `Root` (attività, CSV, log di terminazione/console/crash, sentinel); elenco dei processi; contatori GPU; pkill WSL locale opzionale.
- **Non accessibile:** al codice sorgente, ai checkpoint, alle credenziali, alla rete.
- **Autorizzazioni:** l'utente che lo avvia può terminare i processi configurati. Non è presente alcun account di servizio aggiuntivo.
- **Nessun telemetria** lascia la macchina. Nessun segreto nei log.
- **Azione irreversibile:** ARRESTO. Vedi [docs/compensators.md](docs/compensators.md).

## Test

```powershell
pwsh -File .\verify.ps1
```

32 test unitari, senza GPU. Gli elementi di test del parser includono l'output nvidia-smi non valido che ha causato l'interruzione del ciclo il 12 giugno 2026. Il test di interruzione hardware rimane locale e non viene eseguito in CI.

## Origine

Questo è un estratto di un watchdog che era già in esecuzione su una scheda 5090. Gli script pre-estrazione sono stati salvati in [`origin/`](origin/) con hash SHA-256. Gli incidenti datati (errore di analisi, lacuna di cinque settimane, ai-toolkit non protetto, 153 arresti vuoti, interruzione dopo un solo campione) sono disponibili in [docs/incidents.md](docs/incidents.md).

## Licenza

MIT. Vedi [LICENSE](LICENSE). Supportato: 1.x.

Creato da [MCP Tool Shop](https://mcp-tool-shop.github.io/).
