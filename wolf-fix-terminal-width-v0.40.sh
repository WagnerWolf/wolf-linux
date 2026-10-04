#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo "      WOLF LINUX - TERMINAL WIDTH FIX v0.40"
echo "============================================================"

command -v gsettings >/dev/null 2>&1 || {
    echo "[ERRO] gsettings não encontrado."
    exit 1
}

if ! gsettings list-schemas | grep -Fxq 'org.mate.terminal.global'; then
    echo "[ERRO] Schema org.mate.terminal.global não encontrado."
    echo
    echo "Schemas MATE Terminal disponíveis:"
    gsettings list-schemas | grep '^org\.mate\.terminal' || true
    exit 1
fi

if ! gsettings list-schemas | grep -Fxq 'org.mate.terminal.profile'; then
    echo "[ERRO] Schema org.mate.terminal.profile não encontrado."
    exit 1
fi

PROFILE="$(
    gsettings get org.mate.terminal.global default-profile 2>/dev/null \
        | tr -d "'"
)"

[[ -n "$PROFILE" ]] || PROFILE="default"

SCHEMA="org.mate.terminal.profile:/org/mate/terminal/profiles/$PROFILE/"

echo "Perfil padrão detectado: $PROFILE"

gsettings set "$SCHEMA" use-custom-default-size true
gsettings set "$SCHEMA" default-size-columns 120

echo
echo "[OK] MATE Terminal configurado para 120 colunas."
echo
echo "Confirmação:"
echo "  use-custom-default-size = $(gsettings get "$SCHEMA" use-custom-default-size)"
echo "  default-size-columns    = $(gsettings get "$SCHEMA" default-size-columns)"
echo
echo "Feche esta janela e abra um NOVO MATE Terminal."
