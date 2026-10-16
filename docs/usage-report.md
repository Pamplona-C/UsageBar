# Consulta ao servidor: `/usage` do Claude Code

O payload da statusline ([`payload.md`](payload.md)) só muda quando o Claude Code recebe uma resposta, então não mostra o
uso feito no claude.ai enquanto nenhuma sessão do Claude Code estiver ativa. Para trazer o uso real, o app roda o
comando `/usage` do próprio Claude Code, que consulta o servidor com o login do Claude Code.

O app não lê token, não lê o Keychain e não chama a API: ele só roda um comando documentado do `claude`.

## Comando

```
claude -p --safe-mode --no-session-persistence --output-format stream-json --verbose "/usage"
```

| Parte | Por quê |
|---|---|
| `-p` + `--output-format stream-json --verbose` | saída em JSON, uma mensagem por linha, que é onde vem o `usage_report` |
| `--safe-mode` | não carrega hooks, plugins, MCP nem a statusline; o login funciona normalmente. `--bare` não serve: ele não lê o login do claude.ai |
| `--no-session-persistence` | a consulta não vira uma sessão no histórico |
| `"/usage"` | comando local: não chama o modelo |

Roda com a pasta pessoal como diretório atual, sem stdin, com limite de 30 s. O app procura o `claude` em
`~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin` e `~/.bun/bin`; se não achar,
pergunta a `zsh -lc 'command -v claude'`, porque um app aberto pelo Finder não herda o PATH do terminal.

## Documentação

- [`SDKUsageReport`](https://code.claude.com/docs/en/agent-sdk/typescript#sdkusagereport): formato do relatório.
- [`SDKAssistantMessage`](https://code.claude.com/docs/en/agent-sdk/typescript#sdkassistantmessage): quando o campo
  `usage_report` vem.
- [CLI reference](https://code.claude.com/docs/en/cli-reference): `--safe-mode`, `--no-session-persistence`.

A documentação marca o tipo como **experimental: o formato pode mudar**. Por isso o parser é tolerante e, se a consulta
falhar, o app mostra o erro e continua com os dados do bridge.

## Captura

- **Data:** 16/10/2026, Claude Code 2.1.301, conta Max.
- **Fixture:** `fixtures/usage-report-sample.jsonl`, com as 3 linhas da saída (`system`, `assistant`, `result`).
  - Na linha `system`, ficaram só alguns campos; as listas de ferramentas, plugins e skills foram removidas.
  - `session_id`, `uuid` e `message.id` foram zerados; `cwd` virou `/Users/usuario`.
  - O texto do relatório foi cortado depois dos limites, porque a parte "What's contributing" lista plugins e skills
    da máquina.
  - O `usage_report` está exatamente como o Claude Code enviou.
- **Custo:** `total_cost_usd` 0, `num_turns` 0, todos os tokens 0. Cerca de 300 ms dentro do Claude Code e uns 8 s no
  total, quase tudo para ele iniciar.

## Campos usados

```json
"usage_report": {
  "rate_limits": {
    "limits": [
      { "kind": "session",    "group": "session", "percent": 25, "resets_at": "2026-10-16T14:20:00.138122+00:00", ... },
      { "kind": "weekly_all", "group": "weekly",  "percent": 56, "resets_at": "2026-10-17T22:00:00.138144+00:00", ... }
    ],
    "extra_usage": { ... }
  }
}
```

| Campo | Tipo JSON | Unidade | No app |
|---|---|---|---|
| `limits[].kind` | string | `session`, `weekly_all`, `weekly_scoped`… | `session` → janela de 5h, `weekly_all` → semanal; os outros são ignorados |
| `limits[].percent` | number | percentual **0–100** | `usedPercentage` |
| `limits[].resets_at` | string ou `null` | **ISO 8601** com microssegundos | `resetsAt`, truncado para segundos |

- A documentação manda classificar as linhas por `kind`, nunca pelo texto ou pela ordem.
- Os microssegundos do `resets_at` mudam a cada consulta (`.138122`, `.725105`): é o horário da requisição, não do
  reset. Truncado, fica igual ao `resets_at` da statusline (`1792160400`).
- `severity`, `is_active`, `scope`, `extra_usage` e `session` (custo local) não são usados. As cores seguem as faixas
  do app.

## Quando não vem

Pela documentação, o `usage_report` só vem quando a sessão usa login do claude.ai com tipo de plano conhecido (ou
escopo `user:profile`) e a conta não está em cobrança por uso. Com API key ou com um token de `claude setup-token`,
vem só o texto. `rate_limits` é `null` quando o Claude Code não consegue ler o uso do plano.

| Situação | Erro no app |
|---|---|
| `claude` não encontrado | Claude Code não encontrado. |
| Saída sem `usage_report` | O Claude Code não devolveu o relatório de uso. |
| `rate_limits` nulo | O Claude Code não conseguiu ler os limites do plano. |
| Sem linhas `session` nem `weekly_all` | O relatório de uso veio sem os limites de 5h e semanal. |
| `result` com `is_error`, ou código de saída diferente de 0 | o texto do erro, ou a última linha do stderr |
| Mais de 30 s | O Claude Code demorou demais para responder. |

## Quando consulta

- Ao abrir o app.
- A cada 5 min (o timer de 30 s confere).
- Ao abrir o popover, se a última tentativa tiver mais de 1 min.
- No botão de atualizar do popover e em **Atualizar agora**, nas Configurações.

## Combinação com o bridge

1. A leitura do servidor é a referência: substitui os valores conhecidos **mesmo quando é menor**, como depois de um
   reset de limite concedido pela Anthropic. Uma janela que não veio mantém o valor conhecido.
2. `serverCheckedAt` e o "atualizado há" recebem o **início** da consulta.
3. Um `state.json` gravado antes desse início é ignorado, porque o timer relê o mesmo arquivo a cada 30 s.
4. Payloads gravados depois seguem as regras entre sessões de [`payload.md`](payload.md): uma sessão parada continua
   ignorada, e uma resposta nova atualiza a barra na hora, sem esperar a próxima consulta.
