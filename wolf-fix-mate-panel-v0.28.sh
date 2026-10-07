#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute dentro da sessão MATE."
    exit 1
fi

echo "============================================================"
echo "      WOLF LINUX - PAINEL MATE FINAL v0.28"
echo "============================================================"

sudo pacman -S --needed --noconfirm mate-applet-dock

BRISK_OK=0
DOCK_OK=0

if [[ -f /usr/share/mate-panel/applets/com.solus_project.brisk.BriskMenu.mate-panel-applet ]] \
   && { [[ -x /usr/lib/brisk-menu/brisk-menu ]] \
        || [[ -x /usr/libexec/brisk-menu ]] \
        || find /usr/lib -maxdepth 3 -type f -path '*/brisk-menu/brisk-menu' -perm -111 -print -quit 2>/dev/null | grep -q .; }; then
    BRISK_OK=1
fi

if [[ -f /usr/share/mate-panel/applets/org.mate.panel.DockApplet.mate-panel-applet ]] \
   && [[ -f /usr/lib/mate-applets/mate-dock-applet/dock.py ]]; then
    DOCK_OK=1
fi

echo "Brisk detectado: $BRISK_OK"
echo "Dock detectado : $DOCK_OK"

(( BRISK_OK == 1 )) || {
    echo "[ERRO] Brisk Menu não foi localizado."
    exit 1
}

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

sudo tee /usr/share/mate-panel/layouts/wolf-linux-brisk-fallback.layout >/dev/null <<'EOF'
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
position=44
locked=true

[Object caja]
object-type=launcher
launcher-location=/usr/share/applications/caja.desktop
toplevel-id=bottom
position=520
locked=true

[Object mate-terminal]
object-type=launcher
launcher-location=/usr/share/applications/mate-terminal.desktop
toplevel-id=bottom
position=560
locked=true

[Object google-chrome]
object-type=launcher
launcher-location=/usr/share/applications/google-chrome.desktop
toplevel-id=bottom
position=600
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

panel_has_iid() {
    local iid="$1"
    local object_ids object_id found_iid

    object_ids="$(
        gsettings get org.mate.panel object-id-list 2>/dev/null \
            | tr -d "[],'"
    )"

    for object_id in $object_ids; do
        found_iid="$(
            gsettings get \
                org.mate.panel.object:/org/mate/panel/objects/"$object_id"/ \
                applet-iid 2>/dev/null \
                | tr -d "'"
        )"
        [[ "$found_iid" == "$iid" ]] && return 0
    done

    return 1
}

apply_layout() {
    local layout="$1"
    local need_dock="$2"
    local i

    for i in $(seq 1 5); do
        echo "Tentativa $i/5: $layout"

        gsettings set org.mate.panel default-layout "$layout" || true
        mate-panel --reset --layout "$layout" >/dev/null 2>&1 || true
        sleep 2

        mate-panel --replace >/dev/null 2>&1 &
        disown || true
        sleep 2

        if panel_has_iid 'BriskMenuFactory::BriskMenu'; then
            if [[ "$need_dock" == "no" ]] \
               || panel_has_iid 'DockAppletFactory::DockApplet'; then
                return 0
            fi
        fi
    done

    return 1
}

LAYOUT="wolf-linux-brisk-fallback"

if (( DOCK_OK == 1 )) && apply_layout wolf-linux yes; then
    LAYOUT="wolf-linux"

    schema='org.mate.panel.applet.dock'
    path='/org/mate/panel/objects/dockapplet/prefs/'

    if gsettings list-schemas | grep -Fxq "$schema"; then
        gsettings set "$schema:$path" \
            pinned-apps \
            "['caja.desktop', 'mate-terminal.desktop', 'google-chrome.desktop']" || true

        gsettings set "$schema:$path" apps-from-all-workspaces true || true
        gsettings set "$schema:$path" use-win-list true || true
        gsettings set "$schema:$path" multi-ind true || true

        echo
        echo "Apps fixados:"
        gsettings get "$schema:$path" pinned-apps || true

        mate-panel --replace >/dev/null 2>&1 &
        disown || true
    fi
else
    echo "[AVISO] DockApplet não estabilizou; usando Brisk + launchers fixos."
    apply_layout wolf-linux-brisk-fallback no
fi

echo
echo "Layout final: $LAYOUT"
panel_has_iid 'BriskMenuFactory::BriskMenu' \
    && echo "[OK] Brisk presente." \
    || echo "[ERRO] Brisk ausente."

panel_has_iid 'DockAppletFactory::DockApplet' \
    && echo "[OK] Dock presente." \
    || echo "[INFO] Dock ausente; fallback com launchers fixos."
