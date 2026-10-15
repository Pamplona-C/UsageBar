# Payload da statusline do Claude Code

Mapeamento baseado em capturas reais (Fase 0) e conferido com a
[documentação oficial da statusline](https://code.claude.com/docs/en/statusline).

- **Captura:** 15/10/2026, 26 payloads de 2 sessões simultâneas, Claude Code 2.1.300 e 2.1.296, conta Max.
- **Fixture:** `fixtures/statusline-sample.json` é o último payload desta captura. Caminhos, `session_id`,
  `prompt_id` e `session_name` foram trocados por valores de exemplo; o resto é exatamente o que o Claude Code enviou.

## Campos de rate limit (os únicos que o app usa)

```json
"rate_limits": {
  "five_hour": { "used_percentage": 19, "resets_at": 1792086600 },
  "seven_day": { "used_percentage": 50, "resets_at": 1792274400 }
}
```

| Campo | Tipo JSON | Unidade | Observado |
|---|---|---|---|
| `rate_limits.five_hour.used_percentage` | number | percentual **0–100** (não 0–1) | inteiros (`16`…`19`); a doc mostra decimais (`23.5`) |
| `rate_limits.five_hour.resets_at` | number | **epoch Unix em segundos** | `1792086600` = 15/10/2026 14:50 (-03) |
| `rate_limits.seven_day.used_percentage` | number | percentual 0–100 | `48`, `50` |
| `rate_limits.seven_day.resets_at` | number | epoch Unix em segundos | `1792274400` = 17/10/2026 19:00 (-03) |

No Swift: `used_percentage` → `Double` (aceita inteiro e decimal); `resets_at` → `Date` via
`secondsSince1970`.

## Quando os campos faltam

Segundo a documentação (não observado na captura, que foi toda de uma conta Max já com respostas):

- `rate_limits` só existe para assinantes **Pro e Max** (ou atrás de um gateway com limite de gasto) e só **depois
  da primeira resposta da API** na sessão.
- Cada janela (`five_hour`, `seven_day`) pode faltar **independentemente**.
- O Claude Code **remove uma janela quando o `resets_at` dela passa**, e roda a statusline de novo nesse momento.
- Existe também `rate_limits.spend_limit` (só com gateway corporativo). Fora de escopo; o parser ignora.

Consequência para o modelo: tudo opcional, chaves desconhecidas ignoradas, e um campo com tipo inesperado vira `nil`
em vez de invalidar o payload inteiro.

## Quando a statusline roda

- A cada mudança na conversa (debounce de 300 ms), quando `refreshInterval` está configurado, quando uma janela de
  rate limit chega ao `resets_at` e quando o `command` muda.
- Se uma atualização nova chega com o script ainda rodando, o Claude Code **cancela** o script em andamento: o bridge
  precisa gravar o arquivo antes de qualquer trabalho demorado.

## Achado: sessões diferentes reportam valores diferentes

Na captura, duas sessões gravaram com segundos de diferença:

| Sessão | `five_hour.used_percentage` | `five_hour.resets_at` |
|---|---|---|
| ativa (UsageBar) | 16 → 19 | 1792086600 |
| parada (outro projeto) | 5 | 1792086600 |

O mesmo `resets_at` indica a mesma janela. A sessão parada repete o valor da **última resposta que ela recebeu**, que
é antigo. Como o bridge grava todas as sessões no mesmo `state.json`, a última gravação **não** é necessariamente a
mais recente em dados.

**Regra adotada no app** (o bridge continua sem parsing):

1. Para cada janela, se o `resets_at` recebido for mais novo (diferença acima de 5 min), é uma janela nova: o valor
   recebido substitui o atual.
2. Se for a mesma janela, fica o **maior** `used_percentage` (dentro de uma janela o uso só sobe).
3. "Atualizado há X min" só avança quando o payload recebido não é mais antigo que o que o app já tem.
4. Se o `resets_at` de uma janela já passou, a janela é exibida como reiniciada (0%).

## Outros campos de topo (não usados)

`session_id`, `session_name`, `prompt_id`, `transcript_path`, `cwd`, `scratchpad_dir`, `workspace`, `version`,
`model`, `effort`, `output_style`, `cost`, `context_window`, `exceeds_200k_tokens`, `prompt_cache`, `fast_mode`,
`thinking`, `rate_limits`.
