<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.md">English</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
  <a href="https://mcp-tool-shop-org.github.io/watchdog/"><img src="https://img.shields.io/badge/Landing_Page-live-blue" alt="Landing Page"></a>
</p>

# vigilante

Vigilante de VRAM/RAM/temperatura para Windows, diseñado para GPU NVIDIA. Realiza muestreos cada 2 segundos. Después de 3 infracciones consecutivas, elimina **solo** los intérpretes que haya especificado; y lo indica cuando una infracción no causa ningún efecto.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

No cree manualmente una comprobación de "latido". No realice la correspondencia por proceso en `_watchdog`. Estos dos errores son la razón por la cual un vigilante inactivo y uno activo parecen idénticos.

**La versión 1 es solo para Windows** (PowerShell 7, nvidia-smi, contadores de memoria de procesos WDDM, WSL `pkill` opcional). Linux será una versión posterior.

## Instalación

PowerShell 7.1+. Clone el repositorio, copie el archivo de configuración de ejemplo, edítelo y ejecútelo:

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

O importe el módulo:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog` copia el módulo en la ruta del módulo CurrentUser.

## Configuración

**No hay una raíz predeterminada ni una lista de eliminación predeterminada.** El módulo se niega a iniciarse sin un archivo de configuración. Orden de búsqueda: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Campos obligatorios: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. Se rechazan las rutas relativas. Las escrituras se mantienen por debajo de `Root`.

`VramKillMiB = 31200` es el límite documentado para una tarjeta de 32 GB (~1,4 GB por debajo del límite WDDM de 32607 MiB). **No** lo aumente para evitar que se produzcan errores en ComfyUI; limite ComfyUI (`--reserve-vram`) en su lugar.

## Comandos

| Comando | Qué hace |
|---|---|
| `watchdog status` | Verificación de actividad. Es la única comprobación correcta. |
| `watchdog start -AllowKill` | Detención del centinela, espera, limpieza, inicio independiente, verificación del latido. |
| `watchdog stop` | DETENGA el centinela, espere. Nunca realice la correspondencia por proceso. |
| `watchdog poll` | Ejecución única: si el latido está desactualizado, escriba `_watchdog_DEAD` desde el exterior. |
| `watchdog help` | Indicadores y códigos de salida |
| `watchdog version` | `1.0.0` |

Códigos de salida `status` / `poll`: **0** en ejecución · **1** sin latido · **2** desactualizado. `start` también utiliza **3** (la VRAM ya está por encima del límite), **4** (el ciclo anterior no se detuvo) y **5** (no hay latido después del inicio).

`-Hook` en el estado emite JSON de Claude Code SessionStart y siempre sale con 0, para que un vigilante inactivo no interrumpa el inicio de la sesión.

## Qué elimina

Solo los procesos `python` cuyo `Path` está en `Targets`, más un patrón WSL `pkill -f` opcional (vacío = desactivado). El resto de Python se conserva. Una infracción que no coincide con nada escribe `_watchdog_NO_TARGET`; eso es una **brecha** de protección, no un éxito.

Consentimiento: `-AllowKill` (o `AllowKill = $true` en la configuración). El sondeo nunca elimina ni reinicia automáticamente; el reinicio automático puede interrumpir un trabajo activo.

## Modelo de amenaza

- **Afectado:** archivos en `Root` (latido, CSV, registros de eliminación/consola/fallos, centinelas); lista de procesos; contadores de GPU; pkill local WSL opcional.
- **No afectado:** su árbol de código fuente, puntos de control, credenciales, la red.
- **Permisos:** el usuario que lo inicia puede eliminar los intérpretes configurados. No hay ninguna cuenta de servicio adicional.
- **No se envía telemetría** fuera de la máquina. No hay secretos en los registros.
- **Acción irreversible:** ABORTAR. Consulte [docs/compensators.md](docs/compensators.md).

## Pruebas

```powershell
pwsh -File .\verify.ps1
```

32 pruebas unitarias, sin GPU. Los casos de prueba del analizador incluyen la salida incorrecta de nvidia-smi que detuvo el ciclo el 12 de junio de 2026. La prueba de aborto de hardware se mantiene local y no se incluye en CI.

## Origen

Este es un extracto de un vigilante que ya se ejecutaba en una 5090. Los scripts de preextracción están congelados en [`origin/`](origin/) con identificadores SHA-256. Los incidentes fechados (error de análisis, brecha de cinco semanas, ai-toolkit sin protección, 153 ABORTs vacíos, muerte de una muestra) se encuentran en [docs/incidents.md](docs/incidents.md).

## Licencia

MIT. Consulte [LICENSE](LICENSE). Compatible con: 1.x.

Creado por [MCP Tool Shop](https://mcp-tool-shop.github.io/).
