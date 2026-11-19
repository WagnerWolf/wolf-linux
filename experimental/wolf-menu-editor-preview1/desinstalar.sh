#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${EUID}" -eq 0 ]]; then echo 'Execute sem sudo.' >&2; exit 2; fi
BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -f -- "$HOME/.local/bin/wolf-menu-editor" "$BASE/applications/wolf-menu-editor.desktop"
rm -f -- "$BASE/wolf-linux/menu-editor/wolf-menu-editor.py"
echo '[OK] Editor removido. Entradas pessoais criadas e backups mantidos.'
