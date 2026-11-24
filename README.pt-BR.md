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

# sentinela

Sentinela VRAM/RAM/temperatura para GPUs NVIDIA no Windows. Ele faz uma leitura a cada 2 segundos. Após 3 violações consecutivas, ele encerra **apenas** os processos que você listou — e informa isso quando uma violação não causa nenhum efeito.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

Não crie manualmente uma verificação de "heartbeat". Não use correspondência de processos em `_watchdog`. Esses dois erros são o que fazem com que uma sentinela inativa e uma sentinela ativa pareçam idênticas.

**v1 é exclusivo para Windows** (PowerShell 7, nvidia-smi, contadores de memória de processo WDDM, WSL `pkill` e liberação do cache de arquivos WSL opcionais). O Linux é uma versão posterior.

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

Não há diretório raiz padrão nem lista de processos a serem encerrados por padrão. O módulo se recusa a iniciar sem uma configuração. Ordem de pesquisa: `-ConfigPath`, `$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Campos obrigatórios: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. Caminhos relativos são rejeitados. As gravações permanecem abaixo de `Root`.

`VramKillMiB = 31200` é o limite documentado para uma placa de 32 GB (~1,4 GB abaixo do limite de 32607 MiB WDDM). Não aumente esse valor para evitar que ComfyUI cause problemas — limite ComfyUI (`--reserve-vram`) em vez disso.

### Liberação do cache de arquivos WSL (opt-in, ativação explícita)

Com `WslCacheRelease = $true`, cada verificação lê a memória da VM WSL pelo lado do Windows (nunca acorda uma VM parada). Quando `vmmemWSL` está grande, ou a memória do Windows está sob pressão e `vmmemWSL` tem tamanho médio, o verificador descarta o cache de páginas do Linux em `WslDistro` (`echo 1 > /proc/sys/vm/drop_caches` como root, com tempo limite e cooldown). O `autoMemoryReclaim` do próprio WSL só dispara quando a VM está ociosa, e um mecanismo de contêiner em execução a mantém ocupada, de modo que downloads de imagens grandes podem deixar dezenas de GB de cache retidos em detrimento do Windows.

Nunca encerra um processo e nunca inicia uma distribuição que já foi interrompida: quando outra distribuição mantém a máquina virtual em execução enquanto `WslDistro` está interrompida, o watchdog não libera o cache e registra essa omissão. O arquivo de registro, `Root\_watchdog_wslcache.log`, registra um sinal de atividade a cada hora; cada operação de liberação de cache, com a quantidade de memória antes e depois; uma linha para cada sequência de omissões; e um `ALERT` que identifica os processos que consomem mais recursos, caso o Windows ainda esteja acima de `WslCacheAlertPct` após uma liberação. Os limites estão definidos no arquivo de configuração de exemplo.

## Comandos

| Comando | O que ele faz |
|---|---|
| `watchdog status` | Verificação de atividade. A única verificação correta. |
| `watchdog start -AllowKill` | Parada da sentinela, espera, limpeza, lançamento independente, verificação do "heartbeat". |
| `watchdog stop` | PARE a sentinela, espere. Nunca use correspondência de processos. |
| `watchdog poll` | Execução única: se o "heartbeat" estiver desatualizado, grave `_watchdog_DEAD` externamente. |
| `watchdog help` | Sinais e códigos de saída |
| `watchdog version` | `1.1.0` |

Códigos de saída `status` / `poll`: **0** em execução · **1** sem "heartbeat" · **2** desatualizado. `start` também usa **3** (VRAM já acima do limite), **4** (o loop anterior não parou), **5** (sem "heartbeat" após o lançamento).

`-Hook` no status emite o JSON do Claude Code SessionStart e sempre sai com 0, para que uma sentinela inativa não interrompa o início da sessão.

## O que ele encerra

Apenas os processos `python` cujo `Path` está em `Targets`, mais um padrão WSL `pkill -f` opcional (vazio = desativado). Outros processos Python são preservados. Uma violação que não corresponde a nada grava `_watchdog_NO_TARGET` — isso é uma **lacuna** de proteção, não um sucesso.

Consentimento: `-AllowKill` (ou `AllowKill = $true` na configuração). O verificador nunca encerra processos e nunca os reinicia automaticamente; o reinício automático pode abortar um trabalho em andamento.

## Modelo de ameaças

- **Acessado:** arquivos sob `Root` (heartbeat, CSV, logs de encerramento/console/falha, sentinelas); lista de processos; contadores da GPU; pkill local WSL opcional; liberação opcional do cache de páginas WSL (opt-in, nunca encerra processos).
- **Não acessado:** sua árvore de código-fonte, pontos de verificação, credenciais, a rede.
- **Permissões:** o usuário que o inicia pode encerrar os processos configurados. Não há conta de serviço extra.
- **Nenhuma telemetria** sai da máquina. Sem segredos nos logs.
- **Ação irreversível:** ABORT. Consulte [docs/compensators.md](docs/compensators.md).

## Testes

```powershell
pwsh -File .\verify.ps1
```

114 testes unitários, sem GPU. Os testes do analisador incluem a saída mal formatada do comando nvidia-smi, que interrompeu o ciclo em 12 de junho de 2026. O teste de interrupção de hardware permanece local e não é incluído nos testes de integração contínua.

`pwsh -File .\verify.ps1 -Coverage` adiciona a análise da cobertura de linhas do `src/Watchdog` e falha se o resultado for inferior a 90%. O sistema de integração contínua (CI) executa o teste dessa forma e envia o relatório para o Codecov, que exige uma cobertura de pelo menos 90% para todo o módulo e para cada alteração.

## Origem

Este é um trecho de uma sentinela que já estava em execução em uma 5090. Os scripts de pré-extração estão congelados em [`origin/`](origin/) com SHA-256 fixações. Incidentes datados (travamento do analisador, lacuna de cinco semanas, ai-toolkit não protegido, 153 ABORTs vazios, morte em uma amostra) estão em [docs/incidents.md](docs/incidents.md).

## Licença

MIT. Consulte [LICENSE](LICENSE). Suportado: 1.x.

Criado por [MCP Tool Shop](https://mcp-tool-shop.github.io/).
