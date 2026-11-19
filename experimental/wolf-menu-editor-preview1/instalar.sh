#!/usr/bin/env bash
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${EUID}" -eq 0 ]]; then
  echo '[ERRO] Execute como usuário normal, sem sudo.' >&2
  exit 2
fi
if ! /usr/bin/python3 -c 'from PySide6.QtWidgets import QApplication' >/dev/null 2>&1; then
  echo '[ERRO] PySide6 ausente: sudo pacman -S --needed pyside6' >&2
  exit 2
fi
BASE="${XDG_DATA_HOME:-$HOME/.local/share}"
DEST="$BASE/wolf-linux/menu-editor"
mkdir -p "$DEST" "$HOME/.local/bin" "$BASE/applications"
if [[ -e "$DEST/wolf-menu-editor.py" ]]; then
  mkdir -p "$DEST/backups"
  cp -a "$DEST/wolf-menu-editor.py" "$DEST/backups/wolf-menu-editor-$(date +%Y%m%d-%H%M%S).py"
fi
install -m 0644 "$HERE/wolf-menu-editor.py" "$DEST/wolf-menu-editor.py"
cat > "$HOME/.local/bin/wolf-menu-editor" <<WRAPPER
#!/bin/sh
exec /usr/bin/python3 '$DEST/wolf-menu-editor.py' "\$@"
WRAPPER
chmod 0755 "$HOME/.local/bin/wolf-menu-editor"
cat > "$BASE/applications/wolf-menu-editor.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Editor do Menu (Wolf Linux)
Name[pt_BR]=Editor do Menu (Wolf Linux)
Comment=Adicionar, editar e ocultar entradas do menu LXQt
Exec=$HOME/.local/bin/wolf-menu-editor
TryExec=$HOME/.local/bin/wolf-menu-editor
Icon=preferences-desktop
Terminal=false
Categories=Settings;System;
StartupNotify=true
DESKTOP
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$BASE/applications" >/dev/null 2>&1 || true
fi
echo '[OK] Wolf Menu Editor instalado para este usuário.'
echo "Abra 'Editor do Menu (Wolf Linux)' no menu LXQt ou execute: $HOME/.local/bin/wolf-menu-editor"
