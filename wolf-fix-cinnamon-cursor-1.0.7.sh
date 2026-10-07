#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo "      WOLF LINUX - CINNAMON CURSOR FIX 1.0.7"
echo "============================================================"

CURSOR_THEME="breeze_cursors"

if [[ ! -d "/usr/share/icons/$CURSOR_THEME/cursors" ]]; then
    if [[ -d /usr/share/icons/Breeze_Snow/cursors ]]; then
        CURSOR_THEME="Breeze_Snow"
    else
        CURSOR_THEME="Adwaita"
    fi
fi

echo "Tema de cursor selecionado: $CURSOR_THEME"

mkdir -p \
    "$HOME/.config/gtk-3.0" \
    "$HOME/.config/gtk-4.0" \
    "$HOME/.local/share/icons/default" \
    "$HOME/.icons/default"

for file in \
    "$HOME/.config/gtk-3.0/settings.ini" \
    "$HOME/.config/gtk-4.0/settings.ini"
do
    touch "$file"

    if grep -q '^gtk-cursor-theme-name=' "$file"; then
        sed -i \
            "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CURSOR_THEME/" \
            "$file"
    else
        grep -q '^\[Settings\]' "$file" || printf '[Settings]\n' >> "$file"
        printf 'gtk-cursor-theme-name=%s\n' "$CURSOR_THEME" >> "$file"
    fi

    if grep -q '^gtk-cursor-theme-size=' "$file"; then
        sed -i 's/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=24/' "$file"
    else
        printf 'gtk-cursor-theme-size=24\n' >> "$file"
    fi
done

cat > "$HOME/.local/share/icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=$CURSOR_THEME
EOF

cat > "$HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=$CURSOR_THEME
EOF

if gsettings list-schemas | grep -Fxq 'org.cinnamon.desktop.interface'; then
    gsettings set org.cinnamon.desktop.interface cursor-theme "$CURSOR_THEME"
    gsettings set org.cinnamon.desktop.interface cursor-size 24
fi

if gsettings list-schemas | grep -Fxq 'org.gnome.desktop.interface'; then
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null || true
fi

{
    grep -vE '^Xcursor\.(theme|size):' "$HOME/.Xresources" 2>/dev/null || true
    echo "Xcursor.theme: $CURSOR_THEME"
    echo "Xcursor.size: 24"
} > "$HOME/.Xresources.wolf"

mv -f "$HOME/.Xresources.wolf" "$HOME/.Xresources"

if command -v xrdb >/dev/null 2>&1; then
    xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
fi

echo
echo "[OK] Cursor do Cinnamon corrigido."
echo "Faça logout/login do Cinnamon para garantir que todas as aplicações"
echo "recarreguem o tema XCursor."
