#!/usr/bin/env bash
set -Eeuo pipefail
rm -f "$HOME/.local/bin/wolf-control-center" \
      "$HOME/.local/share/applications/wolf-control-center.desktop"
rm -rf -- "$HOME/.local/share/wolf-linux/control-center"
if command -v kbuildsycoca6 >/dev/null 2>&1; then kbuildsycoca6 >/dev/null 2>&1 || true; fi
printf '[OK] Removido apenas o Wolf Control Center instalado para este usuário.\n'
