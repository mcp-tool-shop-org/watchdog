<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.md">English</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

# watchdog

Surveillanceur de la VRAM/RAM/température pour les GPU NVIDIA sous Windows. Il effectue un contrôle toutes les 2 secondes. Après 3 violations consécutives, il ne tue que les interpréteurs que vous avez spécifiés, et il l’indique lorsqu’une violation n’entraîne aucune action.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

N’implémentez pas manuellement une vérification de la présence (heartbeat). N’effectuez pas de correspondance basée sur `_watchdog`. Ces deux erreurs sont la cause d’un watchdog défaillant et d’un watchdog fonctionnel qui semblent identiques.

**La version 1 est uniquement pour Windows** (PowerShell 7, nvidia-smi, compteurs de mémoire des processus WDDM, WSL `pkill` en option). Linux sera disponible dans une version ultérieure.

## Installation

PowerShell 7.1 ou supérieur. Clonez, copiez le fichier de configuration d’exemple, modifiez-le et démarrez :

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

Ou importez le module :

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog` copie le module dans le répertoire des modules CurrentUser.

## Configuration

Il n’y a **pas de racine par défaut ni de liste d’éléments à éliminer par défaut**. Le module refuse de démarrer sans fichier de configuration. Ordre de recherche : `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Champs obligatoires : `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. Les chemins relatifs sont rejetés. Les écritures restent inférieures à `Root`.

`VramKillMiB = 31200` est la limite documentée pour une carte de 32 Go (~1,4 Go en dessous du plafond WDDM de 32 607 MiB). Ne l’augmentez **pas** pour arrêter les problèmes avec ComfyUI ; limitez plutôt ComfyUI (`--reserve-vram`).

## Commandes

| Commande | Ce qu’elle fait |
|---|---|
| `watchdog status` | Vérification de la présence. La seule vérification correcte. |
| `watchdog start -AllowKill` | Arrêt du sentinelle, attente, effacement, lancement en arrière-plan, vérification de la présence. |
| `watchdog stop` | ARRÊT du sentinelle, attente. Ne jamais effectuer de correspondance basée sur les processus. |
| `watchdog poll` | Exécution unique : si la présence n’est pas détectée, écrivez `_watchdog_DEAD` depuis l’extérieur. |
| `watchdog help` | Indicateurs et codes de sortie |
| `watchdog version` | `1.0.0` |

Codes de sortie `status` / `poll` : **0** (en cours d’exécution), **1** (pas de présence), **2** (présence obsolète). `start` utilise également **3** (la VRAM dépasse déjà la limite), **4** (l’ancienne boucle ne s’est pas arrêtée) et **5** (pas de présence après le lancement).

`-Hook` sur l’état émet un JSON Claude Code SessionStart et se termine toujours avec 0, afin qu’un watchdog défaillant ne puisse pas interrompre le démarrage de la session.

## Ce qu’il élimine

Uniquement les processus `python` dont l’ID `Path` se trouve dans `Targets`, plus un modèle WSL `pkill -f` facultatif (vide = désactivé). Les autres programmes Python sont épargnés. Une violation qui ne correspond à rien écrit `_watchdog_NO_TARGET` ; il s’agit d’une **faille de sécurité**, et non d’un succès.

Consentement : `-AllowKill` (ou `AllowKill = $true` dans la configuration). Le vérificateur n’élimine jamais et ne redémarre jamais automatiquement ; le redémarrage automatique peut interrompre un travail en cours.

## Modèle de menace

- **Touché :** fichiers situés dans `Root` (présence, CSV, journaux d’élimination/console/plantage, sentinelles) ; liste des processus ; compteurs GPU ; pkill WSL local facultatif.
- **Non touché :** votre arborescence de code source, points de contrôle, informations d’identification, le réseau.
- **Autorisations :** l’utilisateur qui le démarre peut éliminer les interpréteurs configurés. Il n’y a pas de compte de service supplémentaire.
- **Aucune télémétrie** ne quitte la machine. Aucun secret dans les journaux.
- **Action irréversible :** ARRÊT. Voir [docs/compensators.md](docs/compensators.md).

## Tests

```powershell
pwsh -File .\verify.ps1
```

32 tests unitaires, sans GPU. Les éléments de test du parseur incluent la sortie nvidia-smi malformée qui a interrompu la boucle le 12 juin 2026. Le test d’arrêt matériel reste local et n’est pas activé dans CI.

## Origine

Il s’agit d’une extraction d’un watchdog qui fonctionnait déjà sur une 5090. Les scripts de pré-extraction sont figés sous [`origin/`](origin/) avec des identifiants SHA-256. Les incidents datés (plantage du parseur, trou de cinq semaines, ai-toolkit non protégé, 153 ARRÊTs vides, arrêt après un seul échantillon) se trouvent dans [docs/incidents.md](docs/incidents.md).

## Licence

MIT. Voir [LICENSE](LICENSE). Pris en charge : 1.x.

Créé par [MCP Tool Shop](https://mcp-tool-shop.github.io/).
