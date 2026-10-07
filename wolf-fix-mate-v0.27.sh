#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute este script dentro da sessão MATE do usuário."
    exit 1
fi

echo "============================================================"
echo "      WOLF LINUX - CORREÇÃO DA SESSÃO MATE v0.27"
echo "============================================================"

echo
echo "Instalando DockApplet caso necessário..."
sudo pacman -S --needed --noconfirm mate-applet-dock

echo
echo "Removendo marcadores antigos de configuração..."
rm -f \
    "$HOME/.config/wolf-linux/style-v1.done" \
    "$HOME/.config/wolf-linux/wallpaper-v1.done" \
    "$HOME/.config/wolf-linux/mate-layout-v1.done" \
    "$HOME/.config/wolf-linux/mate-session-v2.done"

echo
echo "Neutralizando tons quentes do Wolf-Sunrise-Dark..."
sudo python - <<'PY'
from pathlib import Path
import colorsys
import re

root = Path("/usr/share/themes/Wolf-Sunrise-Dark")
extensions = {".css", ".xml", ".rc", ".svg", ".theme"}
hex_re = re.compile(r"#[0-9a-fA-F]{6}\b")

def repl(match):
    token = match.group(0)
    r = int(token[1:3], 16) / 255.0
    g = int(token[3:5], 16) / 255.0
    b = int(token[5:7], 16) / 255.0
    h, s, v = colorsys.rgb_to_hsv(r, g, b)

    if not ((0.015 <= h <= 0.18) and s >= 0.28 and v >= 0.20):
        return token

    lum = 0.2126*r + 0.7152*g + 0.0722*b

    if lum >= 0.72:
        rgb = (0x8B, 0x8F, 0x9C)
    elif lum >= 0.50:
        rgb = (0x70, 0x74, 0x81)
    elif lum >= 0.32:
        rgb = (0x5A, 0x5E, 0x69)
    else:
        rgb = (0x45, 0x48, 0x52)

    return "#%02x%02x%02x" % rgb

changed = 0

for path in root.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in extensions:
        continue

    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue

    updated = hex_re.sub(repl, original)
    updated = re.sub(r"\bdarkorange\b", "#5a5e69", updated, flags=re.I)
    updated = re.sub(r"\borange\b", "#707481", updated, flags=re.I)

    if updated != original:
        path.write_text(updated, encoding="utf-8")
        changed += 1

print(f"{changed} arquivos neutralizados.")
PY

echo
echo "Aplicando tema..."
gsettings set org.mate.interface gtk-theme 'Wolf-Sunrise-Dark'
gsettings set org.mate.interface icon-theme 'Papirus-Dark'
gsettings set org.mate.Marco.general theme 'Wolf-Sunrise-Dark' || true
gsettings set org.mate.peripherals-mouse cursor-theme 'breeze-dark' || true
gsettings set org.mate.peripherals-mouse cursor-size 24 || true

echo
echo "Aplicando wallpaper..."
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
gsettings set org.mate.background picture-filename "$WALLPAPER"
gsettings set org.mate.background picture-options 'zoom'

echo
echo "Aplicando teclado..."
XKB_LAYOUT="br"
XKB_VARIANT="abnt2"
MATE_LAYOUT=$'br\tabnt2'
if [[ -r /etc/wolf-linux-keyboard.conf ]]; then
    # shellcheck disable=SC1091
    source /etc/wolf-linux-keyboard.conf
fi
gsettings set org.mate.peripherals-keyboard-xkb.kbd model "'pc105'" || true
gsettings set org.mate.peripherals-keyboard-xkb.kbd layouts "['$MATE_LAYOUT']" || true
setxkbmap "$XKB_LAYOUT" -variant "$XKB_VARIANT" || true

echo
echo "Criando layout do painel no usuário atual..."

sudo install -d /usr/share/mate-panel/layouts

sudo tee /usr/share/mate-panel/layouts/wolf-linux.layout >/dev/null <<'EOF'
[Toplevel bottom]
expand=true
orientation=bottom
size=28

[Object briskmenu]
object-type=applet
applet-iid=BriskMenuFactory::BriskMenu
toplevel-id=bottom
position=0
locked=true

[Object dockapplet]
object-type=applet
applet-iid=DockAppletFactory::DockApplet
toplevel-id=bottom
position=44
locked=true

[Object notification-area]
object-type=applet
applet-iid=NotificationAreaAppletFactory::NotificationArea
toplevel-id=bottom
position=160
panel-right-stick=true
locked=true

[Object clock]
object-type=applet
applet-iid=ClockAppletFactory::ClockApplet
toplevel-id=bottom
position=42
panel-right-stick=true
locked=true

[Object show-desktop]
object-type=applet
applet-iid=WnckletFactory::ShowDesktopApplet
toplevel-id=bottom
position=0
panel-right-stick=true
locked=true
EOF

gsettings set org.mate.panel default-layout 'wolf-linux' || true
mate-panel --reset --layout wolf-linux >/dev/null 2>&1 || true
sleep 3

base="/org/mate/panel/objects/dockapplet/prefs"
dconf write "$base/first-run" "false" || true
dconf write "$base/use-win-list" "true" || true
dconf write "$base/apps-from-all-workspaces" "true" || true
dconf write "$base/pinned-apps-on-all-workspaces" "true" || true
dconf write "$base/app-spacing" "uint32 1" || true
dconf write "$base/multi-ind" "true" || true
dconf write "$base/bg-type" "1" || true
dconf write "$base/pinned-apps" \
    "['caja.desktop', 'mate-terminal.desktop', 'google-chrome.desktop']" || true

echo
echo "Reiniciando painel..."
mate-panel --replace >/dev/null 2>&1 &
disown || true

echo
echo "Resultado:"
echo "  Tema .........: $(gsettings get org.mate.interface gtk-theme)"
echo "  Wallpaper ....: $(gsettings get org.mate.background picture-filename)"
echo "  Layout .......: $(gsettings get org.mate.panel default-layout)"
echo
echo "[OK] Correção aplicada. Se algum detalhe visual não atualizar,"
echo "     encerre a sessão e entre novamente."
