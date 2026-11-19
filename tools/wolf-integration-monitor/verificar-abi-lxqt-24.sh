#!/usr/bin/env bash
# Preflight read-only: use sync DB from official Arch extra, not chaotic/testing.
set -Eeuo pipefail
command -v pacman >/dev/null || { echo '[BLOQUEADO] Pacman ausente.' >&2; exit 2; }
version_of() {
    local pkg="$1" info version
    info="$(LC_ALL=C pacman -Si "extra/$pkg")" || {
        echo "[BLOQUEADO] Não foi possível consultar o pacote extra/$pkg." >&2
        return 2
    }
    version="$(awk -F: '$1 ~ /^Version[[:space:]]*$/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' <<< "$info")"
    [[ -n "$version" ]] || { echo "[BLOQUEADO] Versão não encontrada: $pkg" >&2; return 2; }
    printf '%s' "$version"
}
lib="$(version_of libfm-qt)"
pcman="$(version_of pcmanfm-qt)"
case "$lib" in
    2.4.0-4) ;;
    *) echo "[BLOQUEADO] Arch extra/libfm-qt=$lib não é a base 2.4.0-4 (ABI 17)." >&2
       echo 'LXQt 2.5 tem ABI diferente; portar os patches Wolf antes de criar/reinstalar.' >&2
       exit 2 ;;
esac
case "$pcman" in
    2.4.0-*|2.4.1-*) ;;
    *) echo "[BLOQUEADO] Arch extra/pcmanfm-qt=$pcman não é série 2.4.x (ABI 17)." >&2
       exit 2 ;;
esac
echo "[OK] Repositório extra: libfm-qt=$lib / pcmanfm-qt=$pcman (ABI 17, compatível com Wolf 4.2)."
