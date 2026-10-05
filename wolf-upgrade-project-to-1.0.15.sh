#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-${WOLF_PROJECT:-$HOME/wolf-linux}}"

echo "============================================================"
echo "         WOLF LINUX - UPGRADE DO PROJETO PARA 1.0.15"
echo "============================================================"
echo
echo "Projeto: $PROJECT"
echo "assets/ será preservado."
echo

[[ -d "$PROJECT" ]] || {
    echo "[ERRO] Projeto não encontrado: $PROJECT"
    exit 1
}

mkdir -p "$PROJECT/install" "$PROJECT/package-profiles" "$PROJECT/tests"

cp -f "$SELF_DIR/wolf-install.sh" "$PROJECT/install/wolf-install.sh"
chmod 755 "$PROJECT/install/wolf-install.sh"

cp -f "$SELF_DIR/wolf-linux-packages-v0.1.conf" \
    "$PROJECT/package-profiles/packages.conf"

for helper in \
    wolf-build-iso.sh \
    wolf-test-iso.sh \
    wolf-smoke-test.sh \
    wolf-serve.sh \
    wolf-run-arch-test.sh \
    wolf-enable-ssh-live.sh \
    wolf-vm-ssh.sh \
    wolf-customize-iso-profile.sh \
    wolf-finalize-1.0.sh \
    wolf-fix-mouse-no-accel-1.0.2.sh \
    wolf-remove-window-mover-1.0.6.sh \
    wolf-fix-cinnamon-polish-1.0.15.sh
do
    cp -f "$SELF_DIR/$helper" "$PROJECT/tests/$helper"
    chmod 755 "$PROJECT/tests/$helper"
done

# Remove scripts experimentais antigos do projeto se existirem.
rm -f "$PROJECT/tests"/wolf-fix-monitor-toggle-*.sh
rm -f "$PROJECT/tests/wolf-fix-audio-titlebar-v0.43.sh"
rm -f "$PROJECT/tests/wolf-fix-csd-dark-v0.45.sh"
rm -f "$PROJECT/tests/wolf-fix-csd-gnome-disks-v0.46.sh"

"$PROJECT/tests/wolf-customize-iso-profile.sh"
"$PROJECT/tests/wolf-smoke-test.sh"

echo
echo "[OK] Projeto Wolf Linux 1.0.15 atualizado."
echo "O mover experimental de janelas foi removido desta versão."
echo
echo "Próximos comandos:"
echo "  cd \"$PROJECT\""
echo "  ./tests/wolf-build-iso.sh"
echo "  ./tests/wolf-run-arch-test.sh uefi"
echo "  ./tests/wolf-run-arch-test.sh bios"
