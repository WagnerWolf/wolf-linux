#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute dentro da sessão MATE."
    exit 1
fi

echo "============================================================"
echo "      WOLF LINUX - TEMA FINAL MATE v0.33"
echo "============================================================"
echo
echo "GTK ..........: Materia-dark"
echo "Marco ........: Wolf-Sunrise-Border"
echo "Ícones .......: Papirus-Dark"
echo "Cursor .......: breeze-dark"
echo "Notificações .: coco"
echo

sudo pacman -S --needed --noconfirm \
    materia-gtk-theme \
    python-pillow

if [[ ! -d /usr/share/themes/Wolf-Sunrise-Border/metacity-1 ]]; then
    echo "[INFO] Wolf-Sunrise-Border ainda não existe nesta instalação."
    echo "       Execute primeiro o Theme Base Lab v0.32 opção 4,"
    echo "       ou use uma instalação feita pelo instalador v0.33."
    exit 1
fi

# Remove overrides de cor deixados pelos laboratórios anteriores.
gsettings reset org.mate.interface gtk-color-scheme 2>/dev/null || true

gsettings set org.mate.interface gtk-theme 'Materia-dark'
gsettings set org.mate.interface icon-theme 'Papirus-Dark'
gsettings set org.mate.Marco.general theme 'Wolf-Sunrise-Border' || true
gsettings set org.mate.peripherals-mouse cursor-theme 'breeze-dark' || true
gsettings set org.mate.peripherals-mouse cursor-size 24 || true

if gsettings list-schemas | grep -Fxq 'org.mate.NotificationDaemon'; then
    gsettings set org.mate.NotificationDaemon theme 'coco'
    pkill -x mate-notification-daemon 2>/dev/null || true
fi

# Limpa marcadores para o perfil final ser revalidado no próximo login.
rm -f \
    "$HOME/.config/wolf-linux/mate-session-v2.done" \
    "$HOME/.config/wolf-linux/mate-session-v3.done" \
    "$HOME/.config/wolf-linux/mate-session-v4.done"

caja -q 2>/dev/null || true
pkill mate-panel 2>/dev/null || true
sleep 2
caja --no-default-window >/dev/null 2>&1 &

echo
echo "Resultado:"
echo "  GTK .........: $(gsettings get org.mate.interface gtk-theme)"
echo "  Marco .......: $(gsettings get org.mate.Marco.general theme 2>/dev/null || true)"
echo "  Coco ........: $(gsettings get org.mate.NotificationDaemon theme 2>/dev/null || true)"
echo
echo "[OK] Tema final aplicado."
