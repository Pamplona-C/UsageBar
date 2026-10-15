# UsageBar

App de barra de menu do macOS que mostra o consumo dos limites do Claude Code: o percentual da janela de 5 horas
no label, com uma bolinha na cor do limite semanal, e os detalhes de cada janela ao clicar.

<img src="docs/popover.png" width="280" alt="Popover do UsageBar com a janela de 5h em 19% e a semanal em 50%">

Cores: verde abaixo de 60%, amarelo de 60% a 85%, vermelho acima de 85%.

## Como funciona

O Claude Code envia um JSON com os dados de uso para o comando da statusline. O UsageBar instala um bridge
nesse caminho:

```
Claude Code ──stdin JSON──> ~/.claude/usagebar-bridge.sh ──grava──> ~/.claude/usagebar/state.json
                                     │                                        │
                                     └─ repassa ao statusline original         └─ o app observa e atualiza
```

- A sua statusline atual continua aparecendo: o bridge repassa os mesmos dados para ela.
- O app não lê o Keychain, não usa token e não acessa a rede. Só lê `~/.claude/usagebar/state.json`.
- Os dados de uso só existem para assinantes Pro e Max, e só depois da primeira resposta em cada sessão.
  Detalhes do formato em [`docs/payload.md`](docs/payload.md).

## Requisitos

- macOS 14 (Sonoma) ou superior.
- Xcode ou Command Line Tools com Swift 5.9 ou superior.

## Instalação

```bash
./build-app.sh
```

Compila em release, gera `UsageBar.app` assinado ad-hoc, instala em `~/Applications` e abre o app. Rodar de novo
substitui a versão instalada. Use `--no-open` para só instalar.

Depois, configure a statusline de um destes jeitos:

- **Pelo app:** clique no label → **Configurações** → **Configurar statusline…**
- **Pelo terminal:** `scripts/install-bridge.sh`

Os dois fazem o mesmo: criam um backup `~/.claude/settings.json.bak-AAAAMMDD-HHMMSS`, guardam a statusline atual
em `~/.claude/usagebar/` e apontam `statusLine.command` para o bridge. Rodar duas vezes não duplica nada.

Para abrir junto com o Mac: **Configurações** → **Abrir ao iniciar sessão**. Se o macOS pedir, aprove o UsageBar em
Ajustes do Sistema → Geral → Itens de Início.

## Gatekeeper

O app é assinado ad-hoc, sem Developer ID. Compilado na própria máquina, ele não recebe o atributo de quarentena e
abre direto. Se você copiar o `.app` de outro Mac ou baixar de algum lugar, o macOS vai bloquear. Para liberar:

- **Ajustes do Sistema** → **Privacidade e Segurança** → **Abrir Mesmo Assim**, depois de tentar abrir uma vez; ou
- no terminal: `xattr -dr com.apple.quarantine ~/Applications/UsageBar.app`

Cada recompilação gera uma assinatura nova. Se "Abrir ao iniciar sessão" parar de funcionar depois de recompilar,
desligue e ligue a opção de novo.

## Desinstalação

1. Remova o bridge **antes** de apagar o app: **Configurações** → **Remover bridge…**, ou
   `scripts/uninstall-bridge.sh`. O `statusLine` original volta ao `settings.json` (com backup antes).
2. Desligue **Abrir ao iniciar sessão** e clique em **Sair**.
3. Apague os arquivos:

   ```bash
   rm -rf ~/Applications/UsageBar.app ~/.claude/usagebar
   defaults delete com.gustavopamplona.UsageBar
   ```

Os backups `~/.claude/settings.json.bak-*` ficam; apague quando não precisar mais.

## Desenvolvimento

```bash
swift test   # parser, regra de combinação entre sessões, formatação e scripts do bridge
swift run    # abre o app sem empacotar (também fica fora do Dock)
```

Os testes dos scripts rodam contra um `~/.claude` falso (variável `USAGEBAR_CLAUDE_DIR`) e nunca tocam no seu
`settings.json`.
