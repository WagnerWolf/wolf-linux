#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
PROFILE="${WOLF_ISO_PROFILE:-$PROJECT/iso-profile}"
AIROOT="$PROFILE/airootfs"
VERSION_FILE="$PROJECT/VERSION"
[[ -r "$VERSION_FILE" ]] || { echo "[ERRO] VERSION do projeto não encontrado: $VERSION_FILE" >&2; exit 1; }
DEVKIT_VERSION="$(< "$VERSION_FILE")"
[[ "$DEVKIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?$ ]] || {
    printf '[ERRO] VERSION inválido no projeto: %q\n' "$DEVKIT_VERSION" >&2
    exit 1
}

[[ -d "$PROFILE" ]] || { echo "[ERRO] Perfil Archiso não encontrado: $PROFILE"; exit 1; }
[[ -f "$PROJECT/install/wolf-install.sh" ]] || { echo "[ERRO] Instalador ausente."; exit 1; }
[[ -f "$PROJECT/package-profiles/packages.conf" ]] || { echo "[ERRO] Manifesto ausente."; exit 1; }
[[ -d "$PROJECT/tools" ]] || { echo "[ERRO] Diretório tools ausente."; exit 1; }

echo "======================================================"
echo "   WOLF LINUX 2.1 - CUSTOMIZAÇÃO ISO KDE BASELINE"
echo "======================================================"

mkdir -p \
    "$AIROOT/etc/systemd/system/multi-user.target.wants" \
    "$AIROOT/root/wolf-linux/install" \
    "$AIROOT/root/wolf-linux/package-profiles" \
    "$AIROOT/root/wolf-linux/tools" \
    "$AIROOT/root/wolf-linux/tests" \
    "$AIROOT/root/wolf-linux/assets" \
    "$AIROOT/usr/local/bin"

# Remove resíduos de autostarts Wolf de perfis antigos. A baseline 2.0
# transporta helpers, mas não os executa automaticamente.
mkdir -p "$AIROOT/etc/xdg/autostart"
find "$AIROOT/etc/xdg/autostart" -maxdepth 1 -type f -name 'wolf-*.desktop' -delete 2>/dev/null || true

cat > "$AIROOT/etc/vconsole.conf" <<'VC'
KEYMAP=br-abnt2
FONT=ter-v16n
VC

cat > "$AIROOT/etc/systemd/system/wolf-loadkeys.service" <<'UNIT'
[Unit]
Description=Wolf Linux - teclado BR-ABNT2 na ISO live
After=systemd-vconsole-setup.service
Before=getty@tty1.service
[Service]
Type=oneshot
ExecStart=/usr/bin/loadkeys br-abnt2
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
ln -sfn ../wolf-loadkeys.service "$AIROOT/etc/systemd/system/multi-user.target.wants/wolf-loadkeys.service"

cat > "$AIROOT/etc/os-release" <<'OSR'
NAME="Wolf Linux Live"
VERSION="2.1"
VERSION_ID="2.1.2"
PRETTY_NAME="Wolf Linux 2.1 Live"
ID=wolf-linux
ID_LIKE=arch
VARIANT="Wolf Linux 2.1 Live Graphical Installer"
VARIANT_ID=wolf-linux-live
BUILD_ID=rolling
ANSI_COLOR="1;37"
OSR
cat > "$AIROOT/etc/issue" <<'ISSUE'
Wolf Linux Live — instalacao e recuperacao  \n \l
ISSUE
cat > "$AIROOT/etc/motd" <<'MOTD'
Wolf Linux Live — abra Wolf Installer para iniciar a instalacao grafica.
O instalador CLI continua disponivel com sudo wolf-install --help.
MOTD
printf '%s\n' wolf-live > "$AIROOT/etc/hostname"
printf 'Wolf Linux %s KDE/Wayland Clean Baseline\n' "$DEVKIT_VERSION" > "$AIROOT/etc/wolf-linux-live-build"
cp -f "$VERSION_FILE" "$AIROOT/root/wolf-linux/VERSION"

cp -f "$PROJECT/install/wolf-install.sh" "$AIROOT/root/wolf-linux/install/wolf-install.sh"
cp -f "$PROJECT/package-profiles/packages.conf" "$AIROOT/root/wolf-linux/package-profiles/packages.conf"
rm -rf "$AIROOT/root/wolf-linux/tools"
cp -a "$PROJECT/tools" "$AIROOT/root/wolf-linux/tools"
find "$AIROOT/root/wolf-linux/tools" -type f -name '*.sh' -exec chmod 755 {} +

rm -rf "$AIROOT/root/wolf-linux/assets"
mkdir -p "$AIROOT/root/wolf-linux/assets"
[[ -d "$PROJECT/assets" ]] && cp -a "$PROJECT/assets/." "$AIROOT/root/wolf-linux/assets/"
chmod 755 "$AIROOT/root/wolf-linux/install/wolf-install.sh"

cat > "$AIROOT/usr/local/bin/wolf-install" <<'WRAP'
#!/usr/bin/env bash
set -Eeuo pipefail
export WOLF_PACKAGES_FILE="/root/wolf-linux/package-profiles/packages.conf"
export WOLF_ASSET_DIR="/root/wolf-linux/assets"
needs_mode=1
for arg in "$@"; do
    case "$arg" in
        --install|--vm-install|--dry-run|--plan-only|--review-gui-plan|--simulate-gui-plan|--review-multidisk-plan|--simulate-multidisk-plan|--rehearse-multidisk-physical|--preflight-multidisk-physical|--execute-multidisk-physical|--preflight-multidisk-lab-vm|--execute-multidisk-lab-vm|--preflight-gui-plan-vm|--execute-gui-plan-vm|--execute-gui-plan-vm-click|--list-stacks|--reset-state|-h|--help) needs_mode=0 ;;
        --full|--test|--minimal|--preset|--stacks) ;; # Seleções do instalador interativo legado.
        --*|-*) echo "[ERRO] Opção desconhecida do lançador Wolf: $arg" >&2; exit 2 ;;
    esac
done
if (( needs_mode == 1 )); then
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    case "$virt" in
        qemu|kvm|oracle|virtualbox|vbox) set -- --vm-install "$@" ;;
        *) set -- --install "$@" ;;
    esac
fi
exec /root/wolf-linux/install/wolf-install.sh "$@"
WRAP
chmod 755 "$AIROOT/usr/local/bin/wolf-install"

cp -f "$PROJECT/tests/wolf-enable-ssh-live.sh" "$AIROOT/root/wolf-linux/tests/wolf-enable-ssh-live.sh"
chmod 755 "$AIROOT/root/wolf-linux/tests/wolf-enable-ssh-live.sh"
# Usado pelo instalador no estágio pós-pacotes (painel sem Discover).
install -m 0644 \
    "$PROJECT/tests/wolf-prune-discover-launchers.py" \
    "$AIROOT/root/wolf-linux/tests/wolf-prune-discover-launchers.py"
install -m 0644 \
    "$PROJECT/tests/wolf-configure-user-defaults.py" \
    "$AIROOT/root/wolf-linux/tests/wolf-configure-user-defaults.py"
install -Dm0755 \
    "$PROJECT/tests/wolf-enable-ssh-live.sh" \
    "$AIROOT/usr/local/bin/wolf-enable-ssh-live"
ln -sfn wolf-enable-ssh-live "$AIROOT/usr/local/bin/wolf-ssh"

cat > "$AIROOT/root/.zprofile" <<'ZP'
loadkeys br-abnt2 2>/dev/null || true
echo
echo "============================================================"
echo "             $(cat /etc/wolf-linux-live-build)"
echo "============================================================"
echo "Instalador: wolf-install"
echo "Full .....: wolf-install --full"
echo "Test .....: wolf-install --test"
echo "Basic ....: wolf-install --basic"
echo "Minimal ..: wolf-install --minimal"
echo "Stacks ...: wolf-install --list-stacks"
echo "SSH .......: wolf-enable-ssh-live  (alias: wolf-ssh)"
echo "============================================================"
echo
ZP

PACKAGES_FILE="$PROFILE/packages.x86_64"
touch "$PACKAGES_FILE"
LIVE_PACKAGES=(arch-install-scripts curl dosfstools e2fsprogs git gptfdisk iwd kbd libarchive lvm2 networkmanager openssh parted pciutils python terminus-font)
for pkg in "${LIVE_PACKAGES[@]}"; do grep -Fxq "$pkg" "$PACKAGES_FILE" || printf '%s\n' "$pkg" >> "$PACKAGES_FILE"; done

PROFILEDEF="$PROFILE/profiledef.sh"
if [[ -f "$PROFILEDEF" ]]; then
python - "$PROFILEDEF" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); t=p.read_text()
for k,v in {
    'iso_name':'"wolf-linux"',
    'iso_label':'"WOLFLINUX_$(date +%Y%m)"',
    'iso_publisher':'"Wolf Linux"',
    'iso_application':'"Wolf Linux 2.1 Graphical Live Installer"',
}.items():
    pat=rf'^{re.escape(k)}=.*$'; line=f'{k}={v}'
    t=re.sub(pat,line,t,flags=re.M) if re.search(pat,t,flags=re.M) else t+'\n'+line+'\n'
req={
 '/usr/local/bin/wolf-install':'0:0:755',
 '/usr/local/bin/wolf-enable-ssh-live':'0:0:755',
 '/root/wolf-linux/install/wolf-install.sh':'0:0:755',
 '/root/wolf-linux/tests/wolf-enable-ssh-live.sh':'0:0:755',
 '/root/wolf-linux/tools/wolf-helper-manager-0.2.sh':'0:0:755',
 '/root/wolf-linux/tools/wolf-validate-helpers-0.1.sh':'0:0:755',
 '/root/wolf-linux/tools/stable/wolf-grub-manager-0.3.sh':'0:0:755',
 '/root/wolf-linux/tools/stable/wolf-gamepad-setup-0.3.sh':'0:0:755',
 '/root/wolf-linux/tools/experimental/wolf-plasma-branding-0.2.sh':'0:0:755',
 '/root/wolf-linux/tools/experimental/wolf-plasma-multimonitor-0.3.sh':'0:0:755',
}
m=re.search(r'file_permissions=\(\s*(.*?)\s*\)',t,flags=re.S)
if m:
    block=m.group(0)
    for path,mode in req.items():
        pat=re.compile(rf'^\s*\["{re.escape(path)}"\]="[^"]*"\s*$',flags=re.M)
        entry=f'  ["{path}"]="{mode}"'
        block=pat.sub(entry,block) if pat.search(block) else block[:-1].rstrip()+'\n'+entry+'\n)'
    t=t[:m.start()]+block+t[m.end():]
else:
    t+='\nfile_permissions=(\n'+''.join(f'  ["{p}"]="{m}"\n' for p,m in req.items())+')\n'
p.write_text(t)
PY
fi

# Branding de títulos GRUB/Syslinux/loader somente em strings visíveis.
# Conserva os nomes técnicos archiso necessários ao boot.
python3 "$PROJECT/tests/wolf-brand-live-boot.py" "$PROFILE" --assets "$PROJECT/assets"

# O estágio final é a fonte de verdade para o SSH live. Ele é idempotente e
# também é chamado novamente pelo build imediatamente antes do mkarchiso.
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROFILE" "$PROJECT/tests/wolf-stage-live-ssh.sh"
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROFILE" "$PROJECT/tests/wolf-stage-live-desktop.sh"

[[ -x "$AIROOT/usr/local/bin/wolf-enable-ssh-live" ]] || { echo "[ERRO] SSH live não foi instalado no airootfs." >&2; exit 1; }
[[ -L "$AIROOT/usr/local/bin/wolf-ssh" ]] || { echo "[ERRO] Alias wolf-ssh ausente no airootfs." >&2; exit 1; }
grep -Fxq openssh "$PACKAGES_FILE" || { echo "[ERRO] openssh ausente de packages.x86_64." >&2; exit 1; }

echo "[OK] Perfil ISO Wolf Live GUI 2.0 e identidade do boot; backend KDE/Wayland preservado."
