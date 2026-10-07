#!/usr/bin/env bash
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

set_default() {
    local desktop="$1"
    shift
    local mime
    for mime in "$@"; do
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
    done
}

TEXT_MIMES=(
    text/plain
    text/markdown
    text/x-readme
    text/x-log
    application/x-shellscript
    application/json
    application/xml
    text/xml
    text/x-python
    text/x-csrc
    text/x-c++src
    text/x-java
    text/x-cmake
)

echo "============================================================"
echo "       WOLF LINUX - DESKTOP ESSENTIALS FIX 1.0.8"
echo "============================================================"
echo "Desktop: ${DESKTOP:-desconhecido}"
echo

case "$DESKTOP" in
    *MATE*)
        sudo pacman -S --needed --noconfirm pluma mate-calc
        set_default pluma.desktop "${TEXT_MIMES[@]}"
        echo "[OK] Pluma + MATE Calculator."
        ;;

    *X-Cinnamon*|*Cinnamon*)
        sudo pacman -S --needed --noconfirm xed galculator
        set_default xed.desktop "${TEXT_MIMES[@]}"
        echo "[OK] Xed como editor padrão + Galculator."
        ;;

    *KDE*|*Plasma*)
        sudo pacman -S --needed --noconfirm kate kcalc
        set_default org.kde.kwrite.desktop "${TEXT_MIMES[@]}"

        CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

        if [[ -s "$CONFIG" ]]; then
            cp -n "$CONFIG" "$CONFIG.wolf-backup" 2>/dev/null || true

            python - "$CONFIG" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
out = []

for line in lines:
    if line.startswith("launchers="):
        prefix, value = line.split("=", 1)
        items = [item for item in value.split(",") if item]
        items = [item for item in items if "discover" not in item.lower()]
        line = prefix + "=" + ",".join(items)
    out.append(line)

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

            if ! systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1; then
                kquitapp6 plasmashell >/dev/null 2>&1 || true
                nohup plasmashell --replace >/dev/null 2>&1 &
                disown || true
            fi
        fi

        echo "[OK] KWrite como editor padrão + KCalc + Discover removido do painel."
        ;;

    *)
        echo "[ERRO] Desktop não reconhecido."
        exit 1
        ;;
esac

echo
echo "Editor padrão para text/plain:"
xdg-mime query default text/plain || true
