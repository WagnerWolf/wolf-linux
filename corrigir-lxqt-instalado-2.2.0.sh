#!/usr/bin/env bash
# Correção opcional da instalação física Wolf LXQt 2.2.0 atual.
# Use --check (somente relatório) ou --apply (backup + instalação de scripts).
# Não altera kernels, /home de outros usuários, discos ou bootloader.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/tools"
usage(){ echo "Uso: bash corrigir-lxqt-instalado-2.2.0.sh [--check|--apply]"; }
[[ $# -eq 1 ]] || { usage; exit 2; }
case "$1" in --check|--apply) mode="$1";; *) usage; exit 2;; esac
[[ "$(id -u)" -ne 0 ]] || { echo 'Execute como usuário normal; sudo será pedido somente se necessário.' >&2; exit 2; }
for rel in control-center/monitor_editor.py control-center/monitor_layout.py lxqt/wolf_lxqt_monitors.py lxqt/wolf-mouse-flat.sh lxqt/wolf-user-dirs-ptbr.py; do
    [[ -f "$SRC/$rel" ]] || { echo "Arquivo ausente no DevKit: $rel" >&2; exit 1; }
done
syscc=/usr/local/lib/wolf-linux/control-center
[[ -f "$syscc/main.py" ]] || { echo "Wolf Control Center global ausente: $syscc/main.py" >&2; exit 1; }
if [[ "$mode" == --check ]]; then
    echo 'Arquivos Wolf existentes:'
    for path in "$syscc/monitor_editor.py" "$syscc/monitor_layout.py" /usr/local/bin/wolf-lxqt-monitors \
        /usr/local/bin/wolf-lxqt-mouse-flat "$HOME/.config/autostart/wolf-lxqt-monitors.desktop" \
        "$HOME/.config/autostart/wolf-lxqt-layout-restore.desktop" "$HOME/.config/user-dirs.dirs"; do
        [[ ! -e "$path" ]] || echo "  [EXISTE] $path"
    done
    echo 'Nenhum arquivo foi alterado. Use --apply para aplicar os ajustes globais e autostarts.'
    echo 'Pastas inglesas podem ser migradas separadamente com: python3 tools/lxqt/wolf-user-dirs-ptbr.py --migrate'
    exit 0
fi
backup="$HOME/wolf-backups/lxqt-firstboot-fix/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup/global" "$backup/user"
for path in "$syscc/monitor_editor.py" "$syscc/monitor_layout.py" /usr/local/bin/wolf-lxqt-monitors \
    /usr/local/bin/wolf-lxqt-mouse-flat /etc/X11/xorg.conf.d/50-wolf-lxqt-mouse-flat.conf; do
    if [[ -f "$path" ]]; then
        sudo cp -p -- "$path" "$backup/global/$(basename "$path")"
    fi
done
for name in wolf-lxqt-monitors.desktop wolf-lxqt-layout-restore.desktop wolf-lxqt-mouse-flat.desktop; do
    path="$HOME/.config/autostart/$name"
    [[ ! -f "$path" ]] || cp -p -- "$path" "$backup/user/$name"
done
sudo install -m 0644 "$SRC/control-center/monitor_editor.py" "$syscc/monitor_editor.py"
sudo install -m 0644 "$SRC/control-center/monitor_layout.py" "$syscc/monitor_layout.py"
sudo install -m 0755 "$SRC/lxqt/wolf_lxqt_monitors.py" /usr/local/bin/wolf-lxqt-monitors
sudo install -m 0755 "$SRC/lxqt/wolf-mouse-flat.sh" /usr/local/bin/wolf-lxqt-mouse-flat
sudo install -m 0755 "$SRC/lxqt/wolf-user-dirs-ptbr.py" /usr/local/bin/wolf-user-dirs-ptbr
sudo install -d /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/50-wolf-lxqt-mouse-flat.conf >/dev/null <<'XORG'
Section "InputClass"
    Identifier "Wolf LXQt - mouse sem aceleracao"
    MatchIsPointer "on"
    MatchIsTouchpad "off"
    MatchDriver "libinput"
    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
EndSection
XORG
mkdir -p "$HOME/.config/autostart"
old="$HOME/.config/autostart/wolf-lxqt-monitors.desktop"
layout="$HOME/.config/autostart/wolf-lxqt-layout-restore.desktop"
if [[ -f "$old" ]] && grep -q 'wolf-monitors-apply' "$old" && ! grep -q 'wolf-lxqt-monitors --session' "$old"; then
    cp -p "$old" "$layout"
fi
cat > "$old" <<'PANEL'
[Desktop Entry]
Type=Application
Name=Wolf - Painéis por monitor
Exec=/usr/local/bin/wolf-lxqt-monitors --session
TryExec=/usr/local/bin/wolf-lxqt-monitors
OnlyShowIn=LXQt;
NoDisplay=true
Terminal=false
PANEL
cat > "$HOME/.config/autostart/wolf-lxqt-mouse-flat.desktop" <<'MOUSE'
[Desktop Entry]
Type=Application
Name=Wolf - Mouse sem aceleração
Exec=/usr/local/bin/wolf-lxqt-mouse-flat
TryExec=/usr/local/bin/wolf-lxqt-mouse-flat
OnlyShowIn=LXQt;
NoDisplay=true
MOUSE
printf '\n[OK] Correções aplicadas. Backup em: %s\n' "$backup"
echo 'Faça logout/login para ativar a política do mouse e sincronizar painéis.'
echo 'Para ajustar agora o painel secundário: wolf-lxqt-monitors'
echo 'Pastas XDG (opcional): wolf-user-dirs-ptbr  [ver plano]'
echo 'Para migrar pastas inglesas com backup: wolf-user-dirs-ptbr --migrate'
