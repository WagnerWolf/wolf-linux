#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_BUILD_PROJECT:-$HOME/wolf-linux-2.1.3-rc2}"
[[ $(< "$SELF_DIR/VERSION") == 2.1.3-rc2 ]] || {
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
"$SELF_DIR/preparar_ambiente_wolf_linux.sh" --project "$PROJECT"
cd "$PROJECT"
./tests/wolf-test-kernel-2.1.3.py
./tests/wolf-build-iso.sh
printf '
[OK] ISOs produzidas em %s/out:
' "$PROJECT"
find "$PROJECT/out" -maxdepth 1 -type f -name '*.iso' -printf '%p (%s bytes)
'
