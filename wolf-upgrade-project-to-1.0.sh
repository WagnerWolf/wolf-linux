#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-${WOLF_PROJECT:-$HOME/wolf-linux}}"

echo "============================================================"
echo "         WOLF LINUX - UPGRADE DO PROJETO PARA 1.0"
echo "============================================================"
echo
echo "Projeto:"
echo "  $PROJECT"
echo
echo "IMPORTANTE:"
echo "  assets/ NÃO será alterado."
echo "  Sua logo transparente do Plymouth será preservada."
echo

[[ -d "$PROJECT" ]] || {
    echo "[ERRO] Projeto não encontrado: $PROJECT"
    exit 1
}

mkdir -p \
    "$PROJECT/install" \
    "$PROJECT/package-profiles" \
    "$PROJECT/tests"

cp -f "$SELF_DIR/wolf-install.sh" \
    "$PROJECT/install/wolf-install.sh"
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
    wolf-finalize-1.0.sh
do
    cp -f "$SELF_DIR/$helper" "$PROJECT/tests/$helper"
    chmod 755 "$PROJECT/tests/$helper"
done

echo "[1/3] Código do projeto atualizado."

echo "[2/3] Recriando/customizando perfil Archiso..."
"$PROJECT/tests/wolf-customize-iso-profile.sh"

echo "[3/3] Smoke test..."
"$PROJECT/tests/wolf-smoke-test.sh"

echo
echo "============================================================"
echo "              PROJETO WOLF LINUX 1.0 PRONTO"
echo "============================================================"
echo
echo "A logo existente foi preservada:"
echo "  $PROJECT/assets/plymouth/logo.png"
echo
echo "Próximos comandos:"
echo "  cd \"$PROJECT\""
echo "  ./tests/wolf-build-iso.sh"
echo "  ./tests/wolf-run-arch-test.sh uefi"
echo
echo "Após validar UEFI, opcionalmente:"
echo "  ./tests/wolf-run-arch-test.sh bios"
