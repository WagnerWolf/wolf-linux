#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
PROFILE="$PROJECT/iso-profile"
WORK="$PROJECT/work"
OUT="$PROJECT/out"

[[ -d "$PROFILE" ]] || {
    echo "Perfil Archiso não encontrado: $PROFILE"
    exit 1
}

mkdir -p "$WORK" "$OUT"

if [[ -x "$PROJECT/tests/wolf-customize-iso-profile.sh" ]]; then
    "$PROJECT/tests/wolf-customize-iso-profile.sh"
fi

echo "======================================================"
echo "             WOLF LINUX - BUILD DA ISO"
echo "======================================================"
echo "Perfil : $PROFILE"
echo "Work   : $WORK"
echo "Saída  : $OUT"
echo

sudo rm -rf "$WORK"/*

sudo mkarchiso \
    -v \
    -w "$WORK" \
    -o "$OUT" \
    "$PROFILE"

echo
echo "ISOs encontradas:"
find "$OUT" -maxdepth 1 -type f -name '*.iso' -printf '  %p\n'
