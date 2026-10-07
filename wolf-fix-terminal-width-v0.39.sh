#!/usr/bin/env bash
set -Eeuo pipefail

echo "============================================================"
echo "      WOLF LINUX - TERMINAL WIDTH FIX v0.39"
echo "============================================================"

command -v gsettings >/dev/null 2>&1 || {
    echo "[ERRO] gsettings não encontrado."
    exit 1
}

if ! gsettings list-schemas | grep -Fxq 'org.mate.terminal.profiles-list'; then
    echo "[ERRO] Schema do MATE Terminal não encontrado."
    exit 1
fi

uuid="$(
    gsettings get org.mate.terminal.profiles-list default 2>/dev/null \
        | tr -d "'"
)"

[[ -n "$uuid" ]] || {
    echo "[ERRO] Perfil padrão do MATE Terminal não foi localizado."
    exit 1
}

schema="org.mate.terminal.profile:/org/mate/terminal/profiles/$uuid/"

gsettings set "$schema" use-custom-default-size true
gsettings set "$schema" default-size-columns 120

echo
echo "[OK] MATE Terminal configurado para abrir com 120 colunas."
echo
echo "Perfil: $uuid"
echo "Largura: $(gsettings get "$schema" default-size-columns)"
echo
echo "Feche esta janela e abra um NOVO terminal para conferir."
