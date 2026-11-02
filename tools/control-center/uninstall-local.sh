#!/usr/bin/env bash
set -Eeuo pipefail
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -f -- "$HOME/.local/bin/wolf-control-center" "$HOME/.local/bin/wolf-monitors" \
    "$DATA/applications/wolf-control-center.desktop" "$DATA/applications/wolf-monitors.desktop"
rm -rf -- "$DATA/wolf-linux/control-center"
# Não remover layout salvo nem configurações de monitores do usuário.
printf '[OK] Atalhos e Control Center locais removidos; layouts pessoais preservados.\n'
