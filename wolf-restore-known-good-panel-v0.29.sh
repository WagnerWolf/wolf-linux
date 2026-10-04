#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute dentro da sessão MATE."
    exit 1
fi

echo "============================================================"
echo "   WOLF LINUX - RESTAURAR PAINEL CONHECIDO COMO BOM"
echo "============================================================"

BRISK_DESCRIPTOR="/usr/share/mate-panel/applets/com.solus_project.brisk.BriskMenu.mate-panel-applet"

if [[ ! -f "$BRISK_DESCRIPTOR" ]]; then
    echo "[ERRO] Brisk está instalado, mas o descriptor esperado não foi encontrado:"
    echo "       $BRISK_DESCRIPTOR"
    echo
    echo "Arquivos do pacote brisk-menu:"
    pacman -Ql brisk-menu 2>/dev/null | grep -E 'mate-panel|Brisk|brisk' || true
    exit 1
fi

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

[Object window-list]
object-type=applet
applet-iid=WnckletFactory::WindowListApplet
toplevel-id=bottom
position=42
locked=true

[Object caja]
object-type=launcher
launcher-location=/usr/share/applications/caja.desktop
toplevel-id=bottom
position=285
panel-right-stick=true
locked=true

[Object mate-terminal]
object-type=launcher
launcher-location=/usr/share/applications/mate-terminal.desktop
toplevel-id=bottom
position=250
panel-right-stick=true
locked=true

[Object google-chrome]
object-type=launcher
launcher-location=/usr/share/applications/google-chrome.desktop
toplevel-id=bottom
position=215
panel-right-stick=true
locked=true

[Object notification-area]
object-type=applet
applet-iid=NotificationAreaAppletFactory::NotificationArea
toplevel-id=bottom
position=165
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

rm -f \
    "$HOME/.config/wolf-linux/mate-layout-v1.done" \
    "$HOME/.config/wolf-linux/mate-layout-v4.done" \
    "$HOME/.config/wolf-linux/mate-session-v2.done" \
    "$HOME/.config/wolf-linux/mate-session-v3.done"

gsettings set org.mate.panel default-layout 'wolf-linux'

if gsettings list-schemas | grep -Fxq 'com.solus-project.brisk-menu'; then
    gsettings set com.solus-project.brisk-menu label-visible false || true
fi

echo "Aplicando exatamente o layout que funcionou anteriormente..."
mate-panel --reset --layout wolf-linux

echo
echo "[OK] Painel restaurado."
echo "Se algum objeto ainda não aparecer imediatamente, faça logout/login uma vez."
