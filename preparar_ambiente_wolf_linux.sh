#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${HOME}/wolf-linux"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================================"
echo "       WOLF LINUX - AMBIENTE DE DESENVOLVIMENTO"
echo "======================================================"

echo "[1/6] Instalando ferramentas..."
sudo pacman -S --needed \
    archiso \
    qemu-desktop \
    edk2-ovmf \
    shellcheck \
    git \
    python

echo "[2/6] Criando estrutura..."
mkdir -p \
    "$PROJECT/install/lib" \
    "$PROJECT/package-profiles" \
    "$PROJECT/assets/grub" \
    "$PROJECT/assets/plymouth" \
    "$PROJECT/assets/sddm" \
    "$PROJECT/assets/wallpapers" \
    "$PROJECT/assets/zsh" \
    "$PROJECT/tests" \
    "$PROJECT/vm" \
    "$PROJECT/out" \
    "$PROJECT/work"

if [[ ! -d "$PROJECT/iso-profile" ]]; then
    echo "[3/6] Copiando perfil releng..."
    cp -a /usr/share/archiso/configs/releng "$PROJECT/iso-profile"
else
    echo "[3/6] iso-profile já existe; preservando."
fi

echo "[4/6] Instalando arquivos do DevKit..."

for helper in wolf-build-iso.sh wolf-test-iso.sh wolf-smoke-test.sh wolf-serve.sh wolf-run-arch-test.sh wolf-enable-ssh-live.sh wolf-vm-ssh.sh wolf-fix-mate-v0.27.sh wolf-fix-mate-panel-v0.28.sh wolf-restore-known-good-panel-v0.29.sh wolf-theme-lab-v0.30.sh wolf-theme-lab-v0.31.sh wolf-fix-numlock-coco-v0.31.sh wolf-theme-bases-v0.32.sh wolf-apply-final-mate-theme-v0.33.sh wolf-customize-iso-profile.sh wolf-desktop-extras-v0.36.sh wolf-final-polish-v0.37.sh wolf-fix-fastfetch-startup-v0.38.sh wolf-fix-terminal-width-v0.39.sh wolf-fix-terminal-width-v0.40.sh wolf-fix-tty-v0.41.sh wolf-finalize-1.0.sh wolf-fix-mouse-no-accel-1.0.2.sh wolf-remove-window-mover-1.0.6.sh; do    cp -f "$SELF_DIR/$helper" "$PROJECT/tests/$helper"
    chmod 755 "$PROJECT/tests/$helper"
done

cp -f "$SELF_DIR/wolf-install.sh" "$PROJECT/install/wolf-install.sh"
chmod 755 "$PROJECT/install/wolf-install.sh"

if [[ -f "$SELF_DIR/wolf-linux-packages-v0.1.conf" ]]; then
    cp -f "$SELF_DIR/wolf-linux-packages-v0.1.conf" \
        "$PROJECT/package-profiles/packages.conf"
fi

if [[ -f "$SELF_DIR/wolf-linux-logo.png" ]]; then
    cp -f "$SELF_DIR/wolf-linux-logo.png" \
        "$PROJECT/assets/wallpapers/wolf-linux-logo.png"
fi

if [[ -f "$SELF_DIR/wolf-p10k.zsh" ]]; then
    cp -f "$SELF_DIR/wolf-p10k.zsh" \
        "$PROJECT/assets/zsh/p10k.zsh"
fi

# Se já existe um projeto validado em hardware, preserve a logo do
# Plymouth. Isso evita substituir a versão transparente já aprovada.
PLYMOUTH_KEEP=""
if [[ -f "$PROJECT/assets/plymouth/logo.png" ]]; then
    PLYMOUTH_KEEP="$(mktemp --suffix=.png)"
    cp -f "$PROJECT/assets/plymouth/logo.png" "$PLYMOUTH_KEEP"
elif [[ -f /usr/share/plymouth/themes/wolf-linux/logo.png ]]; then
    # Em uma reinstalação do ambiente de desenvolvimento, aproveita a logo
    # já validada no sistema em uso (a versão transparente aprovada).
    PLYMOUTH_KEEP="$(mktemp --suffix=.png)"
    cp -f /usr/share/plymouth/themes/wolf-linux/logo.png "$PLYMOUTH_KEEP"
    echo "[OK] Logo Plymouth validada encontrada no sistema atual."
fi

if [[ -d "$SELF_DIR/branding-assets" ]]; then
    cp -a "$SELF_DIR/branding-assets/." "$PROJECT/assets/"
fi

if [[ -n "$PLYMOUTH_KEEP" && -f "$PLYMOUTH_KEEP" ]]; then
    cp -f "$PLYMOUTH_KEEP" "$PROJECT/assets/plymouth/logo.png"
    rm -f "$PLYMOUTH_KEEP"
    echo "[OK] Logo transparente existente do Plymouth preservada."
fi

echo "[5/6] Personalizando perfil da ISO Wolf Linux..."
"$PROJECT/tests/wolf-customize-iso-profile.sh"

echo "[6/6] Verificando KVM..."
if [[ -e /dev/kvm ]]; then
    echo "[OK] /dev/kvm disponível."
else
    echo "[AVISO] /dev/kvm não encontrado."
fi

cat <<EOF

Ambiente pronto em:
  $PROJECT

Primeiro teste:
  cd "$PROJECT"
  ./tests/wolf-smoke-test.sh

Teste seguro do instalador no computador atual:
  ./install/wolf-install.sh --dry-run

EOF
