#!/usr/bin/env bash
# Instalação por usuário, mantida para atualizações manuais do Control Center.
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
BASE="$DATA/wolf-linux/control-center"
BIN="$HOME/.local/bin/wolf-control-center"
MONITOR_BIN="$HOME/.local/bin/wolf-monitors"
DESKTOP="$DATA/applications/wolf-control-center.desktop"
MONITOR_DESKTOP="$DATA/applications/wolf-monitors.desktop"
if ! /usr/bin/python3 -c 'from PySide6.QtWidgets import QApplication' >/dev/null 2>&1; then
    printf '[ERRO] PySide6 não instalado. Execute: sudo pacman -S --needed pyside6\n' >&2
    exit 2
fi
mkdir -p "$BASE" "$(dirname "$BIN")" "$(dirname "$DESKTOP")"
for f in main.py backend.py lxqt_support.py wolf_profile.py monitor_editor.py monitor_layout.py wolf_monitors.py; do
    install -m 0644 "$HERE/$f" "$BASE/$f"
done
cat > "$BIN" <<'WRAPPER'
#!/usr/bin/env sh
if [ "${1:-}" = "--monitors" ] && [ "$#" -eq 1 ]; then
    exec "$HOME/.local/bin/wolf-monitors"
fi
exec /usr/bin/python3 "${XDG_DATA_HOME:-$HOME/.local/share}/wolf-linux/control-center/main.py" "$@"
WRAPPER
cat > "$MONITOR_BIN" <<'WRAPPER'
#!/usr/bin/env sh
exec /usr/bin/python3 "${XDG_DATA_HOME:-$HOME/.local/share}/wolf-linux/control-center/wolf_monitors.py" "$@"
WRAPPER
chmod 755 "$BIN" "$MONITOR_BIN"
install -m 0644 "$HERE/wolf-control-center.desktop" "$DESKTOP"
install -m 0644 "$HERE/wolf-monitors.desktop" "$MONITOR_DESKTOP"
# Referências diretas, pois ~/.local/bin nem sempre está no PATH da sessão.
/usr/bin/python3 - "$DESKTOP" "$BIN" "$MONITOR_DESKTOP" "$MONITOR_BIN" <<'PYCODE'
from pathlib import Path
import sys
cc, cc_bin, monitors, monitor_bin=map(Path,sys.argv[1:])
cc.write_text(cc.read_text(encoding='utf-8').replace('Exec=wolf-control-center\n','Exec='+str(cc_bin)+'\n'),encoding='utf-8')
monitors.write_text(monitors.read_text(encoding='utf-8').replace('Exec=/usr/local/bin/wolf-control-center --monitors\n','Exec='+str(cc_bin)+' --monitors\n').replace('TryExec=/usr/local/bin/wolf-monitors\n','TryExec='+str(monitor_bin)+'\n'),encoding='utf-8')
PYCODE
printf '[OK] Control Center e Monitores Wolf instalados para %s.\n' "$USER"
printf 'Abra Monitores (Wolf Linux) no menu ou execute: %s --monitors\n' "$BIN"
