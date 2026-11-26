<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.md">English</a>
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

**Um limite máximo para tarefas longas de GPU no Windows.** O watchdog verifica a VRAM e a temperatura da sua placa NVIDIA e a RAM do seu sistema a cada 2 segundos. Quando um limite é ultrapassado por três verificações consecutivas, ele interrompe os interpretadores Python que você permitiu que ele interrompesse e nada mais.

Você inicia uma execução de treinamento ou uma renderização grande, se afasta e um vazamento de memória, um lote muito grande ou uma placa superaquecida transformam tudo em uma área de trabalho travada. O watchdog é o pequeno processo que permanece ativo para você: ele aplica os limites que você define, registra o que viu e informa claramente quando não conseguiu protegê-lo.

## O que você obtém

- **Limites que você escolhe.** VRAM em MiB, RAM em porcentagem, temperatura da GPU em °C. Não há valores padrão ocultos.
- **Interrupções direcionadas.** Apenas os caminhos dos interpretadores que você listar (mais um padrão de processo WSL opcional) podem ser interrompidos. Todos os outros processos Python na máquina são deixados intactos.
- **Sem falsas garantias.** Uma violação que não corresponde a nenhum dos seus processos listados é registrada como uma lacuna de proteção, e os processos que detêm a VRAM são nomeados.
- **Um watchdog para o watchdog.** Uma tarefa agendada opcional verifica o sinal de vida uma vez por minuto e marca o watchdog como inativo externamente, caso ele tenha parado. Ela nunca reinicia nada por conta própria.
- **Uma resposta clara sobre o status.** `watchdog status` retorna 0 (em execução), 1 (não em execução) ou 2 (falha grave).
- **Um registro de cada execução.** Um arquivo CSV de amostras, um registro de interrupções, uma transcrição do console e um registro de falhas, todos armazenados em uma única pasta que você escolher.
- **Retorno opcional de memória WSL.** Se o cache de arquivos do WSL sobrecarregar a memória do Windows, o verificador pode descartar esse cache. Ele nunca interrompe um processo e nunca inicia uma distribuição interrompida.

## Início rápido

Requisitos: Windows, PowerShell 7 ou mais recente e um driver NVIDIA com `nvidia-smi` em `PATH`.

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill` é o seu consentimento: o watchdog não será iniciado sem ele, ou sem `AllowKill = $true` na configuração.
Para instalá-lo como um módulo e adicionar a verificação externa:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## Como funciona

1. **Amostra.** A cada `IntervalSec` (2 s por padrão), ele lê a temperatura, a potência e a VRAM da GPU de `nvidia-smi` e a RAM do sistema do Windows.
2. **Aguarde por um padrão, não por um pico.** Um limite deve ser ultrapassado `BreachSamples` vezes consecutivas (3 por padrão) antes que qualquer coisa aconteça. Os avisos são registrados ao longo do caminho.
3. **Interrompa apenas o que você listou.** Em caso de violação contínua, ele interrompe os `python` processos cujo caminho está em `Targets` e executa o padrão WSL `pkill` opcional. Ele registra o que interrompeu ou que não interrompeu nada.
4. **Prove que está ativo.** O loop reescreve um arquivo de sinal de vida a cada amostra. `watchdog status` e o verificador agendado avaliam o status a partir desse sinal de vida, para que um watchdog inativo nunca pareça estar funcionando.

## Comandos

| Comando | O que ele faz |
|---|---|
| `watchdog status` | Verificação de status. Retorna 0 (em execução), 1 (não em execução) ou 2 (falha grave). |
| `watchdog start -AllowKill` | Interrompe qualquer loop antigo de forma limpa, inicia um novo em segundo plano e aguarda o seu sinal de vida. |
| `watchdog stop` | Solicita que o loop seja interrompido por meio de um arquivo sentinela e aguarda. |
| `watchdog poll` | Uma verificação externa, executada pela tarefa agendada. |
| `watchdog install` / `uninstall` | Copia ou remove o módulo. `install -Poll` também registra a verificação agendada. |
| `watchdog help` / `version` | Flags, códigos de saída e a versão. |

`start` recusa com o código de saída 3 se a VRAM já estiver acima do seu limite (use `-Force` apenas se você realmente quiser isso). `status -Hook` imprime uma mensagem do Claude Code SessionStart e sempre retorna 0, para que um watchdog inativo seja relatado sem interromper a sessão. Referência completa: [handbook → Reference](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/).

## Configuração

O watchdog não será iniciado sem uma configuração. Ele procura em `-ConfigPath`, depois em `$env:WATCHDOG_CONFIG`, depois em `./watchdog.config.psd1` e, finalmente, em `~/.watchdog/config.psd1`.

| Obrigatório | Significado |
|---|---|
| `Root` | Pasta absoluta para o arquivo de sinal de vida, logs e arquivos sentinela. O watchdog não grava em nenhum outro lugar. |
| `Targets` | Caminhos absolutos dos interpretadores que ele pode interromper. |
| `VramKillMiB` | Limite máximo de VRAM em MiB. Para uma placa de 32 GB, `31200` deixa cerca de 1,4 GB de margem. |
| `RamKillPct` | Limite máximo de RAM do sistema em porcentagem. |
| `TempKillC` | Limite máximo de temperatura da GPU em °C. |

Se uma tarefa ultrapassar o limite máximo de VRAM durante o uso normal, limite a tarefa (para ComfyUI, `--reserve-vram`) em vez de aumentar o limite. Todas as outras configurações, incluindo a liberação do cache WSL, estão em [handbook → Configuration](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/).

## Segurança

- **Consentimento primeiro.** Nada é interrompido sem `-AllowKill` ou `AllowKill = $true`.
- **Acessado:** arquivos em `Root`, a lista de processos, contadores da GPU; e, apenas se você habilitá-los, um padrão WSL `pkill` e a liberação da página de cache do WSL.
- **Não acessado:** suas árvores de código-fonte, pontos de verificação, credenciais e a rede. Nenhuma telemetria sai da máquina.
- **A única ação irreversível é a própria interrupção.** Uma tarefa interrompida perde tudo o que não foi salvo. O que é perdido e como se recuperar está em [docs/compensators.md](docs/compensators.md).

Consulte [SECURITY.md](SECURITY.md) para relatar uma vulnerabilidade.

## Plataforma

A versão 1 é apenas para Windows: ela depende de PowerShell 7, `nvidia-smi`, os contadores de memória de processo da GPU do Windows e, opcionalmente, do WSL. O suporte para Linux está planejado para uma versão posterior.

## Desenvolvimento

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

Cada interrupção, lançamento e chamada de tarefa agendada nos testes são simuladas, portanto, executá-los nunca afeta processos reais. Os scripts de pré-extração são mantidos, com hash fixo, em [`origin/`](origin/), e os incidentes que moldaram o design estão em [docs/incidents.md](docs/incidents.md).

## Licença

MIT. Consulte [LICENSE](LICENSE).

Criado por [MCP Tool Shop](https://mcp-tool-shop.github.io/).
