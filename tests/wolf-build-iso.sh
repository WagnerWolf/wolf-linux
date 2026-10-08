#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
PROFILE="${WOLF_ISO_PROFILE:-$PROJECT/iso-profile}"
WORK="${WOLF_WORK_DIR:-$PROJECT/work}"
OUT="${WOLF_OUT_DIR:-$PROJECT/out}"

[[ -d "$PROFILE" ]] || {
    echo "Perfil Archiso não encontrado: $PROFILE" >&2
    exit 1
}
[[ -x "$PROJECT/tests/wolf-customize-iso-profile.sh" ]] || {
    echo "[ERRO] Customizador ausente: $PROJECT/tests/wolf-customize-iso-profile.sh" >&2
    exit 1
}
[[ -x "$PROJECT/tests/wolf-stage-live-ssh.sh" ]] || {
    echo "[ERRO] Stager SSH ausente: $PROJECT/tests/wolf-stage-live-ssh.sh" >&2
    exit 1
}

mkdir -p "$WORK" "$OUT"

# Customização geral e, DEPOIS, staging explícito do SSH. O build não confia
# em efeitos colaterais de uma etapa anterior.
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROFILE" \
    "$PROJECT/tests/wolf-customize-iso-profile.sh"
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROFILE" \
    "$PROJECT/tests/wolf-stage-live-ssh.sh"

SSH_PROFILE="$PROFILE/airootfs/usr/local/bin/wolf-enable-ssh-live"
SSH_ALIAS_PROFILE="$PROFILE/airootfs/usr/local/bin/wolf-ssh"
[[ -x "$SSH_PROFILE" ]] || {
    echo "[ERRO] Preflight ISO: wolf-enable-ssh-live não está no airootfs." >&2
    exit 1
}
[[ -L "$SSH_ALIAS_PROFILE" ]] || {
    echo "[ERRO] Preflight ISO: alias wolf-ssh não está no airootfs." >&2
    exit 1
}
grep -Fxq openssh "$PROFILE/packages.x86_64" || {
    echo "[ERRO] Preflight ISO: openssh não está em packages.x86_64." >&2
    exit 1
}

echo "======================================================"
echo "             WOLF LINUX - BUILD DA ISO"
echo "======================================================"
echo "Projeto : $PROJECT"
echo "Perfil  : $PROFILE"
echo "Work    : $WORK"
echo "Saída   : $OUT"
echo "SSH live: $SSH_PROFILE"
echo

sudo rm -rf "$WORK"/*

sudo mkarchiso \
    -v \
    -w "$WORK" \
    -o "$OUT" \
    "$PROFILE"

# Verificação do filesystem REAL que mkarchiso montou antes de comprimir.
SSH_WORK="$WORK/x86_64/airootfs/usr/local/bin/wolf-enable-ssh-live"
SSH_ALIAS_WORK="$WORK/x86_64/airootfs/usr/local/bin/wolf-ssh"
[[ -x "$SSH_WORK" ]] || {
    echo "[ERRO] Pós-build: wolf-enable-ssh-live não chegou ao airootfs construído." >&2
    exit 1
}
[[ -L "$SSH_ALIAS_WORK" ]] || {
    echo "[ERRO] Pós-build: wolf-ssh não chegou ao airootfs construído." >&2
    exit 1
}

SFS="$WORK/iso/arch/x86_64/airootfs.sfs"
[[ -f "$SFS" ]] || {
    echo "[ERRO] Pós-build: airootfs.sfs não encontrado: $SFS" >&2
    exit 1
}
command -v unsquashfs >/dev/null 2>&1 || {
    echo "[ERRO] Pós-build: unsquashfs não encontrado; não é possível validar a ISO." >&2
    exit 1
}
if ! unsquashfs -ll "$SFS" 2>/dev/null | grep -E '/usr/local/bin/wolf-enable-ssh-live$' >/dev/null; then
    echo "[ERRO] Pós-build: wolf-enable-ssh-live NÃO está dentro do airootfs.sfs." >&2
    exit 1
fi
if ! unsquashfs -ll "$SFS" 2>/dev/null | grep -E '/usr/local/bin/wolf-ssh([[:space:]]|$)' >/dev/null; then
    echo "[ERRO] Pós-build: wolf-ssh NÃO está dentro do airootfs.sfs." >&2
    exit 1
fi

echo
printf '[OK] SSH live confirmado dentro do squashfs final.\n'
echo "ISOs encontradas:"
find "$OUT" -maxdepth 1 -type f -name '*.iso' -printf '  %p\n'
