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

**Un limite massimo per i processi GPU di lunga durata su Windows.** Watchdog controlla la VRAM e la temperatura della tua scheda NVIDIA e la RAM del sistema ogni 2 secondi. Quando un limite viene superato per tre controlli consecutivi, interrompe gli interpreti Python che hai autorizzato a interrompere e nient'altro.

Avvii un processo di addestramento o un rendering di grandi dimensioni, ti allontani e un errore, un batch di dimensioni eccessive o una scheda surriscaldata lo trasformano in un desktop bloccato. Watchdog è il piccolo processo che rimane attivo per te: applica i limiti che hai impostato, registra ciò che ha rilevato e ti comunica chiaramente quando non è stato in grado di proteggerti.

## Cosa ottieni

- **Limiti che scegli tu.** VRAM in MiB, RAM in percentuale, temperatura della GPU in °C. Non ci sono impostazioni predefinite nascoste.
- **Interruzioni mirate.** Solo i percorsi degli interpreti che elenchi (più un modello di processo WSL opzionale) possono essere interrotti. Tutti gli altri processi Python sulla macchina vengono lasciati inalterati.
- **Nessuna falsa sicurezza.** Una violazione che non corrisponde a nessuno dei processi elencati viene registrata come una lacuna nella protezione e i processi che utilizzano la VRAM vengono identificati.
- **Un watchdog per il watchdog.** Un'attività pianificata opzionale controlla il segnale di attività una volta al minuto e contrassegna il watchdog come inattivo dall'esterno se si è interrotto. Non riavvia mai nulla da solo.
- **Una risposta chiara sullo stato di attività.** `watchdog status` restituisce 0 (in esecuzione), 1 (non in esecuzione) o 2 (interrotto in modo definitivo).
- **Un registro di ogni esecuzione.** Un file CSV con i campioni, un registro delle interruzioni, una trascrizione della console e un registro degli errori, tutti conservati in una singola cartella che scegli.
- **Rilascio opzionale della memoria WSL.** Se la cache dei file di WSL occupa la memoria di Windows, il processo di controllo può eliminare tale cache. Non interrompe mai un processo e non avvia mai una distribuzione interrotta.

## Avvio rapido

Requisiti: Windows, PowerShell 7 o versione successiva e un driver NVIDIA con `nvidia-smi` su `PATH`.

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill` è il tuo consenso: watchdog non si avvierà senza di esso, né senza `AllowKill = $true` nella configurazione.
Per installarlo come modulo e aggiungere il controllo esterno:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## Come funziona

1. **Campione.** Ogni `IntervalSec` (2 secondi per impostazione predefinita), legge la temperatura, la potenza e la VRAM della GPU da `nvidia-smi` e la RAM del sistema da Windows.
2. **Attendi un modello, non un picco.** Un limite deve essere superato `BreachSamples` volte di seguito (3 per impostazione predefinita) prima che accada qualcosa. Gli avvisi vengono registrati durante il processo.
3. **Interrompi solo ciò che hai elencato.** In caso di violazione prolungata, interrompe i `python` processi il cui percorso è in `Targets` ed esegue il modello WSL `pkill` opzionale. Registra ciò che ha interrotto o che non ha interrotto nulla.
4. **Dimostra che è attivo.** Il ciclo sovrascrive un file di segnale di attività a ogni campione. `watchdog status` e il processo di controllo pianificato valutano lo stato di attività in base a tale segnale, quindi un watchdog inattivo non può mai apparire attivo.

## Comandi

| Comando | Cosa fa |
|---|---|
| `watchdog status` | Controllo dello stato di attività. Restituisce 0 (in esecuzione), 1 (non in esecuzione) o 2 (interrotto in modo definitivo). |
| `watchdog start -AllowKill` | Interrompe in modo pulito qualsiasi ciclo precedente, ne avvia uno nuovo in background e attende il suo segnale di attività. |
| `watchdog stop` | Chiede al ciclo di interrompersi tramite un file di segnale e attende. |
| `watchdog poll` | Un singolo controllo esterno, eseguito dall'attività pianificata. |
| `watchdog install` / `uninstall` | Copia o rimuove il modulo. `install -Poll` registra anche il controllo pianificato. |
| `watchdog help` / `version` | Flag, codici di uscita e versione. |

`start` rifiuta con il codice di uscita 3 se la VRAM supera già il limite (utilizza `-Force` solo se lo intendi). `status -Hook` stampa un messaggio Claude Code SessionStart e restituisce sempre 0, quindi un watchdog inattivo viene segnalato senza interrompere la sessione. Riferimento completo: [handbook → Reference](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/).

## Configurazione

Watchdog non si avvierà senza una configurazione. Cerca in `-ConfigPath`, quindi in `$env:WATCHDOG_CONFIG`, quindi in `./watchdog.config.psd1`, quindi in `~/.watchdog/config.psd1`.

| Obbligatorio | Significato |
|---|---|
| `Root` | Cartella assoluta per il file di segnale di attività, i registri e i file di segnale. Watchdog non scrive altrove. |
| `Targets` | Percorsi assoluti degli interpreti che può interrompere. |
| `VramKillMiB` | Limite massimo della VRAM in MiB. Per una scheda da 32 GB, `31200` lascia circa 1,4 GB di spazio libero. |
| `RamKillPct` | Limite massimo della RAM del sistema in percentuale. |
| `TempKillC` | Limite massimo della temperatura della GPU in °C. |

Se un processo supera il limite massimo della VRAM durante l'uso normale, limita il processo (per ComfyUI, `--reserve-vram`) anziché aumentare il limite. Tutte le altre impostazioni, incluso il rilascio della cache WSL, sono disponibili in [handbook → Configuration](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/).

## Sicurezza

- **Consenso prima di tutto.** Nessun processo viene mai interrotto senza `-AllowKill` o `AllowKill = $true`.
- **Toccato:** file in `Root`, l'elenco dei processi, i contatori della GPU e, solo se li abiliti, un modello WSL `pkill` e l'eliminazione della cache delle pagine WSL.
- **Non toccato:** le tue directory di origine, i checkpoint, le credenziali e la rete. Nessun dato di telemetria lascia la macchina.
- **L'unica azione irreversibile è l'interruzione stessa.** Un processo interrotto perde tutto ciò che non ha salvato. Cosa viene perso e come ripristinarlo è disponibile in [docs/compensators.md](docs/compensators.md).

Consulta [SECURITY.md](SECURITY.md) per segnalare una vulnerabilità.

## Piattaforma

La versione 1 è solo per Windows: si basa su PowerShell 7, `nvidia-smi`, i contatori della memoria di processo della GPU di Windows e, facoltativamente, WSL. Il supporto per Linux è previsto per una versione successiva.

## Sviluppo

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

Ogni interruzione, avvio e chiamata di attività pianificata nei test è simulata, quindi l'esecuzione non influisce mai sui processi reali. Gli script di pre-estrazione sono conservati, con hash fissi, in [`origin/`](origin/) e gli incidenti che hanno plasmato il progetto sono disponibili in [docs/incidents.md](docs/incidents.md).

## Licenza

MIT. Consulta [LICENSE](LICENSE).

Creato da [MCP Tool Shop](https://mcp-tool-shop.github.io/).
