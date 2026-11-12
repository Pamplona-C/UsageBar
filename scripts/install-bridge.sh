#!/bin/bash
# Instala o bridge do UsageBar na statusline do Claude Code. Idempotente: rodar de novo só atualiza o bridge.
# Uso: install-bridge.sh [--yes]
#   --yes  não pergunta antes de alterar o settings.json (o app já confirmou com você)
set -euo pipefail
umask 077

claude_dir="${USAGEBAR_CLAUDE_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
bridge="$claude_dir/usagebar-bridge.sh"
data_dir="$claude_dir/usagebar"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$script_dir/lib/bridge-common.sh"
usagebar_check_paths

json() { osascript -l JavaScript "$script_dir/lib/statusline-json.js" "$@"; }

bridge_command="$(usagebar_bridge_command "$bridge")"

install_bridge_file() {
  mkdir -p "$data_dir"
  chmod 700 "$data_dir"
  cp "$script_dir/usagebar-bridge.sh" "$bridge"
  chmod 700 "$bridge"
}

current_command="$(json get-command "$settings")"

if [ "$current_command" = "$bridge_command" ]; then
  install_bridge_file
  echo "O bridge já está instalado. settings.json não foi alterado."
  exit 0
fi

updating_existing=false
if usagebar_is_bridge_command "$current_command" "$bridge"; then
  updating_existing=true
fi

echo "Isto vai:"
if [ -f "$settings" ]; then
  echo "  1. criar um backup privado $settings.bak-…"
else
  echo "  1. criar $settings (ainda não existe)"
fi
echo "  2. preservar a statusline original sem exibir o comando"
echo "  3. apontar statusLine.command para $bridge_command"
echo "A statusline atual continua aparecendo: o bridge repassa os dados para ela."

if [ "${1:-}" != "--yes" ]; then
  read -r -p "Continuar? [s/N] " answer || answer=""
  if [[ ! "$answer" =~ ^[sS] ]]; then
    echo "Cancelado. Nada foi alterado."
    exit 1
  fi
fi

if [ -f "$settings" ]; then
  usagebar_backup_settings
  rm -f "$data_dir/settings-created"
else
  mkdir -p "$data_dir"
  touch "$data_dir/settings-created"
fi

# O bridge e a statusline original ficam prontos antes de o settings.json apontar para eles.
install_bridge_file
if [ "$updating_existing" = false ]; then
  json get "$settings" > "$data_dir/original-statusline.json"
  printf '%s' "$current_command" > "$data_dir/original-command"
fi
json point-to "$settings" "$bridge_command"
chmod 600 "$settings" "$data_dir/original-statusline.json" "$data_dir/original-command"

if [ "$(json get-command "$settings")" != "$bridge_command" ]; then
  echo "Erro: o settings.json não ficou apontando para o bridge. Restaure a partir do backup settings.json.bak-…." >&2
  exit 1
fi
echo "Pronto. O UsageBar recebe os dados na próxima atualização da statusline do Claude Code."
