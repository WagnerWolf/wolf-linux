#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo " WOLF LINUX 1.0.6 - REMOVER MOVER EXPERIMENTAL DE JANELAS"
echo "============================================================"

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

if gsettings list-keys org.mate.Marco.general 2>/dev/null \
    | grep -Fxq 'action-middle-click-titlebar'; then
    gsettings set \
        org.mate.Marco.general \
        action-middle-click-titlebar \
        'lower' || true
fi

echo
echo "[OK] Recurso experimental removido."
echo "[OK] Clique do meio na barra do Marco restaurado para 'lower'."
echo
echo "As barreiras de borda entre monitores continuam instaladas e ativas."
