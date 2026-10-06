#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    TARGET_USER="${SUDO_USER:-}"
    if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
        echo "[ERRO] Execute este script como o usuário da sessão, sem sudo."
        exit 1
    fi
else
    TARGET_USER="$USER"
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" ]] || TARGET_HOME="/home/$TARGET_USER"

TMP_SCRIPT="$(mktemp)"
trap 'rm -f "$TMP_SCRIPT"' EXIT

cat > "$TMP_SCRIPT" <<'SCRIPT'
#!/usr/bin/env bash
set -u

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
FILE_MANAGER_DESKTOP=""

case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*) FILE_MANAGER_DESKTOP="nemo.desktop" ;;
    *MATE*) FILE_MANAGER_DESKTOP="caja.desktop" ;;
    *KDE*|*Plasma*) FILE_MANAGER_DESKTOP="org.kde.dolphin.desktop" ;;
esac

[[ -n "$FILE_MANAGER_DESKTOP" ]] || exit 0
[[ -r "/usr/share/applications/$FILE_MANAGER_DESKTOP" ]] || exit 0

xdg-mime default "$FILE_MANAGER_DESKTOP" inode/directory >/dev/null 2>&1 || true
if command -v gio >/dev/null 2>&1; then
    gio mime inode/directory "$FILE_MANAGER_DESKTOP" >/dev/null 2>&1 || true
fi
SCRIPT

sudo install -Dm755 "$TMP_SCRIPT" /usr/local/bin/wolf-protect-directory-handler

sudo install -d /etc/xdg/autostart
sudo tee /etc/xdg/autostart/wolf-protect-directory-handler.desktop >/dev/null <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Proteger gerenciador de arquivos
Comment=Mantém pastas associadas ao gerenciador de arquivos nativo do desktop
Exec=/usr/local/bin/wolf-protect-directory-handler
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF_DESKTOP

# Aplica imediatamente na sessão atual do usuário.
/usr/local/bin/wolf-protect-directory-handler || true

echo
printf 'Handler atual de inode/directory: '
xdg-mime query default inode/directory || true

echo
echo "[OK] Proteção de diretórios instalada."
echo "Ela será reaplicada a cada login para Cinnamon/Nemo, MATE/Caja e KDE/Dolphin."
