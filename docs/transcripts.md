# Tokens: históricos locais do Claude Code

O card de tokens do popover soma os tokens que o Claude Code registra nos históricos das sessões. Nenhuma fonte
documentada traz tokens da conta: o `usage_report` e a statusline só têm percentuais (e, na statusline, os tokens da
sessão atual). Por isso os números cobrem **só o Claude Code deste Mac**: o uso no claude.ai e em outros
computadores fica de fora, e os tokens nunca alteram o percentual dos anéis.

O formato desses arquivos não é um contrato documentado. O parser é tolerante: linha ilegível ou sem os campos é
ignorada, e se a leitura inteira falhar o card mostra "Tokens indisponíveis" e o resto do popover segue normal.
O app só lê esses arquivos, nunca escreve neles.

## Arquivos

Observado em 29/10/2026, com o Claude Code 2.1.30x:

- Sessões: `~/.claude/projects/<projeto>/<sessão>.jsonl`.
- Subagentes: `~/.claude/projects/<projeto>/<sessão>/subagents/agent-*.jsonl`.

Os dois entram na conta. Uma linha JSON por evento.

## Campos usados

| Campo | Uso |
|---|---|
| `timestamp` | ISO 8601 em UTC, com fração de segundos. A fração sai antes do parse (o macOS 14 e 15 rejeitam a data com ela). |
| `message.id` + `requestId` | Chave da resposta, para deduplicar. |
| `message.model` | `<synthetic>` marca mensagens locais (como a do `/usage`), com tokens zerados: ignoradas. |
| `message.usage.input_tokens` | Entra no total. |
| `message.usage.cache_creation_input_tokens` | Entra no total. |
| `message.usage.cache_read_input_tokens` | Entra no total. |
| `message.usage.output_tokens` | Entra no total e é o número "escritos" (já inclui o raciocínio). |

Campo ausente conta como zero. Linha sem `message.id` é ignorada, porque não dá para deduplicar.

**Deduplicação:** a mesma resposta aparece em várias linhas, uma por bloco de conteúdo, com o mesmo `usage`. Na
amostra desta máquina, 8.912 de 16.944 linhas com `usage` eram repetidas. Cada chave conta uma vez.

**Total e escritos:** o total é dominado pela leitura de cache (o mesmo contexto relido a cada resposta, cerca de
98% do total), por isso a altura das barras usa os tokens escritos.

## Leitura

- `TranscriptScanner` lê só os arquivos modificados a partir do início do período mais longo exibido (o mais antigo
  entre a segunda 00:00 e o início da janela de 5h).
- Leitura incremental: para cada arquivo, guarda o inode e o deslocamento já lido, e na próxima passada lê só o que
  foi acrescentado. Consome até o último `\n`; uma linha pela metade fica para a próxima passada. Arquivo com outro
  inode ou menor que o deslocamento é relido do início, e a deduplicação evita contar de novo.
- `TokenBuckets` guarda os tokens por minuto. A janela de 5h começa em qualquer minuto e a meia-noite local pode cair
  em qualquer deslocamento de fuso.
- A leitura roda numa fila serial, fora da main thread, quando o app abre, a cada vez que o `state.json` muda ou o
  timer de 30 s dispara (no máximo uma vez a cada 30 s) e sempre que o popover abre.
- Medido nesta máquina (~400 MB de histórico, semana atual): primeira passada 0,27 s, seguintes 8 ms.

## Barras

- **Modo 5h:** cinco barras de 1h alinhadas à janela (com reset às 14:20, a primeira é 9:20–10:20). Sem janela atual
  conhecida (nenhuma ainda, ou o reset já passou), mostra as últimas 5 horas corridas.
- **Modo Semana:** segunda a domingo da semana atual, pelo calendário local. Essa semana não coincide com a janela
  semanal do servidor, que tem o próprio reset.

Fixture: `fixtures/transcript-sample.jsonl` (anonimizada), com uma resposta repetida, uma linha `<synthetic>`, uma
sem `usage` e uma truncada.
