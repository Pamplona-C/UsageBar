# UsageBar — app de barra de menu do macOS para consumo do Claude Code

## Objetivo
App nativo para macOS que fica **apenas na barra de menu** (sem ícone no Dock, sem janela principal) e mostra o consumo dos limites do Claude Code:
- Label na barra: percentual da janela de 5h (ex.: `42%`) + indicador de cor do limite semanal.
- Popover ao clicar: janela de 5h e semanal (percentual, barra de progresso, horário de reset), "atualizado há X min", botões de Configurações e Sair.

## Stack e decisões fixas
- Swift 5.9+, SwiftUI, `MenuBarExtra` com `.menuBarExtraStyle(.window)`.
- macOS 14 (Sonoma) ou superior.
- Swift Package Manager (executável), **sem .xcodeproj**. Um script `build-app.sh` compila em release e empacota um `.app` com `Info.plist` contendo `LSUIElement = true`, instalando em `~/Applications`.
- Sem dependências de terceiros, a menos que eu aprove.

## Fontes de dados
Duas fontes. A consulta ao servidor é a referência; a statusline atualiza a barra a cada resposta entre uma consulta e outra.

### Consulta ao servidor: `/usage` do Claude Code (Fase 5, aprovada em 16/10/2026)
- A cada 5 min, ao abrir o popover e no botão de atualizar, o app roda `claude -p --safe-mode --no-session-persistence --output-format stream-json --verbose "/usage"` e lê o `usage_report` documentado no Agent SDK. Traz o uso real da conta, incluindo o da web, e não gasta limite.
- O app não lê token nem Keychain e não chama a API: quem fala com o servidor é o próprio Claude Code, com o login dele.
- O `usage_report` é marcado como experimental na documentação: parser tolerante e, se falhar, o app mostra o erro e segue com o bridge.
- Mapeamento e regra de combinação em `docs/usage-report.md`.

### Statusline do Claude Code
O Claude Code executa o comando configurado em `statusLine.command` (em `~/.claude/settings.json`), envia um JSON via **stdin** e exibe o **stdout** do comando como statusline. Esse JSON inclui informações de rate limit.

Fluxo:
```
Claude Code ──stdin JSON──> ~/.claude/usagebar-bridge.sh ──grava──> ~/.claude/usagebar/state.json
                                     │                                        │
                                     └─ repassa stdin ao statusline original   └─ app observa e atualiza a UI
```

### Regras do bridge
- Script bash mínimo. **Não faz parsing**: grava o stdin bruto em arquivo temporário e faz `mv` atômico para `state.json`. Quem interpreta o JSON é o app em Swift.
- Se já existir um `statusLine.command` configurado, o bridge **encadeia**: repassa o mesmo stdin ao comando original e devolve o stdout dele. Se não existir, imprime uma statusline simples.
- Nunca pode quebrar ou atrasar a statusline do Claude Code: falhas ao gravar são ignoradas silenciosamente.

## Restrições (não negociáveis)
- **Não** ler o Keychain, **não** usar token OAuth, **não** chamar endpoints não documentados da Anthropic.
- **Não** modificar `~/.claude/settings.json` sem antes criar um backup com timestamp (`settings.json.bak-YYYYMMDD-HHMMSS`) e me pedir confirmação.
- A instalação do bridge precisa ser idempotente (rodar duas vezes não duplica nada) e ter um desinstalador que restaura o `statusLine` original.
- Não inventar campos do JSON. O modelo `Codable` deve ser baseado em um payload real capturado (ver Fase 0), com todos os campos opcionais e tolerante a campos novos ou ausentes.

## Fases (entregar uma por vez e parar para eu validar)

### Fase 0 — Descobrir o payload real
1. Criar um script de captura temporário que salva o stdin em `fixtures/statusline-sample.json`.
2. Me dizer exatamente como apontá-lo no `settings.json` (com backup), eu uso o Claude Code uma vez e depois reverto.
3. Analisar o JSON capturado e me mostrar quais campos de rate limit existem, os tipos e as unidades (percentual 0–1 ou 0–100? reset em epoch ou ISO?).
**Critério de aceite:** fixture real salva e o mapeamento dos campos documentado em `docs/payload.md`.

### Fase 1 — Parser + testes
- `UsageSnapshot` (Codable) e um parser que lê `state.json`.
- Testes unitários (`swift test`) usando a fixture real, mais casos de JSON sem rate limits, JSON corrompido e arquivo inexistente.
**Critério de aceite:** `swift test` passando.

### Fase 2 — App de barra de menu
- `UsageStore` (ObservableObject) observando `~/.claude/usagebar/state.json` com `DispatchSource` de arquivo, e um timer leve de fallback a cada 30s.
- Label e popover conforme o objetivo. Estados vazios: "Sem dados ainda — use o Claude Code uma vez" e "Dados antigos (> 1h)".
- Cores: verde < 60%, amarelo 60–85%, vermelho > 85%.
**Critério de aceite:** o app abre via `swift run`, mostra os dados da fixture copiada para o caminho real e não aparece no Dock.

### Fase 3 — Bridge + instalação
- `scripts/usagebar-bridge.sh`, `scripts/install-bridge.sh` e `scripts/uninstall-bridge.sh`, seguindo as regras acima.
- Botão "Configurar statusline" nas Configurações do app que executa o mesmo fluxo, com confirmação.
**Critério de aceite:** instalar → usar o Claude Code → o label atualiza em poucos segundos; desinstalar → `settings.json` volta ao estado original.

### Fase 4 — Empacotamento
- `build-app.sh` gera `UsageBar.app` em `~/Applications`, assinado ad-hoc (`codesign --sign -`).
- Opção "Abrir ao iniciar sessão" via `SMAppService.mainApp`.
- README com instalação, como liberar no Gatekeeper e como desinstalar.

### Fase 5 — Consulta ao servidor
- `UsageReportClient` roda o `/usage` do Claude Code e lê o `usage_report`; a leitura substitui os valores do bridge.
- Botão de atualizar no popover e seção "Consulta ao servidor" nas Configurações.
**Critério de aceite:** usar o claude.ai na web → clicar em atualizar → o percentual sobe sem usar o Claude Code.

### Fase 6 — Popover com anéis e tokens (aprovada em 29/10/2026)
- Anéis com o percentual **livre** das janelas de 5h e semanal, no lugar das barras.
- Card de tokens (total e escritos) com gráfico de barras: modo 5h (uma barra por hora da janela) e modo Semana
  (segunda a domingo). Os tokens vêm dos históricos locais do Claude Code em `~/.claude/projects/` e cobrem só
  este Mac; nunca alteram o percentual. Regras em `docs/transcripts.md`.
- Design em `docs/superpowers/specs/2026-10-29-popover-aneis-tokens-design.md`.
**Critério de aceite:** os números do card batem com uma soma independente dos históricos.

## Fora de escopo (por enquanto)
Histórico do percentual e projeções, custo em R$/US$, múltiplas contas, notificações, Codex e outros CLIs.

## Como trabalhar comigo
- Antes de cada fase, apresente um plano curto (arquivos que vai criar ou alterar) e espere meu ok.
- Ao terminar uma fase, rode build e testes, mostre o resultado e pare.
- Na dúvida sobre o formato de um dado ou comportamento do Claude Code, pergunte ou verifique; não assuma.
- Commits pequenos, mensagens em português no formato `tipo: descrição` (feat, fix, test, chore, docs).

## Estrutura esperada
```
UsageBar/
├── CLAUDE.md
├── Package.swift
├── Sources/UsageBar/        # App, UsageStore, Views, Models, Tokens
├── Tests/UsageBarTests/
├── fixtures/statusline-sample.json
├── fixtures/usage-report-sample.jsonl
├── fixtures/transcript-sample.jsonl
├── scripts/                 # bridge, install, uninstall
├── docs/payload.md
├── docs/usage-report.md
├── docs/transcripts.md
├── build-app.sh
└── README.md
```
