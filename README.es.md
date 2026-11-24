<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.md">English</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

# vigilante

Vigilante de VRAM/RAM/temperatura de Windows para GPU de NVIDIA. Realiza muestreos cada 2 segundos. Después de 3 infracciones consecutivas, solo finaliza los intérpretes que haya especificado, y lo indica cuando una infracción no causa ningún efecto.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

No cree manualmente una comprobación de "latido". No realice una coincidencia de procesos en `_watchdog`. Estos dos errores son la causa de que un vigilante defectuoso y uno en buen estado parezcan idénticos.

**v1 solo es compatible con Windows** (PowerShell 7, nvidia-smi, contadores de memoria de procesos WDDM, WSL `pkill` y liberación de caché de archivos WSL opcionales). Linux es una versión posterior.

## Instalación

PowerShell 7.1+. Clone, copie el archivo de configuración de ejemplo, edítelo y ejecute:

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

No hay una raíz predeterminada ni una lista de finalización predeterminada. El módulo se niega a iniciarse sin una configuración. Orden de búsqueda: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Campos obligatorios: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. Se rechazan las rutas relativas. Las escrituras se mantienen por debajo de `Root`.

`VramKillMiB = 31200` es el límite documentado para una tarjeta de 32 GB (~1,4 GB por debajo del límite de 32607 MiB de WDDM). No lo aumente para evitar que se produzcan ComfyUI; en su lugar, limite ComfyUI (`--reserve-vram`).

### Liberación de la caché de archivos de WSL (opt-in, activación explícita)

Con `WslCacheRelease = $true`, cada sondeo comprueba la memoria de la máquina virtual WSL desde el lado de Windows (nunca activa una máquina virtual detenida). Cuando `vmmemWSL` es grande, o la memoria de Windows está bajo presión y `vmmemWSL` es de tamaño medio, el sondeo libera la caché de páginas de Linux en `WslDistro` (`echo 1 > /proc/sys/vm/drop_caches` como root, con tiempo de espera y enfriamiento). El propio `autoMemoryReclaim` de WSL solo se activa cuando la máquina virtual está inactiva, y un motor de contenedores en ejecución la mantiene ocupada, por lo que las descargas de imágenes grandes pueden dejar decenas de GB de caché retenidos a costa de Windows.

Nunca finaliza un proceso y nunca inicia una distribución que se ha detenido: cuando otra distribución mantiene la máquina virtual en funcionamiento mientras `WslDistro` está detenida, omite la liberación y registra la omisión. Su registro, `Root\_watchdog_wslcache.log`, anota una señal de actividad cada hora; cada liberación de la caché, con la memoria antes y después; una línea por cada racha de omisiones; y un `ALERT` que indica los procesos principales si Windows sigue por encima de `WslCacheAlertPct` después de una liberación. Los umbrales se encuentran en la configuración de ejemplo.

## Comandos

| Comando | Qué hace |
|---|---|
| `watchdog status` | Comprobación de actividad. Es la única comprobación correcta. |
| `watchdog start -AllowKill` | Detención del vigilante, espera, limpieza, lanzamiento independiente, verificación del "latido". |
| `watchdog stop` | DETENGA el vigilante, espere. Nunca realice una coincidencia de procesos. |
| `watchdog poll` | Ejecución única: si el "latido" está desactualizado, escriba `_watchdog_DEAD` desde el exterior. |
| `watchdog help` | Indicadores y códigos de salida |
| `watchdog version` | `1.1.1` |

Códigos de salida `status` / `poll`: **0** en ejecución · **1** sin "latido" · **2** desactualizado. `start` también utiliza **3** (la VRAM ya está por encima del límite), **4** (el ciclo anterior no se detuvo), **5** (no hay "latido" después del lanzamiento).

`-Hook` en el estado emite Claude Code SessionStart en formato JSON y siempre sale con 0, para que un vigilante defectuoso no interrumpa el inicio de la sesión.

## Qué finaliza

Solo los procesos `python` cuyo `Path` se encuentra en `Targets`, más un patrón opcional de WSL `pkill -f` (vacío = desactivado). El resto de Python se salva. Una infracción que no coincide con nada escribe `_watchdog_NO_TARGET`; esa es una **brecha** de protección, no un éxito.

Consentimiento: `-AllowKill` (o `AllowKill = $true` en la configuración). El sondeo nunca finaliza ni reinicia automáticamente; el reinicio automático puede interrumpir un trabajo en curso.

## Modelo de amenazas

- **Afectados:** archivos bajo `Root` (latido, CSV, registros de finalización/consola/fallos, centinelas); lista de procesos; contadores de GPU; pkill local de WSL opcional; liberación opcional de caché de páginas de WSL (activación explícita / opt-in, nunca mata procesos).
- **No afectados:** su árbol de código fuente, puntos de control, credenciales, la red.
- **Permisos:** el usuario que lo inicia puede finalizar los intérpretes configurados. No hay ninguna cuenta de servicio adicional.
- **No hay telemetría** que salga de la máquina. No hay secretos en los registros.
- **Acción irreversible:** ABORTAR. Consulte [docs/compensators.md](docs/compensators.md).

## Pruebas

```powershell
pwsh -File .\verify.ps1
```

123 pruebas unitarias, sin GPU. Los elementos de prueba del analizador incluyen la salida incorrecta de nvidia-smi que interrumpió el ciclo el 12 de junio de 2026. La prueba de interrupción de hardware permanece local y no se incluye en la integración continua.

`pwsh -File .\verify.ps1 -Coverage` añade la medición de cobertura de líneas de `src/Watchdog` y falla si el resultado es inferior al 90 %. El sistema de integración continua (CI) lo ejecuta de esta manera y sube el informe a Codecov, que exige una cobertura de al menos el 90 % para todo el módulo y para cada cambio.

## Origen

Este es un extracto de un vigilante que ya se ejecutaba en una 5090. Los scripts de preextracción están congelados en [`origin/`](origin/) con SHA-256 fijas. Los incidentes con fecha (error de análisis, agujero de cinco semanas, ai-toolkit sin protección, 153 ABORTs vacíos, muerte de una muestra) se encuentran en [docs/incidents.md](docs/incidents.md).

## Licencia

MIT. Consulte [LICENSE](LICENSE). Compatible con: 1.x.

Creado por [MCP Tool Shop](https://mcp-tool-shop.github.io/).
