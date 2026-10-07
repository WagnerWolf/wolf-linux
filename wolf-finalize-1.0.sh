#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo "          WOLF LINUX 1.0.6 - FINALIZER ESTÁVEL"
echo "============================================================"
echo
echo "Aplicando:"
echo "  - tema escuro via XDG Desktop Portal"
echo "  - RTKit para PipeWire"
echo "  - remoção do experimento de mover janelas entre monitores"
echo "  - restauração do clique do meio nativo do Marco"
echo

sudo pacman -S --needed --noconfirm \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    rtkit \
    gnome-disk-utility

# Dark mode
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.mate.interface gtk-theme 'Materia-dark' 2>/dev/null || true
gsettings set org.mate.interface icon-theme 'Papirus-Dark' 2>/dev/null || true

systemctl --user restart \
    xdg-desktop-portal-gtk.service \
    xdg-desktop-portal.service \
    >/dev/null 2>&1 || true

# Remove window mover experiment
pkill -f '^/usr/local/bin/wolf-titlebar-monitor-move$' 2>/dev/null || true

sudo rm -f \
    /usr/local/bin/wolf-titlebar-monitor-move \
    /usr/local/bin/wolf-titlebar-monitor-move-start \
    /usr/local/src/wolf-titlebar-monitor-move.c \
    /etc/xdg/autostart/wolf-titlebar-monitor-move.desktop

rm -f \
    "$HOME/.cache/wolf-titlebar-monitor-move.log" \
    "${XDG_RUNTIME_DIR:-/tmp}/wolf-titlebar-monitor-move-${UID}.lock" \
    2>/dev/null || true

# Restore native Marco middle-click behavior.
if gsettings list-keys org.mate.Marco.general 2>/dev/null \
    | grep -Fxq 'action-middle-click-titlebar'; then
    gsettings set \
        org.mate.Marco.general \
        action-middle-click-titlebar \
        'lower' || true
fi

sudo systemctl start rtkit-daemon.service 2>/dev/null || true

echo
echo "Portal color-scheme:"
gdbus call --session \
    --dest org.freedesktop.portal.Desktop \
    --object-path /org/freedesktop/portal/desktop \
    --method org.freedesktop.portal.Settings.Read \
    org.freedesktop.appearance \
    color-scheme \
    2>/dev/null || true

echo
echo "[OK] Finalização estável concluída."
echo "O recurso Super+botão do meio para mover janelas NÃO faz parte da 1.0.6."
