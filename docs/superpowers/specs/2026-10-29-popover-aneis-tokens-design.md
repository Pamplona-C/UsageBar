# Popover com anéis e gráfico de tokens

Data: 29/10/2026. Status: aprovado pelo usuário em 29/10/2026.

## Intenção

Ao abrir o popover, o usuário quer responder duas perguntas na hora:

1. **Quanto ainda posso usar antes do reset?**
2. **Quantos tokens gastei até agora?**, e como esse gasto se distribui ao longo da janela de 5h e dos dias da semana.

O popover atual (duas barras finas com percentual usado) responde a primeira só de forma indireta e não responde a
segunda. O pedido do usuário foi "mais bonito, mais intuitivo"; as direções foram escolhidas sobre mockups (anéis da
direção A, gráfico de barras da direção B).

## Objetivos

- Mostrar o que **resta** em cada janela, em destaque, com o tempo até o reset.
- Mostrar tokens gastos em dois números lado a lado: **total** (com cache) e **escritos** (saída).
- Gráfico de barras de tokens com dois modos: **5h** (uma barra por hora da janela atual) e **Semana** (uma barra
  por dia, segunda a domingo).
- Visual nativo do macOS, em claro e escuro.

## Fora do objetivo

- Tokens do claude.ai na web e de outros computadores: não existem em nenhuma fonte local. O card avisa
  "Só o Claude Code deste Mac".
- Custo em R$/US$, múltiplas contas, notificações (continuam fora de escopo no `CLAUDE.md`).
- Projeção de onde o uso chega no reset (direção C): exigiria guardar o histórico do percentual; não foi escolhida.
- Mudar o label da barra de menu: continua percentual usado da janela de 5h + bolinha da semanal.

## Anti-objetivos (seria falha mesmo funcionando)

- O popover demorar para abrir ou a barra de menu travar enquanto os históricos são lidos.
- O número de tokens parecer o total da conta, ou contradizer o percentual sem explicação.
- Uma mudança no formato dos históricos derrubar o popover inteiro: os anéis precisam seguir funcionando.
- Quebrar qualquer restrição do `CLAUDE.md`: sem Keychain, sem token, sem chamar a API.

## Layout (aprovado sobre mockup)

Largura de ~300 pt (hoje 280; pode crescer o necessário para os dois anéis).

```
┌────────────────────────────────────┐
│ Claude Code      atualizado agora ↻│
│                                    │
│    ( 75% )            ( 44% )      │  anéis: % livre
│     livre              livre       │
│    5 horas            Semana       │
│  reinicia em 2h40  reinicia amanhã │
│                         19:00      │
│                                    │
│ ┌ Tokens            [5h | Semana] ┐│
│ │ 43,7M total      223 mil escritos││
│ │ ▆ █ ▅ ▁ ▁         (barras)       ││
│ │ 9:20               reset 14:20   ││
│ │ Só o Claude Code deste Mac       ││
│ └──────────────────────────────────┘│
│ [Configurações]              [Sair]│
└────────────────────────────────────┘
```

### Anéis

- Dois anéis lado a lado: **5 horas** e **Semana**.
- O preenchimento e o número central mostram o percentual **livre** (`100 − usado`), com a palavra "livre".
- A cor segue as faixas atuais (`UsageLevel`), calculadas sobre o **usado**: verde < 60%, amarelo 60–85%,
  vermelho > 85%.
- Abaixo de cada anel: o nome e o reset em forma relativa curta ("reinicia em 2h40", "reinicia amanhã 19:00"),
  reaproveitando `Format.reset` ou uma variante dele.
- Estados que já existem continuam: sem dados da janela, janela reiniciada, reset desconhecido, dados antigos (> 1h),
  "Sem dados ainda", "Consultando o servidor…", erro do servidor.

### Card de tokens

- Cabeçalho "Tokens" com um seletor segmentado **5h | Semana**. O app lembra o último modo (`UserDefaults`).
- Dois números lado a lado: **total** (entrada + gravação de cache + leitura de cache + saída) e **escritos**
  (saída, que já inclui o raciocínio). Formato compacto em pt-BR: "43,7M", "223 mil", "1,6M".
- Gráfico de barras, em que a altura da barra é **tokens escritos** (o total é dominado pela leitura de cache e
  deixaria as barras quase iguais).
  - **Modo 5h:** cinco barras de 1h **alinhadas à janela, não ao relógio**: com reset às 14:20, as barras são
    9:20–10:20, …, 13:20–14:20. Horas futuras ficam apagadas, uma linha tracejada marca "agora", e os rótulos são o
    início da janela e "reset HH:MM". Os números do cabeçalho somam exatamente do início da janela até agora, no
    minuto. *(minha decisão)*
  - **Modo Semana:** uma barra por dia, **segunda a domingo da semana atual** (calendário local, fuso do Mac). Hoje
    em destaque, dias futuros apagados, rótulos "seg … dom". Os números somam segunda 00:00 até agora.
    O usuário escolheu segunda a domingo sabendo que essa semana não coincide com a janela semanal do servidor.
- Abaixo do gráfico, uma linha diz o período coberto: "desde 9:20" no modo 5h, "desde seg 00:00" no modo Semana.
  O `.help` do card explica que os tokens são só do Claude Code deste Mac e que o percentual dos anéis vem do
  servidor, com o uso da web e de outros computadores. *(minha decisão)*
- Passar o mouse sobre uma barra mostra o valor exato (escritos e total) daquela hora ou dia.
- Sem janela de 5h atual conhecida, seja porque nenhum reset chegou ainda ou porque o último reset conhecido já
  passou e nenhuma leitura nova abriu a janela seguinte: o modo 5h mostra as **últimas 5 horas corridas**, em
  barras de 1h terminando agora, com o rótulo "últimas 5h" no lugar de "reset HH:MM". Assim o gráfico nunca mostra
  uma janela que já acabou ao lado de um anel em 100% livre. *(minha decisão)*
- Sem nenhum token no período: barras vazias e "Nenhum uso do Claude Code neste período".
- Leitura falhou: o card mostra "Tokens indisponíveis" com o motivo em `.help`; o resto do popover segue normal.

## Fonte dos tokens: históricos locais do Claude Code

Não existe fonte documentada com tokens da conta: o `usage_report` e a statusline só trazem percentuais e, na
statusline, os tokens da sessão atual. A contagem vem dos históricos que o Claude Code grava em
`~/.claude/projects/`.

Observado em 29/10/2026 (Claude Code 2.1.30x):

- Arquivos `~/.claude/projects/<projeto>/<sessão>.jsonl` e, para subagentes,
  `~/.claude/projects/<projeto>/<sessão>/subagents/agent-*.jsonl`. Os dois entram na conta.
- Uma linha JSON por evento. As que interessam têm `message.usage` com `input_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens` e `output_tokens`, além de `timestamp` (ISO 8601 UTC),
  `message.id`, `requestId` e `message.model`.
- A mesma resposta aparece em várias linhas (uma por bloco de conteúdo) com o mesmo `usage`: em 16.944 linhas com
  `usage`, 8.912 eram repetidas. **Deduplicar por (`message.id`, `requestId`)**.
- Há linhas com `message.model == "<synthetic>"` e tokens zerados (mensagens locais, como a do `/usage`). Ignorar.
- Tamanho atual: ~400 MB em 64 arquivos.

Regras de leitura:

- O formato não é documentado como contrato: parser tolerante, no mesmo estilo de `lenient` já usado no projeto.
  Linha ilegível ou sem os campos é ignorada, nunca derruba a leitura.
- Fixture anonimizada em `fixtures/`, com linhas repetidas, uma `<synthetic>` e uma de subagente, seguindo o
  padrão das fixtures atuais (IDs zerados, usuário "usuario").
- O app só lê esses arquivos; nunca escreve neles.

### Desempenho

- Nada de reler 400 MB a cada abertura. Só entram arquivos com data de modificação dentro do período mais longo
  exibido (a partir da segunda-feira 00:00 ou do início da janela de 5h, o que for mais antigo).
- Leitura incremental: para cada arquivo, guardar o deslocamento já lido e o tamanho; na próxima passada, ler só o
  que foi acrescentado. Se o arquivo encolheu ou mudou de identidade, reler do início.
- Agregação guardada por **minuto** (balde de 1 min, em epoch, com total e escritos). Os modos 5h e Semana são somas
  desses baldes: a janela de 5h pode começar em qualquer minuto e a meia-noite local pode cair em qualquer
  deslocamento de fuso (inclusive meia hora). Uma semana dá no máximo ~10 mil baldes. Baldes mais antigos que a
  segunda-feira 00:00 da semana atual e que as últimas 5h podem ser descartados. *(minha decisão)*
- Tudo fora da main thread; a UI recebe só o resultado agregado.
- Quando roda: ao abrir o app, ao abrir o popover, quando o `state.json` do bridge muda (sinal de que houve resposta
  nova) e no timer de 5 min que já existe. Com intervalo mínimo entre leituras, como o `serverThrottle`.
- Persistir o cache de deslocamentos e baldes entre aberturas do app é decisão do implementador; o requisito é
  abrir o popover sem espera perceptível.

## Restrições

- Todas as do `CLAUDE.md` continuam valendo: sem Keychain, sem token OAuth, sem endpoints não documentados, sem
  dependências de terceiros (Swift Charts é do sistema e pode ser usado).
- macOS 14+.
- Os anéis e o percentual continuam vindo das fontes atuais (servidor e bridge). Os tokens são informação à parte e
  nunca alteram o percentual.
- Testes com `swift test`, cobrindo o parser dos históricos (deduplicação, `<synthetic>`, linha corrompida,
  subagente), a agregação por hora e por dia (inclusive na virada de dia e com o fuso local) e a leitura incremental.
- O Mac do GitHub Actions roda macOS 15: nada de APIs que só existem no macOS 26 sem verificação de disponibilidade.

## Decisões do usuário

- Anéis (direção A) mostrando o percentual **livre**.
- Gráfico de barras de tokens (direção B), com seletor **5h | Semana**.
- Dois números lado a lado: total e escritos.
- Semana de **segunda a domingo**.
- Aceita que os tokens sejam só do Claude Code deste Mac.

## Decisões minhas (para conferir)

- Altura das barras em tokens **escritos** (anotada no mockup combinado, que o usuário aprovou).
- Card com o aviso "Só o Claude Code deste Mac".
- Modo escuro: o popover segue o tema do sistema.
- O app lembra o último modo do seletor.
- Sem janela de 5h atual conhecida (nenhuma ainda, ou a última já passou), o modo 5h mostra as últimas 5h corridas.
- Barras do modo 5h alinhadas à janela, e total exato no minuto, com agregação por minuto.
- Linha com o período coberto ("desde 9:20", "desde seg 00:00") e `.help` explicando por que tokens e percentual não
  batem.
- Mouse sobre a barra mostra o valor exato.
- O `CLAUDE.md` passa a registrar esta fase ("Fase 6 — Popover com anéis e tokens") e tira "histórico e gráficos"
  da lista de fora de escopo; o `README.md` e o `docs/popover.png` são atualizados no fim.

## Fica a cargo do implementador

- Estrutura de tipos e arquivos (por exemplo, um leitor de históricos separado do `UsageStore`).
- Swift Charts ou desenho próprio para barras e anéis.
- Formato e local do cache de leitura incremental.
- Detalhes de espaçamento, tipografia e animação, desde que fiquem nativos do macOS e iguais ao mockup aprovado.
