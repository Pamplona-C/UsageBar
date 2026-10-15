#!/bin/bash
# Bridge do UsageBar: grava o JSON que o Claude Code envia à statusline e encadeia a statusline original.
# Instalado por install-bridge.sh em ~/.claude/usagebar-bridge.sh. Não faz parsing: quem lê o JSON é o app.

data_dir="$(dirname "${BASH_SOURCE[0]}")/usagebar"
payload="$(cat)"

# Gravação atômica para o app nunca ler um arquivo pela metade. Falhas são ignoradas:
# a statusline do Claude Code não pode quebrar por causa do UsageBar.
if [ -n "$payload" ]; then
  {
    tmp="$(mktemp "$data_dir/.state.XXXXXX")" &&
      printf '%s\n' "$payload" > "$tmp" &&
      mv -f "$tmp" "$data_dir/state.json" || rm -f "$tmp"
  } 2>/dev/null
fi

original="$(cat "$data_dir/original-command" 2>/dev/null)"
if [ -n "$original" ]; then
  printf '%s\n' "$payload" | /bin/sh -c "$original"
else
  printf '%s\n' "${PWD##*/}"
fi
