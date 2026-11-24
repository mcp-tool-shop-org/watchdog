<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.md">English</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

Surveillance de la VRAM/RAM/température pour les GPU NVIDIA sous Windows. Il effectue un contrôle toutes les 2 secondes. Après 3 violations consécutives, il ne tue que les interpréteurs que vous avez spécifiés, et il l’indique lorsqu’une violation n’entraîne aucune conséquence.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

Ne créez pas manuellement une vérification de l’activité. N’effectuez pas de correspondance de processus sur `_watchdog`. Ces deux erreurs sont la cause d’un watchdog défaillant et d’un watchdog fonctionnel qui semblent identiques.

**v1 est uniquement compatible avec Windows** (PowerShell 7, nvidia-smi, compteurs de mémoire de processus WDDM, WSL `pkill` et libération de la mémoire cache des fichiers WSL en option). Linux est une version ultérieure.

## Installation

PowerShell 7.1+. Clonez, copiez le fichier de configuration d’exemple, modifiez-le, puis démarrez :

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

`Install-Watchdog` copie le module dans le chemin du module CurrentUser.

## Configuration

Il n’y a **pas de répertoire racine par défaut ni de liste de processus à arrêter par défaut**. Le module refuse de démarrer sans fichier de configuration. Ordre de recherche : `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Champs obligatoires : `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. Les chemins relatifs sont rejetés. Les écritures restent inférieures à `Root`.

`VramKillMiB = 31200` est la limite documentée pour une carte de 32 Go (~1,4 Go en dessous du plafond WDDM de 32 607 MiB). Ne l’augmentez **pas** pour éviter les déclenchements de ComfyUI ; limitez plutôt ComfyUI (`--reserve-vram`).

### Libération du cache de fichiers WSL (opt-in, sur activation explicite)

Avec `WslCacheRelease = $true`, chaque contrôle vérifie la mémoire de la machine virtuelle WSL depuis Windows (il ne réveille jamais une machine virtuelle arrêtée). Lorsque `vmmemWSL` est volumineux, ou que la mémoire Windows est sous pression et que `vmmemWSL` est de taille moyenne, le contrôleur vide le cache de pages Linux dans `WslDistro` (`echo 1 > /proc/sys/vm/drop_caches` en tant que root, avec délai d’expiration et temps de repos). L’`autoMemoryReclaim` propre à WSL ne se déclenche que lorsque la machine virtuelle est inactive, et un moteur de conteneurs en cours d’exécution la maintient occupée, si bien que le téléchargement d’images volumineuses peut laisser des dizaines de Go de cache retenus au détriment de Windows.

Il ne tue jamais un processus et ne démarre jamais une distribution arrêtée : lorsqu’une autre distribution maintient la machine virtuelle en marche alors que `WslDistro` est arrêtée, il ne libère pas le cache et consigne ce saut. Son journal, `Root\_watchdog_wslcache.log`, enregistre un signal d’activité toutes les heures ; chaque libération du cache, avec la mémoire avant et après ; une ligne par série de sauts ; et un `ALERT` indiquant les processus les plus gourmands en ressources si Windows est toujours au-dessus de `WslCacheAlertPct` après une libération. Les seuils sont définis dans le fichier de configuration d’exemple.

## Commandes

| Commande | Ce qu’elle fait |
|---|---|
| `watchdog status` | Vérification de l’activité. La seule vérification correcte. |
| `watchdog start -AllowKill` | Arrêt du sentinelle, attente, effacement, lancement en arrière-plan, vérification du signal d’activité |
| `watchdog stop` | ARRÊTEZ le sentinelle, attendez. N’effectuez jamais de correspondance de processus. |
| `watchdog poll` | Exécution unique : si le signal d’activité est obsolète, écrivez `_watchdog_DEAD` depuis l’extérieur. |
| `watchdog help` | Indicateurs et codes de sortie |
| `watchdog version` | `1.1.1` |

`status` / `poll` codes de sortie : **0** en cours d’exécution ; **1** aucun signal d’activité ; **2** obsolète. `start` utilise également **3** (la VRAM dépasse déjà le plafond), **4** (la boucle précédente ne s’est pas arrêtée), **5** (aucun signal d’activité après le lancement).

`-Hook` sur l’état émet le JSON Claude Code SessionStart et quitte toujours avec le code 0, de sorte qu’un watchdog défaillant ne peut pas interrompre le démarrage de la session.

## Ce qu’il tue

Uniquement les processus `python` dont le `Path` se trouve dans `Targets`, ainsi qu’un modèle WSL `pkill -f` facultatif (vide = désactivé). Les autres programmes Python sont épargnés. Une violation qui ne correspond à rien écrit `_watchdog_NO_TARGET` ; il s’agit d’une **faille de sécurité**, et non d’un succès.

Consentement : `-AllowKill` (ou `AllowKill = $true` dans la configuration). Le contrôleur ne tue jamais et ne redémarre jamais automatiquement ; le redémarrage automatique peut interrompre un travail en cours.

## Modèle de menace

- **Touché :** fichiers sous `Root` (signal d’activité, CSV, journaux d’arrêt/console/plantage, sentinelles) ; liste des processus ; compteurs GPU ; pkill WSL local facultatif ; vidage facultatif du cache de pages WSL (opt-in sur activation explicite, ne tue jamais de processus).
- **Non touché :** votre arborescence de code source, points de contrôle, informations d’identification, le réseau.
- **Autorisations :** l’utilisateur qui le démarre peut tuer les interpréteurs configurés. Il n’y a pas de compte de service supplémentaire.
- **Aucune télémétrie** ne quitte la machine. Pas de secrets dans les journaux.
- **Action irréversible :** ABORT. Voir [docs/compensators.md](docs/compensators.md).

## Tests

```powershell
pwsh -File .\verify.ps1
```

134 tests unitaires, pas de GPU. Les données de test du parseur incluent la sortie incorrecte de nvidia-smi qui a interrompu la boucle le 12 juin 2026. Le test d’arrêt matériel reste local et n’est pas intégré dans le processus d’intégration continue.

`pwsh -File .\verify.ps1 -Coverage` ajoute la couverture de lignes de `src/Watchdog` et échoue en dessous de 90 %. La CI l’exécute ainsi et envoie le rapport à Codecov, qui exige au moins 90 % de couverture sur l’ensemble du module et sur chaque modification.

## Origine

Il s’agit d’une extraction d’un watchdog qui fonctionnait déjà sur une 5090. Les scripts de pré-extraction sont figés dans [`origin/`](origin/) avec SHA-256. Les incidents datés (plantage de l’analyse, trou de cinq semaines, ai-toolkit non protégé, 153 ABORT vides, arrêt en un seul échantillon) sont disponibles dans [docs/incidents.md](docs/incidents.md).

## Licence

MIT. Voir [LICENSE](LICENSE). Pris en charge : 1.x.

Créé par [MCP Tool Shop](https://mcp-tool-shop.github.io/).
