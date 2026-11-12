# Codex: conexão e limites

Integração adicionada em 12/11/2026, após a escolha da proposta **C — Símbolos como atalhos** em
[`prototypes/codex-connection/index.html`](prototypes/codex-connection/index.html).

## Interface

- Os símbolos de Claude e ChatGPT ficam no topo do popover; cada um seleciona um serviço.
- A barra de menu mostra Claude e Codex simultaneamente, cada um com seu símbolo, percentual usado da janela
  principal e bolinha na cor da segunda janela. Sem dados, mostra `--%`.
- A seleção alterna os detalhes do popover e é lembrada entre aberturas; os dois percentuais continuam na barra.
- O label completo é renderizado como uma imagem antes de passar ao `MenuBarExtra`: um label SwiftUI composto
  é reduzido pelo macOS a um único texto e uma única imagem. A correção foi conferida em um `MenuBarExtra` real,
  inspecionando o `NSStatusBarButton`, além das prévias em uma janela comum.
- Cada serviço mantém suas leituras, erros e cache separados.
- Sem uma conta disponível, o Codex mostra **Conectar Codex**, com o símbolo do ChatGPT.
- **Entrar com ChatGPT** abre o Terminal com `codex login`. O próprio Codex conduz o login e abre o navegador.
- Enquanto aguarda o login, o UsageBar confere a conexão a cada 10 s. Também há uma atualização manual.
- O login existente do Codex é reconhecido automaticamente.
- Em Configurações → Contas, **Desconectar** desativa o acompanhamento e apaga o cache do Codex no UsageBar.
  Não executa `codex logout`, pois isso encerraria o login usado também no Terminal e em outros clientes.
- Nesta etapa, o card de tokens permanece exclusivo do Claude. O Codex mostra apenas limites e resets reais;
  os tokens mostrados no HTML são ilustrativos, não uma promessa de contagem já implementada.

## Consulta documentada

Referência: [Codex App Server](https://learn.chatgpt.com/docs/app-server), seções Initialization e Rate limits.

O app inicia `codex app-server`, com transporte padrão stdin/stdout, e troca mensagens JSON-RPC, uma por linha:

1. `initialize`, com `clientInfo` identificando o UsageBar.
2. Aguarda a resposta e envia `initialized`.
3. `account/read`, com `refreshToken: false`, para reconhecer falta de login ou autenticação sem ChatGPT.
   O app usa apenas o tipo de conta e não persiste o email.
4. `account/rateLimits/read`, para obter os limites.
5. Fecha a conexão e encerra o processo.

Não cria threads ou turnos, não envia prompts, não lê tokens/Keychain e não acessa endpoints privados diretamente.
O Codex gerencia as credenciais e suas requisições. Há um prazo total de 30 s para as respostas JSON-RPC; um processo
que não responde é encerrado. Logs fora do JSON e notificações são ignorados.

A busca do executável cobre instalações nativas, Homebrew, npm, Bun, Cargo, versões do nvm, PATH e shell de login.
O diretório do executável entra no PATH do subprocesso: instalações npm via nvm precisam encontrar o `node` também
quando o UsageBar é aberto pelo Finder.

## Amostra real e mapeamento

Captura em 12/11/2026, Codex CLI **0.167.2**, login com ChatGPT:
[`../fixtures/codex-rate-limits-sample.json`](../fixtures/codex-rate-limits-sample.json).
A estrutura vem da captura; percentuais e resets foram substituídos por valores fictícios. Foram mantidos apenas
os snapshots e seus campos de limite/plano. Identificadores da conta, créditos e outros metadados foram omitidos. A captura não iniciou conversa nem autenticação nova.

| Campo | Uso |
|---|---|
| `rateLimitsByLimitId.codex` | Snapshot preferido; evita confundir cotas de outros modelos com a do Codex |
| `rateLimits` | Fallback para versões antigas, quando `limitId` é ausente ou `codex` |
| `primary.usedPercent`, `secondary.usedPercent` | Percentual usado, de 0 a 100 |
| `windowDurationMins` | Duração da janela em minutos; define o título do anel |
| `resetsAt` | Próximo reset, epoch Unix em segundos |
| `planType` | Metadado opcional do plano |

Nesta captura, as durações são 300 e 10.080 minutos (5 horas e semana). O app respeita o valor recebido, incluindo
outras durações e ausência de uma janela. Campos ilegíveis são descartados individualmente. Uma consulta com apenas
uma janela substitui o snapshot anterior inteiro, evitando manter uma segunda janela que a conta já não reporta.

## Cache e falhas

`CodexStore` usa `codexUsageState`, separado de `usageState` do Claude. Uma falha de rede mantém a última leitura;
falta de login remove dados antigos da conta. `codexEnabled` lembra a desconexão local e `selectedProvider` lembra
o serviço escolhido. Nenhum desses valores guarda credenciais.

A consulta roda ao abrir o app, ao selecionar/abrir o Codex com throttle de 1 min, manualmente e a cada 5 min.
Desconectar durante uma consulta invalida a resposta pendente, que não pode restaurar o cache.

Os testes usam um executável Codex falso: validam o handshake, os métodos enviados, login ausente, API key,
compatibilidade, timeout, parsing, separação dos caches e desconexão durante uma consulta. Não iniciam o Codex real.
