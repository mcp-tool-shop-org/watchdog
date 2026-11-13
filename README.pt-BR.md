<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.md">English</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

# sentinela

Sentinela de VRAM/RAM/temperatura do Windows para GPUs NVIDIA. Ele faz uma amostragem a cada 2 segundos. Após 3 violações consecutivas, ele encerra **apenas** os interpretadores que você listou — e informa isso quando uma violação não causa nenhum efeito.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

Não crie manualmente uma verificação de "heartbeat". Não faça correspondência de processos com `_watchdog`. Esses dois erros são o que fazem com que uma sentinela inativa e uma sentinela ativa pareçam idênticas.

**A versão 1 é apenas para Windows** (PowerShell 7, nvidia-smi, contadores de memória de processo WDDM, WSL `pkill` opcional). O Linux é uma versão posterior.

## Instalação

PowerShell 7.1+. Clone, copie o arquivo de configuração de exemplo, edite-o e inicie:

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

Ou importe o módulo:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog` copia o módulo para o caminho do módulo CurrentUser.

## Configuração

Não há configuração padrão e nem lista de processos a serem encerrados por padrão. O módulo se recusa a iniciar sem uma configuração. Ordem de pesquisa: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Campos obrigatórios: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. Caminhos relativos são rejeitados. As gravações permanecem abaixo de `Root`.

`VramKillMiB = 31200` é o limite documentado para uma placa de 32 GB (~1,4 GB abaixo do limite WDDM de 32607 MiB). Não aumente esse valor para interromper as execuções do ComfyUI — em vez disso, defina um limite para o ComfyUI (`--reserve-vram`).

## Comandos

| Comando | O que ele faz |
|---|---|
| `watchdog status` | Verificação de atividade. A única verificação correta. |
| `watchdog start -AllowKill` | Parada do sentinela, espera, limpeza, lançamento independente, verificação do "heartbeat". |
| `watchdog stop` | PARE o sentinela, espere. Nunca faça correspondência de processos. |
| `watchdog poll` | Execução única: se o "heartbeat" estiver desatualizado, grave `_watchdog_DEAD` externamente. |
| `watchdog help` | Flags e códigos de saída |
| `watchdog version` | `1.0.0` |

Códigos de saída `status` / `poll`: **0** em execução · **1** sem "heartbeat" · **2** desatualizado. `start` também usa **3** (VRAM já acima do limite), **4** (o loop anterior não parou), **5** (sem "heartbeat" após o lançamento).

Em caso de status, `-Hook` emite JSON da Sessão Claude Code e sempre sai com código 0, para que uma sentinela inativa não interrompa o início da sessão.

## O que ele encerra

Apenas processos `python` cujo `Path` está em `Targets`, mais um padrão WSL `pkill -f` opcional (vazio = desativado). Outros programas Python são preservados. Uma violação que não corresponde a nada grava `_watchdog_NO_TARGET` — isso é uma **lacuna** de proteção, e não sucesso.

Consentimento: `-AllowKill` (ou `AllowKill = $true` na configuração). O verificador nunca encerra processos e nunca reinicia automaticamente; o reinício automático pode abortar um trabalho em andamento.

## Modelo de ameaças

- **Acessado:** arquivos em `Root` (heartbeat, CSV, logs de encerramento/console/travamento, sentinelas); lista de processos; contadores da GPU; pkill local WSL opcional.
- **Não acessado:** sua árvore de código-fonte, checkpoints, credenciais, a rede.
- **Permissões:** o usuário que o inicia pode encerrar os interpretadores configurados. Não há conta de serviço extra.
- **Nenhuma telemetria** sai da máquina. Sem segredos nos logs.
- **Ação irreversível:** ABORTAR. Consulte [docs/compensators.md](docs/compensators.md).

## Testes

```powershell
pwsh -File .\verify.ps1
```

32 testes unitários, sem GPU. Os casos de teste do analisador incluem a saída malformada do nvidia-smi que interrompeu o loop em 12 de junho de 2026. O teste de aborto de hardware permanece local e não é incluído nos testes automatizados (CI).

## Origem

Este é um trecho de uma sentinela que já estava em execução em uma 5090. Os scripts pré-extração estão congelados em [`origin/`](origin/) com hashes SHA-256. Incidentes datados (análise de travamento, lacuna de cinco semanas, ai-toolkit não protegido, 153 ABORTs vazios, morte em uma amostra) estão em [docs/incidents.md](docs/incidents.md).

## Licença

MIT. Consulte [LICENSE](LICENSE). Suportado: 1.x.

Criado por [MCP Tool Shop](https://mcp-tool-shop.github.io/).
