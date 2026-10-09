#!/usr/bin/env bash
# Idempotente: adiciona o ambiente gráfico somente ao airootfs da ISO Live.
set -Eeuo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
PROFILE="${WOLF_ISO_PROFILE:-$PROJECT/iso-profile}"
AIROOT="$PROFILE/airootfs"
SOURCE="$PROJECT/live-gui"
PACKAGES="$PROFILE/packages.x86_64"
PROFILEDEF="$PROFILE/profiledef.sh"

[[ -f "$SOURCE/main.py" ]] || { echo "[ERRO] GUI live não encontrada: $SOURCE" >&2; exit 1; }
[[ -f "$PACKAGES" && -f "$PROFILEDEF" ]] || { echo '[ERRO] Perfil Archiso incompleto.' >&2; exit 1; }

# Não acrescentar esses pacotes à instalação alvo. Somente lista da ISO.
LIVE_GUI_PACKAGES=(
    openbox xorg-server xorg-xinit xorg-xauth xorg-xrandr xorg-xsetroot
    xf86-input-libinput xf86-video-vesa xf86-video-fbdev mesa
    pyside6 python qterminal pcmanfm-qt feh gparted sudo dbus
    networkmanager network-manager-applet nm-connection-editor stalonetray lxqt-policykit
    xorg-setxkbmap xorg-fonts-misc
)
for pkg in "${LIVE_GUI_PACKAGES[@]}"; do
    grep -Fxq "$pkg" "$PACKAGES" || printf '%s\n' "$pkg" >> "$PACKAGES"
done

install -Dm0755 "$SOURCE/wolf-live-create-user" "$AIROOT/usr/local/bin/wolf-live-create-user"
install -Dm0755 "$SOURCE/wolf-live-gparted" "$AIROOT/usr/local/bin/wolf-live-gparted"
install -Dm0755 "$SOURCE/wolf-live-diagnostics" "$AIROOT/usr/local/bin/wolf-live-diagnostics"
install -Dm0755 "$SOURCE/wolf-live-installer" "$AIROOT/usr/local/bin/wolf-live-installer"
install -Dm0755 "$SOURCE/wolf-live-review-plan" "$AIROOT/usr/local/bin/wolf-live-review-plan"
install -Dm0755 "$SOURCE/wolf-live-simulate-plan" "$AIROOT/usr/local/bin/wolf-live-simulate-plan"
install -Dm0755 "$SOURCE/wolf-live-execute-vm-plan" "$AIROOT/usr/local/bin/wolf-live-execute-vm-plan"
install -Dm0755 "$SOURCE/wolf-live-network" "$AIROOT/usr/local/bin/wolf-live-network"
install -Dm0644 "$SOURCE/main.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/main.py"
install -Dm0644 "$SOURCE/wolf_plan.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/wolf_plan.py"
install -Dm0644 "$SOURCE/wolf_plan.py" "$AIROOT/root/wolf-linux/live-gui/wolf_plan.py"
install -Dm0644 "$SOURCE/wolf-live-user.service" "$AIROOT/etc/systemd/system/wolf-live-user.service"
install -Dm0644 "$SOURCE/wolf-live-autologin.conf" "$AIROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf"
install -Dm0644 "$SOURCE/wolf-live-sudoers" "$AIROOT/etc/sudoers.d/90-wolf-live"
chmod 0440 "$AIROOT/etc/sudoers.d/90-wolf-live"
install -Dm0644 "$SOURCE/wolf-live-session.desktop" "$AIROOT/usr/share/xsessions/wolf-live.desktop"
install -Dm0644 "$PROJECT/assets/wallpapers/wolf-linux-wallpaper.png" "$AIROOT/usr/share/backgrounds/wolf-linux/wallpaper.png"
install -d "$AIROOT/usr/share/wolf-live/home"
cp -a "$SOURCE/home/." "$AIROOT/usr/share/wolf-live/home/"

# NetworkManager é o controlador da rede na Live gráfica. Não ativar o iwd
# como gerenciador independente (evita disputa por dispositivos Wi-Fi).
install -d "$AIROOT/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/NetworkManager.service \
    "$AIROOT/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
rm -f "$AIROOT/etc/systemd/system/multi-user.target.wants/iwd.service"
rm -f "$AIROOT/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
# Garante que o criador do usuário corra antes do getty tty1 (boot/live).
install -d "$AIROOT/etc/systemd/system/multi-user.target.wants"
ln -sfn ../wolf-live-user.service "$AIROOT/etc/systemd/system/multi-user.target.wants/wolf-live-user.service"

# mkarchiso aplica permissões em staging; indispensável para sudoers e scripts.
python3 - "$PROFILEDEF" <<'PY_PERMS'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); t=p.read_text(encoding="utf-8")
required={
    "/usr/local/bin/wolf-live-create-user": "0:0:755",
    "/usr/local/bin/wolf-live-installer": "0:0:755",
    "/usr/local/bin/wolf-live-network": "0:0:755",
    "/usr/local/bin/wolf-live-review-plan": "0:0:755",
    "/usr/local/bin/wolf-live-simulate-plan": "0:0:755",
    "/usr/local/bin/wolf-live-execute-vm-plan": "0:0:755",
    "/usr/local/bin/wolf-live-gparted": "0:0:755",
    "/usr/local/bin/wolf-live-diagnostics": "0:0:755",
    "/etc/sudoers.d/90-wolf-live": "0:0:440",
    "/usr/share/wolf-live/home/.xinitrc": "0:0:755",
    "/usr/share/wolf-live/home/.config/openbox/autostart": "0:0:755",
}
m=re.search(r'file_permissions=\(\s*(.*?)\s*\)',t,flags=re.S)
if not m:
    t += "\nfile_permissions=(\n)\n"
    m=re.search(r'file_permissions=\(\s*(.*?)\s*\)',t,flags=re.S)
block=m.group(0)
for dest,mode in required.items():
    pattern=re.compile(rf'^\s*\["{re.escape(dest)}"\]="[^"]*"\s*$',flags=re.M)
    line=f'  ["{dest}"]="{mode}"'
    block=pattern.sub(line,block) if pattern.search(block) else block[:-1].rstrip()+"\n"+line+"\n)"
p.write_text(t[:m.start()]+block+t[m.end():], encoding="utf-8")
PY_PERMS

[[ -x "$AIROOT/usr/local/bin/wolf-live-installer" ]] || { echo '[ERRO] wrapper Wolf Live ausente.' >&2; exit 1; }
[[ -L "$AIROOT/etc/systemd/system/multi-user.target.wants/wolf-live-user.service" ]] || { echo '[ERRO] Serviço live não habilitado.' >&2; exit 1; }
echo '[OK] Wolf Live GUI 0.9 no airootfs (execução VM descartável sob confirmação separada).'
