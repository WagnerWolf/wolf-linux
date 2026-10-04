#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
PROFILE="$PROJECT/iso-profile"
AIROOT="$PROFILE/airootfs"

[[ -d "$PROFILE" ]] || {
    echo "[ERRO] Perfil Archiso não encontrado: $PROFILE"
    exit 1
}

[[ -f "$PROJECT/install/wolf-install.sh" ]] || {
    echo "[ERRO] Instalador não encontrado em $PROJECT/install/wolf-install.sh"
    exit 1
}

[[ -f "$PROJECT/package-profiles/packages.conf" ]] || {
    echo "[ERRO] Manifesto não encontrado."
    exit 1
}

echo "======================================================"
echo "        WOLF LINUX - CUSTOMIZAÇÃO DA ISO"
echo "======================================================"

mkdir -p \
    "$AIROOT/etc/systemd/system/multi-user.target.wants" \
    "$AIROOT/etc" \
    "$AIROOT/root/wolf-linux/install" \
    "$AIROOT/root/wolf-linux/package-profiles" \
    "$AIROOT/root/wolf-linux/assets" \
    "$AIROOT/usr/local/bin"

# ------------------------------------------------------------
# 1. Teclado brasileiro desde o início da ISO live
# ------------------------------------------------------------
cat > "$AIROOT/etc/vconsole.conf" <<'EOF'
KEYMAP=br-abnt2
FONT=ter-v16n
EOF

cat > "$AIROOT/etc/systemd/system/wolf-loadkeys.service" <<'EOF'
[Unit]
Description=Wolf Linux - aplicar teclado BR-ABNT2 na ISO live
After=systemd-vconsole-setup.service
Before=getty@tty1.service

[Service]
Type=oneshot
ExecStart=/usr/bin/loadkeys br-abnt2
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

ln -sfn \
    ../wolf-loadkeys.service \
    "$AIROOT/etc/systemd/system/multi-user.target.wants/wolf-loadkeys.service"

# ------------------------------------------------------------
# 2. Identidade do ambiente live
# ID continua arch para manter compatibilidade.
# ------------------------------------------------------------
cat > "$AIROOT/etc/os-release" <<'EOF'
NAME="Wolf Linux Live"
PRETTY_NAME="Wolf Linux Live"
ID=arch
ID_LIKE=arch
VARIANT="Wolf Linux Installer"
VARIANT_ID=wolf-linux-live
BUILD_ID=rolling
ANSI_COLOR="1;37"
HOME_URL="https://archlinux.org/"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
EOF

cat > "$AIROOT/etc/hostname" <<'EOF'
wolf-live
EOF

cat > "$AIROOT/etc/issue" <<'EOF'
Wolf Linux Live \r (\l)

Execute: wolf-install

EOF

# ------------------------------------------------------------
# 3. Instalador, manifesto e assets dentro da ISO
# ------------------------------------------------------------
cp -f \
    "$PROJECT/install/wolf-install.sh" \
    "$AIROOT/root/wolf-linux/install/wolf-install.sh"

cp -f \
    "$PROJECT/package-profiles/packages.conf" \
    "$AIROOT/root/wolf-linux/package-profiles/packages.conf"

rm -rf "$AIROOT/root/wolf-linux/assets"
mkdir -p "$AIROOT/root/wolf-linux/assets"

if [[ -d "$PROJECT/assets" ]]; then
    cp -a "$PROJECT/assets/." "$AIROOT/root/wolf-linux/assets/"
fi

chmod 755 "$AIROOT/root/wolf-linux/install/wolf-install.sh"

cat > "$AIROOT/usr/local/bin/wolf-install" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

export WOLF_PACKAGES_FILE="/root/wolf-linux/package-profiles/packages.conf"
export WOLF_ASSET_DIR="/root/wolf-linux/assets"

if (($# == 0)); then
    virt="$(systemd-detect-virt 2>/dev/null || true)"

    case "$virt" in
        qemu|kvm)
            set -- --vm-install
            ;;
        *)
            set -- --install
            ;;
    esac
fi

exec /root/wolf-linux/install/wolf-install.sh "$@"
EOF

chmod 755 "$AIROOT/usr/local/bin/wolf-install"


# ------------------------------------------------------------
# 3b. Branding do GRUB da mídia live (principalmente boot BIOS)
# ------------------------------------------------------------
if [[ -f "$PROJECT/assets/grub/background.png" ]]; then
    mkdir -p "$PROFILE/grub"

    cp -f \
        "$PROJECT/assets/grub/background.png" \
        "$PROFILE/grub/wolf-linux-background.png"

    for grub_cfg in \
        "$PROFILE/grub/grub.cfg" \
        "$PROFILE/grub/loopback.cfg"
    do
        [[ -f "$grub_cfg" ]] || continue

        python - "$grub_cfg" <<'PYGRUB'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

begin = "# WOLF-LINUX-GRUB-BRANDING-BEGIN"
end = "# WOLF-LINUX-GRUB-BRANDING-END"

block = """# WOLF-LINUX-GRUB-BRANDING-BEGIN
insmod png
if background_image /grub/wolf-linux-background.png; then
  set color_normal=light-gray/black
  set color_highlight=white/dark-gray
fi
# WOLF-LINUX-GRUB-BRANDING-END

"""

# Idempotência: substitui um bloco Wolf antigo, caso exista.
if begin in text and end in text:
    before, rest = text.split(begin, 1)
    _, after = rest.split(end, 1)
    text = before + block + after.lstrip("\n")
else:
    # Preferimos inserir depois do carregamento da fonte do GRUB.
    marker = "loadfont unicode\n"
    if marker in text:
        text = text.replace(marker, marker + block, 1)
    else:
        text = block + text

path.write_text(text, encoding="utf-8")
PYGRUB
    done
fi

# Mensagem de boas-vindas no shell da ISO. Não sobrescreve .zshrc do releng.
cat > "$AIROOT/root/.zprofile" <<'EOF'
loadkeys br-abnt2 2>/dev/null || true

echo
echo "============================================================"
echo "                    WOLF LINUX LIVE"
echo "============================================================"
echo "Teclado ........: BR-ABNT2"
echo "Instalador .....: wolf-install"
echo "Plano seguro ...: wolf-install --dry-run"
echo "============================================================"
echo
EOF

# ------------------------------------------------------------
# 4. Pacotes necessários no live environment
# ------------------------------------------------------------
PACKAGES_FILE="$PROFILE/packages.x86_64"

touch "$PACKAGES_FILE"

LIVE_PACKAGES=(
    arch-install-scripts
    curl
    dosfstools
    e2fsprogs
    git
    gptfdisk
    iwd
    kbd
    libarchive
    lvm2
    networkmanager
    parted
    pciutils
    terminus-font
)

for pkg in "${LIVE_PACKAGES[@]}"; do
    grep -Fxq "$pkg" "$PACKAGES_FILE" ||
        printf '%s\n' "$pkg" >> "$PACKAGES_FILE"
done

# ------------------------------------------------------------
# 5. Nome/descrição da ISO
# ------------------------------------------------------------
PROFILEDEF="$PROFILE/profiledef.sh"

if [[ -f "$PROFILEDEF" ]]; then
    python - "$PROFILEDEF" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

replacements = {
    "iso_name": '"wolf-linux"',
    "iso_label": '"WOLFLINUX_$(date +%Y%m)"',
    "iso_publisher": '"Wolf Linux"',
    "iso_application": '"Wolf Linux Live/Installer"',
}

for key, value in replacements.items():
    pattern = rf"^{re.escape(key)}=.*$"
    line = f"{key}={value}"

    if re.search(pattern, text, flags=re.M):
        text = re.sub(pattern, line, text, flags=re.M)
    else:
        text += "\n" + line + "\n"

# Archiso does not reliably preserve executable bits from airootfs just
# because the source file is chmod +x. Executable permissions must be
# declared in profiledef.sh's file_permissions associative array.
required_permissions = {
    "/usr/local/bin/wolf-install": "0:0:755",
    "/root/wolf-linux/install/wolf-install.sh": "0:0:755",
}

perm_block = re.search(
    r"file_permissions=\(\s*(.*?)\s*\)",
    text,
    flags=re.S,
)

if perm_block:
    block = perm_block.group(0)

    for file_path, mode in required_permissions.items():
        entry_re = re.compile(
            rf'^\s*\["{re.escape(file_path)}"\]="[^"]*"\s*$',
            flags=re.M,
        )
        entry = f'  ["{file_path}"]="{mode}"'

        if entry_re.search(block):
            block = entry_re.sub(entry, block)
        else:
            block = block[:-1].rstrip() + "\n" + entry + "\n)"

    text = text[:perm_block.start()] + block + text[perm_block.end():]
else:
    text += "\n\nfile_permissions=(\n"
    for file_path, mode in required_permissions.items():
        text += f'  ["{file_path}"]="{mode}"\n'
    text += ")\n"

path.write_text(text, encoding="utf-8")
PY
fi

# Validação das permissões executáveis que o mkarchiso aplicará.
if [[ -f "$PROFILEDEF" ]]; then
    grep -Fq '["/usr/local/bin/wolf-install"]="0:0:755"' "$PROFILEDEF" \
        || {
            echo "[ERRO] profiledef.sh não contém permissão 755 para wolf-install."
            exit 1
        }

    grep -Fq '["/root/wolf-linux/install/wolf-install.sh"]="0:0:755"' "$PROFILEDEF" \
        || {
            echo "[ERRO] profiledef.sh não contém permissão 755 para wolf-install.sh."
            exit 1
        }
fi

# ------------------------------------------------------------
# 6. Texto dos menus de boot da ISO
# ------------------------------------------------------------
while IFS= read -r -d '' file; do
    sed -i \
        -e 's/Arch Linux install medium/Wolf Linux Installer/g' \
        -e 's/Arch Linux Install Medium/Wolf Linux Installer/g' \
        "$file"
done < <(
    grep -rilZ \
        --include='*.cfg' \
        --include='*.conf' \
        --include='*.sh' \
        'Arch Linux install medium' \
        "$PROFILE/grub" \
        "$PROFILE/efiboot" \
        "$PROFILE/syslinux" \
        2>/dev/null || true
)

echo
echo "[OK] Perfil Archiso personalizado."
echo "  Nome ISO ......: wolf-linux"
echo "  Live OS .......: Wolf Linux Live"
echo "  Teclado .......: br-abnt2"
echo "  Instalador ....: wolf-install"
echo "  Permissões ....: wolf-install=755 / instalador=755"
if [[ -f "$PROFILE/grub/wolf-linux-background.png" ]]; then
    echo "  GRUB BIOS .....: fundo Wolf Linux aplicado"
fi
