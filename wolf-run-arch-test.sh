#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
MODE="${1:-uefi}"
ISO="${2:-}"

if [[ -z "$ISO" ]]; then
    ISO="$(
        find "$PROJECT/out" -maxdepth 1 -type f -name '*.iso'             -printf '%T@ %p\n' 2>/dev/null             | sort -nr             | head -n1             | cut -d' ' -f2-
    )"

    if [[ -z "$ISO" ]]; then
        cat <<'EOF'
Nenhuma ISO foi encontrada em ~/wolf-linux/out.

Gere primeiro:
  ~/wolf-linux/tests/wolf-build-iso.sh

Ou informe manualmente:
  wolf-run-arch-test.sh [uefi|bios] /caminho/wolf-linux.iso
EOF
        exit 2
    fi

    echo "[INFO] ISO mais recente selecionada automaticamente:"
    echo "  $ISO"
fi

[[ -f "$ISO" ]] || {
    echo "[ERRO] ISO não encontrada: $ISO"
    exit 1
}

exec "$PROJECT/tests/wolf-test-iso.sh" "$MODE" "$ISO" --fresh
