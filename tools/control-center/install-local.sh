#!/usr/bin/env bash
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$HOME/.local/share/wolf-linux/control-center"
BIN="$HOME/.local/bin/wolf-control-center"
DESKTOP="$HOME/.local/share/applications/wolf-control-center.desktop"
if ! /usr/bin/python3 -c 'from PySide6.QtWidgets import QApplication' >/dev/null 2>&1; then
    printf '[ERRO] PySide6 não instalado. Execute: sudo pacman -S --needed pyside6\n' >&2
    exit 2
fi
mkdir -p "$BASE" "$(dirname "$BIN")" "$(dirname "$DESKTOP")"
install -m 0644 "$HERE/main.py" "$BASE/main.py"
install -m 0644 "$HERE/backend.py" "$BASE/backend.py"
cat > "$BIN" <<'WRAPPER'
#!/usr/bin/env sh
exec /usr/bin/python3 "$HOME/.local/share/wolf-linux/control-center/main.py" "$@"
WRAPPER
chmod 755 "$BIN"
install -m 0644 "$HERE/wolf-control-center.desktop" "$DESKTOP"
# Desktop launcher uses PATH only if ~/.local/bin is on PATH; use full path to avoid surprises.
python3 - "$DESKTOP" "$BIN" <<'PYCODE'
from pathlib import Path
import sys
p=Path(sys.argv[1]); text=p.read_text(encoding='utf-8')
text=text.replace('Exec=wolf-control-center\n', 'Exec='+sys.argv[2]+'\n')
p.write_text(text,encoding='utf-8')
PYCODE
if command -v kbuildsycoca6 >/dev/null 2>&1; then kbuildsycoca6 >/dev/null 2>&1 || true; fi
printf '[OK] Wolf Control Center instalado para %s.\n' "$USER"
printf 'Abra pelo menu do KDE ou execute: %s\n' "$BIN"
