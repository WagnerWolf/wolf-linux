#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
CMD="${1:-status}"
MODE="${2:-uefi}"

case "$CMD" in
    fresh)
        exec "$PROJECT/tests/wolf-test-iso.sh" "$MODE" --fresh
        ;;
    live)
        exec "$PROJECT/tests/wolf-test-iso.sh" "$MODE"
        ;;
    installed|start)
        exec "$PROJECT/tests/wolf-test-iso.sh" "$MODE" --installed
        ;;
    ssh)
        exec "$PROJECT/tests/wolf-vm-ssh.sh"
        ;;
    status)
        echo "Wolf VM"
        echo "Projeto: $PROJECT"
        for candidate in "$PROJECT"/vm/wolf-test-*.qcow2; do
            [[ -f "$candidate" ]] || continue
            printf '  disco: %s  (%s)\n' "$candidate" "$(du -h "$candidate" | awk '{print $1}')"
        done
        echo
        echo "Comandos:"
        echo "  ./tests/wolf-vm.sh fresh uefi      # APAGA/recria VM e boota ISO"
        echo "  ./tests/wolf-vm.sh live uefi       # preserva disco e boota com ISO conectada"
        echo "  ./tests/wolf-vm.sh installed uefi  # boota SOMENTE o disco instalado"
        echo "  ./tests/wolf-vm.sh ssh             # conecta por SSH"
        ;;
    *)
        echo "Uso: $0 {status|fresh|live|installed|start|ssh} [uefi|bios]" >&2
        exit 2
        ;;
esac
