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

**Une limite stricte pour les tâches GPU de longue durée sous Windows.** Watchdog vérifie la VRAM et la température de votre carte NVIDIA, ainsi que la RAM de votre système, toutes les 2 secondes. Lorsqu’une limite est dépassée pendant trois vérifications consécutives, il arrête les interpréteurs Python que vous lui avez autorisés à arrêter, et rien d’autre.

Vous lancez une tâche d’entraînement ou un rendu important, vous vous absentez, et une fuite de mémoire, un lot de données trop volumineux ou une carte surchauffée transforment votre ordinateur en une machine figée. Watchdog est le petit processus qui reste actif pour vous : il applique les limites que vous avez définies, enregistre ce qu’il a observé et vous indique clairement quand il n’a pas pu vous protéger.

## Ce que vous obtenez

- **Des limites que vous choisissez.** VRAM en MiB, RAM en pourcentage, température du GPU en °C. Il n’y a pas de valeurs par défaut cachées.
- **Arrêts ciblés.** Seuls les chemins d’accès aux interpréteurs que vous spécifiez (plus un modèle de processus WSL facultatif) peuvent être arrêtés. Tous les autres processus Python sur la machine sont laissés intacts.
- **Pas de fausse sécurité.** Une violation qui ne correspond à aucun des processus que vous avez spécifiés est enregistrée comme une lacune de protection, et les processus qui utilisent la VRAM sont nommés.
- **Un watchdog pour le watchdog.** Une tâche planifiée facultative vérifie le signal de présence une fois par minute et marque le watchdog comme étant hors service si celui-ci s’est arrêté. Il ne redémarre jamais quoi que ce soit de lui-même.
- **Une réponse claire sur son état de fonctionnement.** `watchdog status` renvoie 0 (en fonctionnement), 1 (non en fonctionnement) ou 2 (arrêt brutal).
- **Un enregistrement de chaque exécution.** Un fichier CSV contenant des échantillons, un journal des arrêts, une transcription de la console et un journal des plantages, le tout conservé dans un seul dossier que vous choisissez.
- **Retour de mémoire WSL facultatif.** Si la mémoire cache de WSL surcharge la mémoire de Windows, le processus de vérification peut supprimer ce cache. Il n’arrête jamais un processus et ne démarre jamais une distribution arrêtée.

## Démarrage rapide

Prérequis : Windows, PowerShell 7 ou version ultérieure, et un pilote NVIDIA avec `nvidia-smi` sur `PATH`.

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill` est votre consentement : watchdog ne démarrera pas sans cela, ni sans `AllowKill = $true` dans la configuration.
Pour l’installer en tant que module et ajouter la vérification externe :

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## Comment cela fonctionne

1. **Échantillon.** Toutes les `IntervalSec` (2 s par défaut), il lit la température, la puissance et la VRAM du GPU à partir de `nvidia-smi`, et la RAM du système à partir de Windows.
2. **Attendre un modèle, pas un pic.** Une limite doit être dépassée `BreachSamples` fois de suite (3 par défaut) avant que quoi que ce soit ne se produise. Des avertissements sont enregistrés en cours de route.
3. **Arrêter uniquement ce que vous avez spécifié.** En cas de violation persistante, il arrête les `python` processus dont le chemin d’accès figure dans `Targets`, et exécute le modèle WSL `pkill` facultatif. Il enregistre ce qu’il a arrêté, ou qu’il n’a rien arrêté.
4. **Prouver qu’il est en fonctionnement.** La boucle réécrit un fichier de signal de présence à chaque échantillon. `watchdog status` et le processus de vérification planifié évaluent l’état de fonctionnement à partir de ce signal de présence, de sorte qu’un watchdog hors service ne puisse jamais sembler en bon état.

## Commandes

| Commande | Ce qu’elle fait |
|---|---|
| `watchdog status` | Vérification de l’état de fonctionnement. Renvoie 0 (en fonctionnement), 1 (non en fonctionnement) ou 2 (arrêt brutal). |
| `watchdog start -AllowKill` | Arrête proprement toute ancienne boucle, démarre une nouvelle boucle en arrière-plan et attend son signal de présence. |
| `watchdog stop` | Demande à la boucle de s’arrêter via un fichier sentinelle et attend. |
| `watchdog poll` | Une seule vérification externe, exécutée par la tâche planifiée. |
| `watchdog install` / `uninstall` | Copie ou supprime le module. `install -Poll` enregistre également la vérification planifiée. |
| `watchdog help` / `version` | Indicateurs, codes de sortie et version. |

`start` refuse avec le code de sortie 3 si la VRAM dépasse déjà votre limite (utilisez `-Force` uniquement si vous le souhaitez vraiment). `status -Hook` affiche un message Claude Code SessionStart et renvoie toujours 0, de sorte qu’un watchdog hors service est signalé sans interrompre la session. Référence complète : [handbook → Reference](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/).

## Configuration

Watchdog ne démarrera pas sans fichier de configuration. Il recherche dans `-ConfigPath`, puis `$env:WATCHDOG_CONFIG`, puis `./watchdog.config.psd1`, puis `~/.watchdog/config.psd1`.

| Obligatoire | Signification |
|---|---|
| `Root` | Dossier absolu pour le fichier de signal de présence, les journaux et les fichiers sentinelles. Watchdog n’écrit nulle part ailleurs. |
| `Targets` | Chemins d’accès absolus aux interpréteurs qu’il peut arrêter. |
| `VramKillMiB` | Limite de VRAM en MiB. Pour une carte de 32 Go, `31200` laisse environ 1,4 Go de marge. |
| `RamKillPct` | Limite de la RAM du système en pourcentage. |
| `TempKillC` | Limite de la température du GPU en °C. |

Si une tâche dépasse la limite de VRAM en utilisation normale, limitez la tâche (pour ComfyUI, `--reserve-vram`) plutôt que d’augmenter la limite. Tous les autres paramètres, y compris la libération du cache WSL, sont disponibles dans [handbook → Configuration](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/).

## Sécurité

- **Consentement d’abord.** Rien n’est jamais arrêté sans `-AllowKill` ou `AllowKill = $true`.
- **Touché :** fichiers sous `Root`, liste des processus, compteurs GPU ; et, uniquement si vous les activez, un modèle WSL `pkill` et la suppression du cache de pages WSL.
- **Non touché :** vos arbres de code source, points de contrôle, informations d’identification et le réseau. Aucune télémétrie ne quitte la machine.
- **La seule action irréversible est l’arrêt lui-même.** Une tâche arrêtée perd tout ce qu’elle n’a pas enregistré. Ce qui est perdu et comment s’en remettre est décrit dans [docs/compensators.md](docs/compensators.md).

Consultez [SECURITY.md](SECURITY.md) pour signaler une vulnérabilité.

## Plateforme

La version 1 est uniquement pour Windows : elle dépend de PowerShell 7, `nvidia-smi`, des compteurs de mémoire de processus GPU Windows et, éventuellement, de WSL. La prise en charge de Linux est prévue pour une version ultérieure.

## Développement

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

Chaque arrêt, lancement et appel de tâche planifiée dans les tests sont simulés, de sorte que leur exécution ne touche jamais les processus réels. Les scripts de pré-extraction sont conservés, avec un hachage fixe, dans [`origin/`](origin/), et les incidents qui ont façonné la conception sont décrits dans [docs/incidents.md](docs/incidents.md).

## Licence

MIT. Voir [LICENSE](LICENSE).

Créé par [MCP Tool Shop](https://mcp-tool-shop.github.io/).
