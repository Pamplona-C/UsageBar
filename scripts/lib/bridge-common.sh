#!/bin/bash
# A instalação e a remoção compartilham o quoting e as verificações dos arquivos que gerenciam.

usagebar_bridge_command() {
  case "$1" in
    *[!a-zA-Z0-9_./-]*)
      local remaining="$1"
      printf "'"
      while [[ "$remaining" == *"'"* ]]; do
        printf '%s' "${remaining%%\'*}"
        printf '%s' "'\\''"
        remaining="${remaining#*\'}"
      done
      printf "%s'" "$remaining"
      ;;
    *) printf '%s' "$1" ;;
  esac
}

usagebar_is_bridge_command() {
  local current="$1" path="$2" legacy="$2"
  [[ "$path" == *" "* ]] && legacy="\"$path\""
  [ "$current" = "$(usagebar_bridge_command "$path")" ] || [ "$current" = "$legacy" ]
}

usagebar_check_paths() {
  local path
  for path in "$settings" "$bridge" "$data_dir" "$data_dir/original-command" \
    "$data_dir/original-statusline.json" "$data_dir/settings-created"; do
    if [ -L "$path" ]; then
      echo "Erro: o UsageBar não altera links simbólicos: $path" >&2
      return 1
    fi
  done
}

usagebar_backup_settings() {
  # Sufixo aleatório evita sobrescrever um backup feito no mesmo segundo.
  backup="$(mktemp "$settings.bak-$(date +%Y%m%d-%H%M%S).XXXXXX")"
  cat "$settings" > "$backup"
  chmod 600 "$backup"
}
