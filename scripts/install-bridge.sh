#!/bin/bash
# Instala o bridge do UsageBar na statusline do Claude Code. Idempotente: rodar de novo só atualiza o bridge.
# Uso: install-bridge.sh [--yes]
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

install_bridge_file() {
  mkdir -p "$data_dir"
  cp "$script_dir/usagebar-bridge.sh" "$bridge"
  chmod 755 "$bridge"
}

current_command="$(json get-command "$settings")"

if [ "$current_command" = "$bridge_command" ]; then
  install_bridge_file
  echo "O bridge já está instalado. settings.json não foi alterado."
  exit 0
fi

backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
echo "Isto vai:"
if [ -f "$settings" ]; then
  echo "  1. criar o backup $backup"
else
  echo "  1. criar $settings (ainda não existe)"
fi
echo "  2. guardar a statusline atual: ${current_command:-(nenhuma)}"
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
  cp -p "$settings" "$backup"
  rm -f "$data_dir/settings-created"
else
  mkdir -p "$data_dir"
  touch "$data_dir/settings-created"
fi

# O bridge e a statusline original ficam prontos antes de o settings.json apontar para eles.
install_bridge_file
json get "$settings" > "$data_dir/original-statusline.json"
printf '%s' "$current_command" > "$data_dir/original-command"
json point-to "$settings" "$bridge_command"

if [ "$(json get-command "$settings")" != "$bridge_command" ]; then
  echo "Erro: o settings.json não ficou apontando para o bridge. Restaure com o backup $backup." >&2
  exit 1
fi
echo "Pronto. O UsageBar recebe os dados na próxima atualização da statusline do Claude Code."
