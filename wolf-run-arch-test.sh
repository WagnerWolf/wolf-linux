#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
MODE="${1:-uefi}"
ISO="${2:-}"

if [[ -z "$ISO" ]]; then
    cat <<'EOF'
Uso:
  wolf-run-arch-test.sh [uefi|bios] /caminho/archlinux.iso

Exemplo:
  ~/wolf-linux/tests/wolf-run-arch-test.sh uefi ~/Downloads/archlinux-x86_64.iso
EOF
    exit 2
fi

[[ -f "$ISO" ]] || {
    echo "[ERRO] ISO não encontrada: $ISO"
    exit 1
}

exec "$PROJECT/tests/wolf-test-iso.sh" "$MODE" "$ISO" --fresh
