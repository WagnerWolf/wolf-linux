#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/usr/local/lib/wolf-linux/helpers"
STABLE="$ROOT/stable"
EXPERIMENTAL="$ROOT/experimental"
VALIDATOR="/usr/local/bin/wolf-validate-helpers"

list_helpers() {
    echo "Wolf Linux helpers"
    echo
    echo "Stable:"
    if compgen -G "$STABLE/*" >/dev/null; then
        local f
        for f in "$STABLE"/*; do
            [[ -x "$f" ]] || continue
            printf '  %-34s %s\n' "$(basename "$f")" "$f"
        done
    else
        echo "  (nenhum)"
    fi
    echo
    echo "Experimental (não executados automaticamente):"
    if compgen -G "$EXPERIMENTAL/*" >/dev/null; then
        local f
        for f in "$EXPERIMENTAL"/*; do
            [[ -x "$f" ]] || continue
            printf '  %-34s %s\n' "$(basename "$f")" "$f"
        done
    else
        echo "  (nenhum)"
    fi
    echo
    if [[ -x "$VALIDATOR" ]]; then
        echo "Validação guiada:"
        echo "  wolf-helper validate"
    fi
}

run_helper() {
    local name="$1"
    shift || true
    local candidate
    for candidate in "$STABLE/$name" "$EXPERIMENTAL/$name"; do
        if [[ -x "$candidate" ]]; then
            exec "$candidate" "$@"
        fi
    done
    echo "[ERRO] Helper não encontrado: $name" >&2
    exit 1
}

case "${1:-list}" in
    list) list_helpers ;;
    run)
        [[ $# -ge 2 ]] || { echo "Uso: wolf-helper run <helper> [args...]" >&2; exit 2; }
        name="$2"
        shift 2
        run_helper "$name" "$@"
        ;;
    validate)
        [[ -x "$VALIDATOR" ]] || { echo "[ERRO] wolf-validate-helpers não instalado." >&2; exit 1; }
        shift || true
        exec "$VALIDATOR" "$@"
        ;;
    *)
        echo "Uso: wolf-helper {list|run <helper> [args...]|validate [--vm|--hardware]}" >&2
        exit 2
        ;;
esac
