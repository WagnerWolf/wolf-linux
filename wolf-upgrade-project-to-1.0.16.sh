#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-$(pwd)}"
FIX="$ROOT/wolf-fix-cinnamon-polish-1.0.16.sh"

if [[ ! -f "$FIX" ]]; then
    echo "[ERRO] wolf-fix-cinnamon-polish-1.0.16.sh não encontrado em: $ROOT"
    exit 1
fi

echo "Projeto Wolf Linux atualizado para o conjunto de correções 1.0.16."
echo "Para corrigir uma instalação Cinnamon existente, execute:"
echo "  bash $FIX"
