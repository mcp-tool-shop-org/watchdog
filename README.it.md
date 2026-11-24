<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.md">English</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

Watchdog per VRAM/RAM/temperatura di Windows per GPU NVIDIA. Esegue un controllo ogni 2 secondi. Dopo 3 violazioni consecutive, termina **solo** gli interpreti elencati e lo comunica quando una violazione non causa l'interruzione di alcun processo.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

Non implementare manualmente un controllo dell'attività. Non effettuare il confronto dei processi in base a `_watchdog`. Questi due errori sono ciò che fa sembrare identici un watchdog non funzionante e uno funzionante.

**v1 è disponibile solo per Windows** (PowerShell 7, nvidia-smi, contatori di memoria dei processi WDDM, WSL `pkill` e rilascio della cache dei file WSL opzionali). Linux è una versione successiva.

## Installazione

PowerShell 7.1+. Clona, copia il file di configurazione di esempio, modificalo, avvia:

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

`Install-Watchdog` copia il modulo nel percorso del modulo CurrentUser.

## Configurazione

Non sono presenti impostazioni predefinite per la directory principale né per la lista dei processi da terminare. Il modulo si rifiuta di avviarsi senza un file di configurazione. Ordine di ricerca: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Campi obbligatori: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. I percorsi relativi non sono accettati. Le scritture avvengono all'interno di `Root`.

`VramKillMiB = 31200` è il limite documentato per una scheda da 32 GB (~1,4 GB inferiore al limite WDDM di 32607 MiB). Non aumentarlo per evitare che si verifichino troppe interruzioni (ComfyUI); limita invece ComfyUI (`--reserve-vram`).

### Rilascio della cache dei file WSL (opt-in, su attivazione esplicita)

Con `WslCacheRelease = $true`, ogni controllo verifica la memoria della VM WSL dal lato Windows (non risveglia mai una VM arrestata). Quando `vmmemWSL` è grande, o la memoria di Windows è sotto pressione e `vmmemWSL` è di dimensioni medie, il poller rilascia la page cache di Linux in `WslDistro` (`echo 1 > /proc/sys/vm/drop_caches` come root, con timeout e cooldown). L’`autoMemoryReclaim` di WSL si attiva solo quando la VM è inattiva e un motore di container in esecuzione la mantiene occupata, quindi il pull di immagini di grandi dimensioni può lasciare decine di GB di cache trattenuti a scapito di Windows.

Non termina mai un processo e non avvia mai una distribuzione che è già stata interrotta: quando un’altra distribuzione mantiene attiva la macchina virtuale mentre `WslDistro` è inattiva, salta l’operazione di rilascio e registra l’omissione. Il suo registro, `Root\_watchdog_wslcache.log`, registra un segnale di attività ogni ora; ogni operazione di rilascio della cache, con i dati relativi alla memoria prima e dopo; una riga per ogni serie di omissioni; e un `ALERT` che indica i processi principali se Windows è ancora al di sopra di `WslCacheAlertPct` dopo un’operazione di rilascio. Le soglie sono indicate nella configurazione di esempio.

## Comandi

| Comando | Cosa fa |
|---|---|
| `watchdog status` | Controllo dell'attività. L'unico controllo corretto. |
| `watchdog start -AllowKill` | Arresto del sentinella, attesa, cancellazione, avvio in background, verifica del controllo dell'attività |
| `watchdog stop` | ARRESTO del sentinella, attesa. Non effettuare mai il confronto dei processi. |
| `watchdog poll` | Esecuzione singola: se il controllo dell'attività è obsoleto, scrivi `_watchdog_DEAD` dall'esterno |
| `watchdog help` | Flag e codici di uscita |
| `watchdog version` | `1.1.1` |

Codici di uscita `status` / `poll`: **0** in esecuzione · **1** nessun controllo dell'attività · **2** obsoleto. `start` utilizza anche **3** (VRAM già al di sopra del limite), **4** (il ciclo precedente non si è arrestato), **5** (nessun controllo dell'attività dopo l'avvio).

`-Hook` sullo stato emette il JSON di Claude Code SessionStart ed esce sempre con 0, in modo che un watchdog non funzionante non possa interrompere l'avvio della sessione.

## Cosa termina

Solo i processi `python` il cui `Path` è in `Targets`, più un pattern WSL `pkill -f` opzionale (vuoto = disabilitato). Gli altri processi Python vengono risparmiati. Un'interruzione che non corrisponde a nulla scrive `_watchdog_NO_TARGET`: si tratta di una **lacuna** nella protezione, non di un successo.

Consenso: `-AllowKill` (o `AllowKill = $true` nel file di configurazione). Il controllo non termina mai i processi né li riavvia automaticamente; il riavvio automatico può interrompere un lavoro in corso.

## Modello di minaccia

- **Accesso:** file sotto `Root` (heartbeat, CSV, log di terminazione/console/crash, sentinelle); elenco dei processi; contatori GPU; pkill WSL locale opzionale; rilascio opzionale della page cache WSL (opt-in, non termina mai alcun processo).
- **Non accessibile:** l'albero di origine, i checkpoint, le credenziali, la rete.
- **Autorizzazioni:** l'utente che lo avvia può terminare gli interpreti configurati. Non è presente alcun account di servizio aggiuntivo.
- **Nessun telemetria** lascia la macchina. Nessun segreto nei log.
- **Azione irreversibile:** ABORT. Vedi [docs/compensators.md](docs/compensators.md).

## Test

```powershell
pwsh -File .\verify.ps1
```

132 test unitari, senza GPU. Le fixture del parser includono l’output nvidia-smi malformato che ha interrotto il ciclo il 2026-06-12. Il test di abort hardware resta locale e non viene eseguito in CI.

`pwsh -File .\verify.ps1 -Coverage` aggiunge la copertura delle righe di `src/Watchdog` e fallisce sotto il 90%. La CI lo esegue in questo modo e carica il report su Codecov, che richiede almeno il 90% di copertura sull’intero modulo e su ogni modifica.

## Origine

Questo è un estratto di un watchdog che è già stato eseguito su una 5090. Gli script pre-estrazione sono stati congelati in [`origin/`](origin/) con SHA-256 pin. Gli incidenti datati (crash dell'analisi, vuoto di cinque settimane, ai-toolkit non protetto, 153 ABORT vuoti, morte con un solo campione) sono in [docs/incidents.md](docs/incidents.md).

## Licenza

MIT. Vedi [LICENSE](LICENSE). Supportato: 1.x.

Creato da [MCP Tool Shop](https://mcp-tool-shop.github.io/).
