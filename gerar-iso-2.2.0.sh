#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_BUILD_PROJECT:-$HOME/wolf-linux-2.2.0}"
[[ $(< "$SELF_DIR/VERSION") == 2.2.0 ]] || {
    echo '[ERRO] DevKit/versão inesperados.' >&2; exit 1;
}
command -v pacman >/dev/null 2>&1 || {
    echo '[ERRO] Esta geração de ISO requer Arch Linux com pacman e Archiso.' >&2
    exit 1
}
[[ ! -e "$PROJECT" ]] || {
    echo "[ERRO] Diretório já existe: $PROJECT" >&2
    echo 'Para preservar instalações anteriores, não o apagarei automaticamente.' >&2
    exit 1
}
USB_PKG="$SELF_DIR/release-packages/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst"
if [[ ! -f "$USB_PKG" ]]; then
    echo '[ERRO] Release com menu USB requer pacote libfm-qt Wolf já compilado.' >&2
    echo "Copie o pacote .pkg.tar.zst para: $USB_PKG" >&2
    exit 1
fi
bash "$SELF_DIR/tools/wolf-integration-monitor/validar-pacote-usb.sh" "$USB_PKG"
"$SELF_DIR/preparar_ambiente_wolf_linux.sh" --project "$PROJECT"
cd "$PROJECT"
./tests/wolf-test-lxqt-2.2.0.py
./tests/wolf-build-iso.sh
printf '
[OK] ISOs produzidas em %s/out:
' "$PROJECT"
find "$PROJECT/out" -maxdepth 1 -type f -name '*.iso' -printf '%p (%s bytes)
'
