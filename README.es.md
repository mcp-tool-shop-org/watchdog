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

# watchdog

**Un límite estricto para trabajos largos de GPU en Windows.** Watchdog comprueba la VRAM y la temperatura de su tarjeta NVIDIA, y la RAM de su sistema, cada 2 segundos. Cuando un límite se supera durante tres comprobaciones consecutivas, detiene los intérpretes de Python que le indicó que detuviera, y nada más.

Inicia una ejecución de entrenamiento o un renderizado grande, se aleja y una fuga de memoria, un lote demasiado grande o una tarjeta sobrecalentada lo convierten en un escritorio congelado. Watchdog es el pequeño proceso que permanece activo para usted: hace cumplir los límites que establece, registra lo que ve y le indica claramente cuándo no pudo protegerle.

## Lo que obtendrá

- **Límites que usted elige.** VRAM en MiB, RAM en porcentaje, temperatura de la GPU en °C. No hay valores predeterminados ocultos.
- **Detenciones dirigidas.** Solo se pueden detener las rutas de los intérpretes que liste (más un patrón de proceso WSL opcional). Todos los demás procesos de Python en la máquina se dejan intactos.
- **Sin falsas garantías.** Una violación que no coincida con ninguno de los procesos que haya listado se registra como una brecha de protección, y se indican los procesos que utilizan la VRAM.
- **Un watchdog para el watchdog.** Una tarea programada opcional comprueba la señal de actividad una vez por minuto y marca el watchdog como inactivo desde el exterior si se detuvo. Nunca reinicia nada por sí solo.
- **Una respuesta clara sobre su estado.** `watchdog status` devuelve 0 (en ejecución), 1 (no en ejecución) o 2 (fallo grave).
- **Un registro de cada ejecución.** Un archivo CSV de muestras, un registro de detenciones, una transcripción de la consola y un registro de fallos, todo almacenado en una carpeta que usted elija.
- **Liberación opcional de la memoria de WSL.** Si la caché de archivos de WSL satura la memoria de Windows, el sondeo puede eliminar esa caché. Nunca detiene un proceso y nunca inicia una distribución detenida.

## Inicio rápido

Requisitos: Windows, PowerShell 7.1 o posterior, y un controlador NVIDIA con `nvidia-smi` en `PATH`.

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill` es su consentimiento: watchdog no se iniciará sin él, ni sin `AllowKill = $true` en la configuración.
Para instalarlo como un módulo y agregar la comprobación externa:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## Cómo funciona

1. **Muestra.** Cada `IntervalSec` (2 segundos por defecto), lee la temperatura, la potencia y la VRAM de la GPU desde `nvidia-smi`, y la RAM del sistema desde Windows.
2. **Espere a un patrón, no a un pico.** Un límite debe superarse `BreachSamples` veces seguidas (3 por defecto) antes de que ocurra algo. Se registran las advertencias en el camino.
3. **Detenga solo lo que haya listado.** En caso de una violación sostenida, detiene los `python` procesos cuya ruta se encuentra en `Targets`, y ejecuta el patrón WSL `pkill` opcional. Registra lo que detuvo, o que no detuvo nada.
4. **Demuestre que está activo.** El bucle reescribe un archivo de señal de actividad en cada muestra. `watchdog status` y el sondeo programado evalúan el estado a partir de esa señal de actividad, por lo que un watchdog inactivo nunca puede parecer saludable.

## Comandos

| Comando | Lo que hace |
|---|---|
| `watchdog status` | Comprobación de estado. Devuelve 0 (en ejecución), 1 (no en ejecución) o 2 (fallo grave). |
| `watchdog start -AllowKill` | Detiene cualquier bucle antiguo de forma limpia, inicia uno nuevo en segundo plano y espera su señal de actividad. |
| `watchdog stop` | Solicita al bucle que se detenga a través de un archivo centinela y espera. |
| `watchdog poll` | Una comprobación externa, tal como la ejecuta la tarea programada. |
| `watchdog install` / `uninstall` | Copia o elimina el módulo. `install -Poll` también registra la comprobación programada. |
| `watchdog help` / `version` | Indicadores, códigos de salida y la versión. |

`start` se niega con el código de salida 3 si la VRAM ya supera su límite (utilice `-Force` solo si lo desea). `status -Hook` imprime un mensaje de Claude Code SessionStart y siempre devuelve 0, por lo que se informa de un watchdog inactivo sin interrumpir la sesión. Referencia completa: [handbook → Reference](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/).

## Configuración

Watchdog no se iniciará sin una configuración. Busca en `-ConfigPath`, luego en `$env:WATCHDOG_CONFIG`, luego en `./watchdog.config.psd1` y, finalmente, en `~/.watchdog/config.psd1`.

| Obligatorio | Significado |
|---|---|
| `Root` | Carpeta absoluta para la señal de actividad, los registros y los archivos centinela. Watchdog no escribe en ningún otro lugar. |
| `Targets` | Rutas absolutas de los intérpretes que puede detener. |
| `VramKillMiB` | Límite de VRAM en MiB. Para una tarjeta de 32 GB, `31200` deja aproximadamente 1,4 GB de margen. |
| `RamKillPct` | Límite de RAM del sistema en porcentaje. |
| `TempKillC` | Límite de temperatura de la GPU en °C. |

Si un trabajo supera el límite de VRAM en el uso normal, limite el trabajo (para ComfyUI, `--reserve-vram`) en lugar de aumentar el límite. Todos los demás ajustes, incluida la liberación de la caché de WSL, se encuentran en [handbook → Configuration](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/).

## Seguridad

- **Consentimiento primero.** Nunca se detiene nada sin `-AllowKill` o `AllowKill = $true`.
- **Tocado:** archivos en `Root`, la lista de procesos, contadores de la GPU; y, solo si los habilita, un patrón de WSL `pkill` y la eliminación de la caché de páginas de WSL.
- **No tocado:** sus árboles de código fuente, puntos de control, credenciales y la red. No se envía ninguna telemetría fuera de la máquina.
- **La única acción irreversible es la detención en sí.** Un trabajo detenido pierde todo lo que no haya guardado. Lo que se pierde y cómo recuperarlo se encuentra en [docs/compensators.md](docs/compensators.md).

Consulte [SECURITY.md](SECURITY.md) para informar sobre una vulnerabilidad.

## Plataforma

La versión 1 es solo para Windows: depende de PowerShell 7, `nvidia-smi`, los contadores de memoria de procesos de GPU de Windows y, opcionalmente, WSL. El soporte para Linux está previsto para una versión posterior.

## Desarrollo

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

Cada detención, inicio y llamada de tarea programada en las pruebas se simulan, por lo que ejecutarlas nunca toca procesos reales. Los scripts de preextracción se mantienen, con un hash fijo, en [`origin/`](origin/), y los incidentes que dieron forma al diseño se encuentran en [docs/incidents.md](docs/incidents.md).

## Licencia

MIT. Consulte [LICENSE](LICENSE).

Creado por [MCP Tool Shop](https://mcp-tool-shop.github.io/).
