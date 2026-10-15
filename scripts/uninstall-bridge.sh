#!/bin/bash
# Remove o bridge do UsageBar e restaura o statusLine original do Claude Code. Idempotente.
# Uso: uninstall-bridge.sh [--yes]
#   --yes  não pergunta antes de alterar o settings.json (o app já confirmou com você)
set -euo pipefail

claude_dir="${USAGEBAR_CLAUDE_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
bridge="$claude_dir/usagebar-bridge.sh"
data_dir="$claude_dir/usagebar"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

json() { osascript -l JavaScript "$script_dir/lib/statusline-json.js" "$@"; }

bridge_command="$bridge"
[[ "$bridge" == *" "* ]] && bridge_command="\"$bridge\""

remove_bridge_files() {
  rm -f "$bridge" "$data_dir/original-statusline.json" "$data_dir/original-command" \
    "$data_dir/settings-created" "$data_dir"/.state.*
}

if [ "$(json get-command "$settings")" != "$bridge_command" ]; then
  remove_bridge_files
  echo "O statusLine não aponta para o bridge. settings.json não foi alterado."
  exit 0
fi

if [ ! -f "$data_dir/original-statusline.json" ]; then
  echo "Erro: statusline original não encontrada em $data_dir." >&2
  echo "Restaure o settings.json a partir de um backup $settings.bak-*." >&2
  exit 1
fi
original="$(cat "$data_dir/original-statusline.json")"

backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
echo "Isto vai:"
echo "  1. criar o backup $backup"
if [ "$original" = "null" ]; then
  echo "  2. remover o statusLine (não havia um antes do UsageBar)"
else
  echo "  2. restaurar o statusLine original: $(cat "$data_dir/original-command")"
fi

if [ "${1:-}" != "--yes" ]; then
  read -r -p "Continuar? [s/N] " answer || answer=""
  if [[ ! "$answer" =~ ^[sS] ]]; then
    echo "Cancelado. Nada foi alterado."
    exit 1
  fi
fi

cp -p "$settings" "$backup"
json restore "$settings" "$original"

# settings.json foi criado pelo instalador e voltou a ficar vazio: volta a não existir.
if [ -f "$data_dir/settings-created" ] && [ "$(cat "$settings")" = "{}" ]; then
  rm -f "$settings" "$backup"
fi

remove_bridge_files
echo "Pronto. Statusline original restaurada."
