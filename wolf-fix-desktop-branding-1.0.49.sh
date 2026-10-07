#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SELF_DIR/wolf-desktop-branding-0.1.sh"
[[ -f "$SRC" ]] || { echo "[ERRO] $SRC não encontrado." >&2; exit 1; }

sudo install -Dm0755 "$SRC" /usr/local/bin/wolf-desktop-branding
sudo install -d -m0755 /etc/xdg/autostart
sudo tee /etc/xdg/autostart/wolf-desktop-branding.desktop >/dev/null <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Identidade do desktop
Comment=Aplica o símbolo Wolf Linux ao menu do Cinnamon e Plasma uma única vez
Exec=/usr/local/bin/wolf-desktop-branding
OnlyShowIn=X-Cinnamon;KDE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOP

case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
    *X-Cinnamon*|*Cinnamon*|*KDE*|*Plasma*)
        /usr/local/bin/wolf-desktop-branding --force || true
        ;;
esac

echo "[OK] Branding Cinnamon/KDE instalado."
echo "- Cinnamon: CinnVII/menu usa o ícone Wolf Linux."
echo "- Plasma: Kickoff usa o ícone Wolf Linux."
echo "- A aplicação automática ocorre apenas uma vez por desktop/usuário."
