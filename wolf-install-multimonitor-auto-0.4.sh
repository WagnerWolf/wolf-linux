#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_SRC="$SELF_DIR/wolf-multimonitor-setup-0.4.sh"
HELPER_DST="/usr/local/bin/wolf-cinnamon-multimonitor"
HOTKEY_SRC="$SELF_DIR/wolf-fix-cinnvii-super-monitor-0.2.sh"
HOTKEY_DST="/usr/local/bin/wolf-cinnvii-hotkey-fix"
AUTOSTART_DST="/etc/xdg/autostart/wolf-cinnamon-multimonitor.desktop"

if [[ $EUID -eq 0 ]]; then
    echo "[ERRO] Execute este instalador como seu usuário normal, sem sudo."
    exit 1
fi

[[ -f "$HELPER_SRC" ]] || {
    echo "[ERRO] Não encontrei $HELPER_SRC"
    exit 1
}
[[ -f "$HOTKEY_SRC" ]] || {
    echo "[ERRO] Não encontrei $HOTKEY_SRC"
    exit 1
}

sudo install -Dm0755 "$HELPER_SRC" "$HELPER_DST"
sudo install -Dm0755 "$HOTKEY_SRC" "$HOTKEY_DST"

# Aplica agora a correção do hotkey por monitor ao CinnVII já instalado.
"$HOTKEY_DST" || true

sudo install -d -m0755 /etc/xdg/autostart
sudo tee "$AUTOSTART_DST" >/dev/null <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Wolf Linux MultiMonitor
Comment=Painel, menu, janelas e Alt+Tab independentes em cada monitor Cinnamon
Exec=/usr/local/bin/wolf-cinnamon-multimonitor watch
OnlyShowIn=X-Cinnamon;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESKTOP

# Uma versão anterior já pode ter aplicado a estrutura manualmente. O enable é idempotente:
# preserva o painel existente e apenas ativa a vigilância para hotplug futuro.
"$HELPER_DST" enable

echo
echo "[OK] Wolf MultiMonitor automático instalado."
echo "- O estado atual dos painéis foi preservado."
echo "- Novos monitores serão detectados durante a sessão."
echo "- A tecla Super abrirá o CinnVII no monitor onde estiver o ponteiro após recarregar o Cinnamon."
echo "- Também haverá reconciliação automática a cada login Cinnamon."
echo
echo "Comandos úteis:"
echo "  wolf-cinnamon-multimonitor status"
echo "  wolf-cinnamon-multimonitor disable"
echo "  wolf-cinnamon-multimonitor enable"
echo "  wolf-cinnamon-multimonitor restore"
