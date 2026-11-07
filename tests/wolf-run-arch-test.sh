#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
MODE="${1:-uefi}"
ISO="${2:-}"
CONFIRM_FRESH="${3:-}"

if [[ "$CONFIRM_FRESH" != "--fresh" ]]; then
    cat <<EOF2
[PROTEÇÃO] wolf-run-arch-test.sh recria a VM de instalação.
Nenhum disco foi alterado.

Para criar/recriar propositalmente:
  $0 $MODE ${ISO:-/caminho/wolf-linux.iso} --fresh

Para iniciar a instalação já existente:
  $PROJECT/tests/wolf-vm.sh installed $MODE

Para preservar o disco e iniciar com a ISO conectada:
  $PROJECT/tests/wolf-vm.sh live $MODE
EOF2
    exit 2
fi

if [[ -z "$ISO" ]]; then
    ISO="$(
        find "$PROJECT/out" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            head -n1 |
            cut -d' ' -f2-
    )"
fi

[[ -n "$ISO" && -f "$ISO" ]] || {
    echo "[ERRO] ISO não encontrada: ${ISO:-<vazia>}" >&2
    exit 1
}

exec "$PROJECT/tests/wolf-test-iso.sh" "$MODE" "$ISO" --fresh
