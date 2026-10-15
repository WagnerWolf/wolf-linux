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
# Migração alpha36 -> alpha37: não deixar Firefox na imagem após restaging.
# Remove apenas linhas de pacotes do perfil Live, jamais mexe nas stacks alvo.
sed -i '/^firefox$/d; /^firefox-i18n-pt-br$/d' "$PACKAGES"
LIVE_GUI_PACKAGES=(
    openbox xorg-server xorg-xinit xorg-xauth xorg-xrandr xorg-xsetroot
    xf86-input-libinput xf86-video-vesa xf86-video-fbdev mesa
    pyside6 python qterminal pcmanfm-qt feh gparted sudo dbus
    networkmanager network-manager-applet nm-connection-editor stalonetray lxqt-policykit lvm2
    chromium bluez bluez-utils blueman rfkill efibootmgr gvfs udisks2 udisks2-lvm2 ntfs-3g exfatprogs e2fsprogs
    xorg-setxkbmap xorg-fonts-misc
)
for pkg in "${LIVE_GUI_PACKAGES[@]}"; do
    grep -Fxq "$pkg" "$PACKAGES" || printf '%s\n' "$pkg" >> "$PACKAGES"
done

install -Dm0755 "$SOURCE/wolf-live-create-user" "$AIROOT/usr/local/bin/wolf-live-create-user"
# Laboratorio QEMU alpha41: somente discos VirtIO com seriais exclusivos.
install -Dm0755 "$PROJECT/tests/wolf-lab41-particionar.sh" "$AIROOT/usr/local/bin/wolf-lab41-particionar"
install -Dm0755 "$PROJECT/tests/wolf-lab41-verificar.sh" "$AIROOT/usr/local/bin/wolf-lab41-verificar"
install -Dm0755 "$SOURCE/wolf-home-preview-live" "$AIROOT/usr/local/bin/wolf-home-preview-live"
install -Dm0755 "$SOURCE/wolf-live-gparted" "$AIROOT/usr/local/bin/wolf-live-gparted"
install -Dm0755 "$SOURCE/wolf-live-diagnostics" "$AIROOT/usr/local/bin/wolf-live-diagnostics"
install -Dm0755 "$SOURCE/wolf-boot-diagnose" "$AIROOT/usr/local/bin/wolf-boot-diagnose"
install -Dm0755 "$SOURCE/wolf-live-storage-topology" "$AIROOT/usr/local/bin/wolf-live-storage-topology"
install -Dm0755 "$SOURCE/wolf-physical-preflight" "$AIROOT/usr/local/bin/wolf-physical-preflight"
install -Dm0755 "$SOURCE/wolf-live-time-status" "$AIROOT/usr/local/bin/wolf-live-time-status"
install -Dm0755 "$SOURCE/wolf-live-browser" "$AIROOT/usr/local/bin/wolf-live-browser"
install -Dm0755 "$SOURCE/wolf-live-rescue" "$AIROOT/usr/local/bin/wolf-live-rescue"
install -Dm0755 "$SOURCE/wolf-live-rescue-report" "$AIROOT/usr/local/bin/wolf-live-rescue-report"
install -Dm0644 "$SOURCE/wolf_rescue.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/wolf_rescue.py"
install -Dm0644 "$SOURCE/wolf_storage_map.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/wolf_storage_map.py"
install -Dm0644 "$SOURCE/wolf_discovery.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/wolf_discovery.py"
install -Dm0644 "$SOURCE/wolf_discovery.py" "$AIROOT/root/wolf-linux/live-gui/wolf_discovery.py"
install -Dm0644 "$SOURCE/wolf_physical_rehearsal.py" "$AIROOT/root/wolf-linux/live-gui/wolf_physical_rehearsal.py"
install -Dm0644 "$SOURCE/wolf_physical_executor.py" "$AIROOT/root/wolf-linux/live-gui/wolf_physical_executor.py"
install -Dm0644 "$SOURCE/wolf_home_cleanup.py" "$AIROOT/root/wolf-linux/live-gui/wolf_home_cleanup.py"
install -Dm0644 "$SOURCE/wolf_home_cleanup.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/wolf_home_cleanup.py"
install -Dm0644 "$SOURCE/wolf_lab42.py" "$AIROOT/root/wolf-linux/live-gui/wolf_lab42.py"
install -Dm0644 "$SOURCE/wolf_home_identity.py" "$AIROOT/root/wolf-linux/live-gui/wolf_home_identity.py"
install -Dm0644 "$SOURCE/wolf_storage_map.py" "$AIROOT/root/wolf-linux/live-gui/wolf_storage_map.py"
install -Dm0644 "$SOURCE/wolf-live-udisks-polkit.rules" "$AIROOT/etc/polkit-1/rules.d/50-wolf-live-udisks.rules"
# Remove artefatos de revisões anteriores após atualizações de staging.
rm -f "$AIROOT/usr/local/bin/wolf-live-mount-manager" "$AIROOT/usr/local/bin/wolf-live-mount-backend" \
      "$AIROOT/usr/local/share/wolf-linux-live/mount_manager.py" \
      "$AIROOT/usr/local/share/wolf-linux-live/mount_backend.py"
install -Dm0755 "$SOURCE/wolf-live-installer" "$AIROOT/usr/local/bin/wolf-live-installer"
rm -f "$AIROOT/usr/local/bin/wolf-live-installer-classic"
install -Dm0644 "$SOURCE/preview/app.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/preview/app.py"
install -Dm0644 "$SOURCE/preview/planner.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/preview/planner.py"
install -Dm0644 "$SOURCE/preview/vm_bridge.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/preview/vm_bridge.py"
install -Dm0755 "$SOURCE/wolf-live-review-plan" "$AIROOT/usr/local/bin/wolf-live-review-plan"
install -Dm0755 "$SOURCE/wolf-live-simulate-plan" "$AIROOT/usr/local/bin/wolf-live-simulate-plan"
install -Dm0755 "$SOURCE/wolf-live-physical-rehearsal" "$AIROOT/usr/local/bin/wolf-live-physical-rehearsal"
install -Dm0755 "$SOURCE/wolf-live-execute-vm-plan" "$AIROOT/usr/local/bin/wolf-live-execute-vm-plan"
install -Dm0755 "$SOURCE/wolf-live-cleanup-vm" "$AIROOT/usr/local/bin/wolf-live-cleanup-vm"
install -Dm0755 "$SOURCE/wolf-live-network" "$AIROOT/usr/local/bin/wolf-live-network"
install -Dm0644 "$SOURCE/main.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/main.py"
install -Dm0644 "$SOURCE/terminal_engine.py" "$AIROOT/usr/local/share/wolf-linux-live/gui/terminal_engine.py"
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
# Relógio correto é essencial para TOTP/2FA; serviço só sincroniza com rede ativa.
install -d "$AIROOT/etc/systemd/system/sysinit.target.wants"
ln -sfn /usr/lib/systemd/system/systemd-timesyncd.service \
    "$AIROOT/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service"
# Bluetooth inicia somente na Live. Sem adaptador, o daemon permanece inofensivo.
ln -sfn /usr/lib/systemd/system/bluetooth.service \
    "$AIROOT/etc/systemd/system/multi-user.target.wants/bluetooth.service"
# UDisks2 é ativado sob demanda pelo D-Bus/GVfs; não há automontagem.

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
    "/usr/local/bin/wolf-lab41-particionar": "0:0:755",
    "/usr/local/bin/wolf-lab41-verificar": "0:0:755",
    "/usr/local/bin/wolf-live-installer": "0:0:755",
    "/usr/local/bin/wolf-live-network": "0:0:755",
    "/usr/local/bin/wolf-live-review-plan": "0:0:755",
    "/usr/local/bin/wolf-live-simulate-plan": "0:0:755",
    "/usr/local/bin/wolf-live-physical-rehearsal": "0:0:755",
    "/usr/local/bin/wolf-live-execute-vm-plan": "0:0:755",
    "/usr/local/bin/wolf-live-cleanup-vm": "0:0:755",
    "/usr/local/bin/wolf-live-gparted": "0:0:755",
    "/usr/local/bin/wolf-home-preview-live": "0:0:755",
    "/usr/local/bin/wolf-live-storage-topology": "0:0:755",
    "/usr/local/bin/wolf-physical-preflight": "0:0:755",
    "/usr/local/bin/wolf-live-time-status": "0:0:755",
    "/usr/local/bin/wolf-live-browser": "0:0:755",
    "/usr/local/bin/wolf-live-rescue": "0:0:755",
    "/usr/local/bin/wolf-live-rescue-report": "0:0:755",
    "/etc/polkit-1/rules.d/50-wolf-live-udisks.rules": "0:0:644",
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
echo '[OK] Wolf Live: instalador integrado e único; executor clássico permanece somente no código-fonte.'
