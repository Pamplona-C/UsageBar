# Popover com anéis e gráfico de tokens: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Objetivo:** trocar as barras do popover por dois anéis de "% livre" e acrescentar um card de tokens (total e
escritos) com gráfico de barras nos modos 5h e Semana, lendo os históricos locais do Claude Code.

**Arquitetura:** um módulo novo `Sources/UsageBar/Tokens/` com quatro peças independentes de UI: o parser de uma
linha do histórico, os baldes por minuto, o leitor incremental dos arquivos e o cálculo das barras de cada modo. Um
`TokenStore` (`@MainActor`, `ObservableObject`) roda o leitor fora da main thread e publica os baldes. O
`UsageStore` existente continua dono dos percentuais e só avisa o `TokenStore` quando o `state.json` muda.

**Tecnologia:** Swift 5.9+, SwiftUI, Swift Charts (do sistema), XCTest, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-29-popover-aneis-tokens-design.md`

## Restrições globais

- macOS 14 (Sonoma) ou superior; o CI roda macOS 15. Nenhuma API exclusiva do macOS 15+ sem `if #available`.
- Sem dependências de terceiros. Swift Charts é do sistema e pode ser usado.
- Sem Keychain, sem token OAuth, sem endpoints não documentados. Os históricos são só lidos, nunca escritos.
- Os tokens nunca alteram o percentual dos anéis, que continua vindo do servidor e do bridge.
- Textos em pt-BR. Cores: verde < 60%, amarelo 60–85%, vermelho > 85%, calculadas sobre o **usado** (`UsageLevel`).
- Total = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens`. Escritos =
  `output_tokens`.
- Commits pequenos, em português, no formato `tipo: descrição`. Sem linhas de atribuição ao Claude.
- `swift test` passando ao fim de cada tarefa.

## Foco da revisão

1. **Linha pela metade no fim do arquivo** (o Claude Code está gravando): não pode ser contada nem perdida. Deve ser
   lida na passada seguinte. Teste na Tarefa 3.
2. **Arquivo reescrito ou truncado** (tamanho menor que o deslocamento salvo): reler do início sem contar duas vezes
   o que já foi contado. Teste na Tarefa 3.
3. **Semana com virada de horário de verão ou fuso de meia hora** (`America/St_Johns`, −3:30): as barras de dia
   precisam começar na meia-noite local. Teste na Tarefa 4.
4. **Pasta `~/.claude/projects` inexistente ou vazia**: mostra "Nenhum uso do Claude Code neste período", não
   "Tokens indisponíveis". Teste na Tarefa 3.
5. **Evento fora do período** (antes da segunda 00:00 ou com data no futuro por relógio adiantado): não entra em
   nenhuma barra nem no total. Teste na Tarefa 4.

---

### Tarefa 1: Parser de uma linha do histórico

**Arquivos:**
- Criar: `Sources/UsageBar/Tokens/TranscriptLine.swift`
- Criar: `fixtures/transcript-sample.jsonl`
- Criar: `Tests/UsageBarTests/TranscriptLineTests.swift`

**Interfaces:**
- Produz:
  - `struct TokenCount: Codable, Equatable { var total: Int; var written: Int }`, com `static let zero` e
    `static func + (TokenCount, TokenCount) -> TokenCount`.
  - `struct TokenEvent: Equatable { let key: String; let date: Date; let count: TokenCount }`. `key` é
    `"\(message.id)|\(requestId)"`.
  - `enum TranscriptLine { static func parse(_ line: Data) -> TokenEvent? }`.

- [ ] **Passo 1: Criar a fixture anonimizada** `fixtures/transcript-sample.jsonl` com 6 linhas, no padrão das fixtures
  atuais (IDs zerados ou sequenciais, usuário "usuario"):
  1. resposta `msg_1`/`req_1` em `2026-10-29T12:05:30.000Z`, usage `2 / 27224 / 23410 / 331`
     (entrada / gravação de cache / leitura de cache / saída);
  2. a mesma resposta `msg_1`/`req_1` repetida (outro bloco de conteúdo, mesmo usage);
  3. resposta `msg_2`/`req_2` em `2026-10-29T12:40:00.000Z`, usage `10 / 0 / 50000 / 1200`;
  4. linha `<synthetic>` com tokens zerados;
  5. linha `{"type":"user",...}` sem `message.usage`;
  6. linha truncada (`{"type":"assistant","mess`).

- [ ] **Passo 2: Escrever os testes**

```swift
func testParsesUsageLine()          // linha 1 → key "msg_1|req_1", date 2026-10-29 12:05:30 UTC,
                                    // count TokenCount(total: 50967, written: 331)
func testIgnoresSyntheticLine()     // linha 4 → nil
func testIgnoresLineWithoutUsage()  // linha 5 → nil
func testIgnoresCorruptedLine()     // linha 6 → nil
func testMissingTokenFieldCountsAsZero() // usage só com output_tokens: 7 → TokenCount(total: 7, written: 7)
func testLineWithoutIdIsIgnored()   // sem message.id → nil (sem chave, não dá para deduplicar)
```

- [ ] **Passo 3: Rodar e ver falhar.** `swift test --filter TranscriptLineTests`. Esperado: erro de compilação, porque
  `TranscriptLine` não existe.

- [ ] **Passo 4: Implementar `TranscriptLine.parse`.** `Decodable` privado e tolerante com `container.lenient`
  (`UsageSnapshot.swift:76`). `timestamp` em ISO 8601 com fração: tirar a fração antes de `Date(_:strategy: .iso8601)`,
  como em `UsageReport.swift:131` (o macOS 14 e 15 rejeitam a fração). `requestId` ausente vira `""` na chave.

- [ ] **Passo 5: Rodar e ver passar.** `swift test --filter TranscriptLineTests`. Esperado: 6 testes passando.

- [ ] **Passo 6: Commit.** `git commit -m "feat: lê os tokens de uma linha do histórico do Claude Code"`

---

### Tarefa 2: Baldes por minuto

**Arquivos:**
- Criar: `Sources/UsageBar/Tokens/TokenBuckets.swift`
- Criar: `Tests/UsageBarTests/TokenBucketsTests.swift`

**Interfaces:**
- Consome: `TokenEvent`, `TokenCount` (Tarefa 1).
- Produz: `struct TokenBuckets: Equatable` com
  - `mutating func add(_ event: TokenEvent)`: ignora `event.key` já visto;
  - `func sum(from: Date, to: Date) -> TokenCount`: soma os baldes com início em `[from, to)`;
  - `mutating func prune(before: Date)`: descarta baldes e chaves vistas anteriores a `before`;
  - `var isEmpty: Bool`.
  - Balde = minuto em epoch (`Int(date.timeIntervalSince1970) / 60`). Chaves vistas: `[String: Int]` (chave → minuto),
    para o `prune` também limpar a deduplicação.

- [ ] **Passo 1: Escrever os testes**

```swift
func testDuplicateKeyIsCountedOnce()         // add(e) duas vezes → sum == e.count
func testSumUsesHalfOpenRange()              // eventos 9:19:59 e 9:20:00; sum(from: 9:20, to: 10:20) conta só o segundo
func testSumAcrossMinutes()                  // 3 eventos em minutos diferentes → soma dos três
func testPruneDropsOldBucketsAndKeys()       // eventos antes e depois de X; prune(before: X) → sum total só conta o
                                             // posterior, e a chave do anterior saiu das chaves vistas
func testAddBeforePruneLimitIsIgnored()      // depois de prune(before: X), add de evento anterior a X → sum inalterado
```

- [ ] **Passo 2: Rodar e ver falhar.** `swift test --filter TokenBucketsTests`. Esperado: erro de compilação.

- [ ] **Passo 3: Implementar `TokenBuckets`.** Guardar `pruneBefore: Date?`; `add` descarta eventos anteriores a ele.

- [ ] **Passo 4: Rodar e ver passar.** `swift test --filter TokenBucketsTests`. Esperado: 5 testes passando.

- [ ] **Passo 5: Commit.** `git commit -m "feat: agrega tokens por minuto com deduplicação"`

---

### Tarefa 3: Leitor incremental dos históricos

**Arquivos:**
- Criar: `Sources/UsageBar/Tokens/TranscriptScanner.swift`
- Criar: `Tests/UsageBarTests/TranscriptScannerTests.swift`

**Interfaces:**
- Consome: `TranscriptLine.parse`, `TokenBuckets` (Tarefas 1 e 2).
- Produz: `final class TranscriptScanner` (não isolada, usada de uma fila só) com
  - `init(root: URL = TranscriptScanner.defaultRoot)`; `static let defaultRoot` = `~/.claude/projects`;
  - `func scan(since: Date) throws -> TokenBuckets`: devolve uma cópia dos baldes acumulados, já com `prune(before: since)`.
  - Lança só quando `root` existe e não pode ser listada. `root` inexistente devolve baldes vazios.

- [ ] **Passo 1: Escrever os testes** (pasta temporária com a mesma estrutura: `proj/sessao.jsonl` e
  `proj/sessao/subagents/agent-1.jsonl`)

```swift
func testReadsSessionAndSubagentFiles()       // um evento em cada → sum = soma dos dois
func testSecondScanReadsOnlyAppendedLines()   // scan, acrescenta 1 linha, scan → só o novo evento soma a mais
func testPartialLastLineIsReadNextTime()      // grava linha sem "\n" → não conta; completa a linha → conta 1 vez
func testTruncatedFileIsReadAgainWithoutDoubleCount() // reescreve o arquivo menor com o mesmo evento → total igual
func testFilesModifiedBeforeSinceAreSkipped() // modificationDate antiga (setAttributes) → não lido
func testMissingRootReturnsEmpty()            // root inexistente → isEmpty, sem erro
```

- [ ] **Passo 2: Rodar e ver falhar.** `swift test --filter TranscriptScannerTests`. Esperado: erro de compilação.

- [ ] **Passo 3: Implementar `TranscriptScanner`.** `FileManager.enumerator` em `root` filtrando `.jsonl` e
  `contentModificationDate >= since`. Para cada arquivo, um estado `(fileID: inode, offset: UInt64)`: inode diferente
  ou tamanho menor que `offset` zera o `offset`. Ler de `offset` até o fim com `FileHandle`, consumir só até o último
  `\n` e avançar `offset` por esse total; o resto fica para a próxima passada. A deduplicação dos `TokenBuckets` evita
  contar duas vezes quando o arquivo é relido.

- [ ] **Passo 4: Rodar e ver passar.** `swift test --filter TranscriptScannerTests`. Esperado: 6 testes passando.

- [ ] **Passo 5: Medir nos dados reais.** Um teste temporário (não commitado), ou `swift run` com um `print`, que
  roda `scan(since:)` em `defaultRoot` com a segunda-feira 00:00 desta semana. Esperado: primeira passada em poucos
  segundos e a segunda em menos de 100 ms. Anotar os tempos no commit.

- [ ] **Passo 6: Commit.** `git commit -m "feat: lê os históricos do Claude Code de forma incremental"`

---

### Tarefa 4: Barras dos modos 5h e Semana

**Arquivos:**
- Criar: `Sources/UsageBar/Tokens/TokenChart.swift`
- Criar: `Tests/UsageBarTests/TokenChartTests.swift`

**Interfaces:**
- Consome: `TokenBuckets.sum` (Tarefa 2), `UsageWindow` (`Models/UsageSnapshot.swift:46`).
- Produz:
  - `enum TokenRange: String, CaseIterable { case fiveHour, week }`;
  - `struct TokenBar: Equatable, Identifiable { let start: Date; let end: Date; let count: TokenCount; let isFuture: Bool; let isCurrent: Bool }` (`id` = `start`);
  - `struct TokenChartData: Equatable { let bars: [TokenBar]; let total: TokenCount; let periodStart: Date; let isRolling: Bool }`;
  - `enum TokenChart { static func fiveHour(window: UsageWindow?, now: Date, buckets: TokenBuckets) -> TokenChartData; static func week(now: Date, calendar: Calendar, buckets: TokenBuckets) -> TokenChartData }`;
  - `static func earliestStart(window: UsageWindow?, now: Date, calendar: Calendar) -> Date`: o mais antigo entre o início
    da janela de 5h e a segunda 00:00. É o `since` do leitor.

Regras (do spec): modo 5h com janela atual conhecida (`resetsAt > now`) → 5 barras de 1h de `resetsAt − 5h` a
`resetsAt`, `isRolling = false`. Sem janela atual (nenhuma, ou `resetsAt <= now`) → 5 barras de 1h terminando em
`now`, `isRolling = true`. Modo Semana → 7 barras, de segunda 00:00 a domingo, cada uma do início do dia ao início do
dia seguinte pelo `calendar` (`firstWeekday = 2`). `total` soma de `periodStart` até `now`. `isFuture` = `start > now`;
`isCurrent` = `start <= now < end`.

- [ ] **Passo 1: Escrever os testes** (calendário `America/Sao_Paulo`, exceto onde indicado)

```swift
func testFiveHourBarsFollowTheWindow()       // reset 14:20, now 11:40 → starts 9:20, 10:20, 11:20, 12:20, 13:20;
                                             // isCurrent só na de 11:20; 12:20 e 13:20 isFuture; isRolling false
func testFiveHourTotalIsExactToTheMinute()   // evento 9:19 fica fora, 9:20 e 11:39 entram no total
func testPassedResetFallsBackToRollingHours() // reset 08:00, now 11:40 → isRolling true, última barra termina 11:40
func testNoWindowFallsBackToRollingHours()   // window nil → isRolling true
func testWeekStartsOnMondayLocalMidnight()   // now qua 29/10 15:00 → 7 barras, a primeira em seg 27/10 00:00 local;
                                             // qua isCurrent; qui a dom isFuture
func testWeekWithHalfHourTimeZone()          // calendário America/St_Johns → primeira barra na meia-noite local
func testWeekAcrossDaylightSavingChange()    // calendário America/New_York, semana de 02/11/2026: o domingo tem 25 h
func testEventsOutsidePeriodAreNotCounted()  // evento no domingo anterior e evento depois de now → fora do total
func testEarliestStartPicksTheOlderOne()     // segunda 00:00 vs reset − 5h numa segunda 02:00 → a mais antiga
```

- [ ] **Passo 2: Rodar e ver falhar.** `swift test --filter TokenChartTests`. Esperado: erro de compilação.

- [ ] **Passo 3: Implementar `TokenChart`.** Semana com `calendar.dateInterval(of: .weekOfYear, for: now)` sobre uma
  cópia com `firstWeekday = 2`, e dias com `calendar.date(byAdding: .day, ...)`, nunca somando 86.400 s.

- [ ] **Passo 4: Rodar e ver passar.** `swift test --filter TokenChartTests`. Esperado: 9 testes passando.

- [ ] **Passo 5: Commit.** `git commit -m "feat: calcula as barras de tokens dos modos 5h e semana"`

---

### Tarefa 5: `TokenStore` e ligação com o `UsageStore`

**Arquivos:**
- Criar: `Sources/UsageBar/Tokens/TokenStore.swift`
- Modificar: `Sources/UsageBar/UsageStore.swift` (método `reload()` e `init`)
- Modificar: `Sources/UsageBar/UsageBarApp.swift`
- Criar: `Tests/UsageBarTests/TokenStoreTests.swift`

**Interfaces:**
- Consome: `TranscriptScanner`, `TokenChart.earliestStart` (Tarefas 3 e 4).
- Produz: `@MainActor final class TokenStore: ObservableObject` com
  - `enum Status: Equatable { case loading, ready(TokenBuckets), failed(String) }`;
  - `@Published private(set) var status: Status = .loading`;
  - `init(scan: @escaping @Sendable (Date) throws -> TokenBuckets = { try sharedScanner.scan(since: $0) })`, em que
    o leitor padrão roda numa fila serial própria;
  - `func refresh(window: UsageWindow?, force: Bool = false)`: sem `force`, respeita `static let throttle: TimeInterval = 30`;
    calcula `since` com `TokenChart.earliestStart(window:now:calendar: .current)` e roda `scan` fora da main thread.
- `UsageStore` ganha `let tokens: TokenStore` (injetável no `init` para os testes) e chama
  `tokens.refresh(window: state.fiveHour)` no fim de `reload()`. O timer de 30 s já chama `reload()`, o que cobre
  o "a cada 5 min" do spec com folga.

- [ ] **Passo 1: Escrever os testes**

```swift
func testRefreshPublishesBuckets()       // scan devolve baldes com 1 evento → status == .ready(baldes)
func testScanErrorBecomesFailed()        // scan lança → status == .failed(mensagem não vazia)
func testRefreshIsThrottled()            // dois refresh seguidos sem force → scan chamado 1 vez
func testForceIgnoresThrottle()          // refresh + refresh(force: true) → scan chamado 2 vezes
```

- [ ] **Passo 2: Rodar e ver falhar.** `swift test --filter TokenStoreTests`. Esperado: erro de compilação.

- [ ] **Passo 3: Implementar `TokenStore`** e a chamada em `UsageStore.reload()`. Em `UsageBarApp`, nada muda além de
  o `UsageStore` já trazer o `tokens`.

- [ ] **Passo 4: Rodar a suíte inteira.** `swift test`. Esperado: todos passando, incluindo os `UsageStoreTests`
  antigos (que recebem um `TokenStore` com `scan` falso).

- [ ] **Passo 5: Commit.** `git commit -m "feat: atualiza os tokens em segundo plano junto com o uso"`

---

### Tarefa 6: Textos novos

**Arquivos:**
- Modificar: `Sources/UsageBar/Formatting.swift`
- Modificar: `Tests/UsageBarTests/FormattingTests.swift`

**Interfaces:**
- Produz:
  - `static func tokens(_ value: Int) -> String`;
  - `static func resetShort(_ date: Date, now: Date, calendar: Calendar = .current) -> String`: texto abaixo do anel.

- [ ] **Passo 1: Escrever os testes**

```swift
func testTokens() {
    XCTAssertEqual(Format.tokens(0), "0")
    XCTAssertEqual(Format.tokens(950), "950")
    XCTAssertEqual(Format.tokens(1_234), "1,2 mil")
    XCTAssertEqual(Format.tokens(222_566), "223 mil")
    XCTAssertEqual(Format.tokens(1_600_000), "1,6M")
    XCTAssertEqual(Format.tokens(43_666_000), "43,7M")
    XCTAssertEqual(Format.tokens(312_000_000), "312M")
    XCTAssertEqual(Format.tokens(1_250_000_000), "1,3 bi")
}
func testResetShort() {
    // now 11:40: reset 14:20 → "reinicia em 2h40"; reset 11:55 → "reinicia em 15 min";
    // amanhã 19:00 → "reinicia amanhã 19:00"; sábado 19:00 → "reinicia sábado 19:00";
    // reset já passou → "janela reiniciada"
}
```

- [ ] **Passo 2: Rodar e ver falhar.** `swift test --filter FormattingTests`. Esperado: erro de compilação.

- [ ] **Passo 3: Implementar.** Uma casa decimal abaixo de 10 da unidade, inteiro a partir de 10; vírgula decimal.
  Em `resetShort`, menos de 24 h e no mesmo dia → relativo ("em 2h40", "em 15 min"); senão, reaproveitar a lógica de
  `reset` sem o "às".

- [ ] **Passo 4: Rodar e ver passar.** `swift test --filter FormattingTests`. Esperado: passando.

- [ ] **Passo 5: Commit.** `git commit -m "feat: formata tokens e reset curto para o popover"`

---

### Tarefa 7: Novo popover

**Arquivos:**
- Criar: `Sources/UsageBar/Views/UsageRing.swift`
- Criar: `Sources/UsageBar/Views/TokenCard.swift`
- Modificar: `Sources/UsageBar/Views/UsagePopover.swift` (trocar `WindowRow` e `UsageBarView` pelos anéis)

**Interfaces:**
- Consome: `UsageStore.tokens`, `TokenStore.status`, `TokenChart`, `TokenRange`, `Format.tokens`, `Format.resetShort`,
  `UsageLevel.color`.
- Produz: `struct UsageRing: View { let title: String; let window: UsageWindow?; let now: Date }` e
  `struct TokenCard: View { @ObservedObject var tokens: TokenStore; let window: UsageWindow?; let now: Date }`.

Layout aprovado (spec, seção "Layout"): cabeçalho "Claude Code" com "atualizado …" e o botão de atualizar; dois anéis
de 92 pt lado a lado com "NN%" e "livre" no centro, nome e `resetShort` embaixo; card "Tokens" com o seletor
`Picker(.segmented)` "5h | Semana" (`@AppStorage("tokenRange")`), "total" e "escritos" lado a lado, gráfico Swift
Charts (`BarMark`, altura = `count.written`, barras futuras em `.quaternary`, a atual em destaque, `RuleMark` tracejado
no "agora" no modo 5h), rótulos ("9:20" e "reset 14:20", ou "últimas 5h"; "seg … dom"), a linha do período ("desde
9:20", "desde seg 00:00") e "Só o Claude Code deste Mac". Mouse sobre a barra (`chartXSelection`, macOS 14) mostra os
escritos e o total daquela barra. `.help` do card: "Tokens só do Claude Code neste Mac. O percentual dos anéis vem do
servidor e inclui o uso na web e em outros computadores." Estados: `.loading` → `ProgressView` pequeno;
`.failed` → "Tokens indisponíveis" com o motivo em `.help`; total zero → "Nenhum uso do Claude Code neste período".
Os estados atuais do popover (sem dados, consultando, dados antigos, erro do servidor) continuam. Largura de 300 pt.
Cores do sistema, para o modo escuro funcionar sozinho. `onAppear` chama `store.tokens.refresh(window:force: true)`.

- [ ] **Passo 1: Implementar `UsageRing`, `TokenCard` e o novo `UsagePopover`.**

- [ ] **Passo 2: Compilar e testar.** `swift build && swift test`. Esperado: build sem avisos novos e todos os testes
  passando.

- [ ] **Passo 3: Ver no app de verdade.** `./build-app.sh`, abrir o popover nos modos claro e escuro e nos dois modos do
  seletor; tirar um print de cada. Conferir com o mockup aprovado e com a soma real das últimas 5h. Esperado: popover
  abre sem espera perceptível e os números batem com a soma manual (`python3` usado na conversa de design).

- [ ] **Passo 4: Commit.** `git commit -m "feat: novo popover com anéis de uso livre e gráfico de tokens"`

---

### Tarefa 8: Documentação

**Arquivos:**
- Modificar: `CLAUDE.md` (nova "Fase 6 — Popover com anéis e tokens"; tirar "histórico e gráficos" de "Fora de escopo";
  incluir `Tokens/` e `fixtures/transcript-sample.jsonl` na estrutura)
- Criar: `docs/transcripts.md` (campos usados, deduplicação, `<synthetic>`, subagentes, leitura incremental, e que o
  formato não é contrato documentado)
- Modificar: `README.md` (seção "Como funciona" com a terceira fonte; novo print)
- Modificar: `docs/popover.png` (print novo, modo claro, modo 5h)

- [ ] **Passo 1: Atualizar os quatro arquivos.**

- [ ] **Passo 2: Conferir.** `swift test` passando e `git diff --stat` só com esses arquivos.

- [ ] **Passo 3: Commit.** `git commit -m "docs: documenta a leitura dos históricos e o novo popover"`
