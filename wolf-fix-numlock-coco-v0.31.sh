#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo "      WOLF LINUX - NUMLOCK + COCO v0.31"
echo "============================================================"

sudo pacman -S --needed --noconfirm numlockx mate-notification-daemon

sudo install -d /usr/local/libexec /etc/sddm.conf.d

sudo tee /usr/local/libexec/wolf-sddm-xsetup >/dev/null <<'EOF'
#!/bin/sh

if [ -x /usr/share/sddm/scripts/Xsetup ]; then
    /usr/share/sddm/scripts/Xsetup "$@" || true
fi

/usr/bin/numlockx on || true
exit 0
EOF

sudo chmod 755 /usr/local/libexec/wolf-sddm-xsetup

sudo tee /etc/sddm.conf.d/12-wolf-linux-numlock.conf >/dev/null <<'EOF'
[General]
Numlock=on

[X11]
DisplayCommand=/usr/local/libexec/wolf-sddm-xsetup
EOF

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" == *MATE* ]]; then
    if gsettings list-schemas | grep -Fxq 'org.mate.peripherals-keyboard'; then
        gsettings set org.mate.peripherals-keyboard remember-numlock-state false || true
        gsettings set org.mate.peripherals-keyboard numlock-state 'on' || true
    fi

    numlockx on || true

    if gsettings list-schemas | grep -Fxq 'org.mate.NotificationDaemon'; then
        gsettings set org.mate.NotificationDaemon theme 'coco'
        pkill -x mate-notification-daemon 2>/dev/null || true
        sleep 1

        echo "Notificações: $(gsettings get org.mate.NotificationDaemon theme)"
    fi
fi

echo
echo "[OK] Configuração gravada."
echo "NumLock do SDDM será confirmado no próximo reboot/logout."
