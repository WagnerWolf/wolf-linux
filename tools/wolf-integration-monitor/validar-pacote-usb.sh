#!/usr/bin/env bash
set -Eeuo pipefail
PKG="${1:-}"
[[ -n "$PKG" && -f "$PKG" && ! -L "$PKG" ]] || { echo '[ERRO] libfm-qt Wolf ausente ou caminho inválido.' >&2; exit 2; }
[[ "$(basename "$PKG")" == 'libfm-qt-2.4.0-4.2-x86_64.pkg.tar.zst' ]] || { echo '[ERRO] Nome de pacote inesperado.' >&2; exit 2; }
command -v zstd >/dev/null && command -v tar >/dev/null || { echo '[ERRO] Requer zstd e tar.' >&2; exit 2; }
INFO="$(zstd -dc -- "$PKG" | tar -xOf - .PKGINFO)" || { echo '[ERRO] Pacote danificado.' >&2; exit 2; }
grep -Fxq 'pkgname = libfm-qt' <<< "$INFO" || { echo '[ERRO] pkgname inesperado.' >&2; exit 2; }
grep -Fxq 'pkgver = 2.4.0-4.2' <<< "$INFO" || { echo '[ERRO] pkgver inesperado.' >&2; exit 2; }
grep -Fxq 'arch = x86_64' <<< "$INFO" || { echo '[ERRO] arquitetura inesperada.' >&2; exit 2; }
# Uma validação de metadados não prova o conteúdo exato do patch.
# A biblioteca deve carregar ABI 17 (a mesma da base LXQt 2.4.x).
[[ "$(zstd -dc -- "$PKG" | tar -tf - | grep -E '^usr/lib/libfm-qt6\.so\.17(\.0\.0)?$' | wc -l)" -ge 1 ]] || {
    echo '[ERRO] ABI libfm-qt6.so.17 ausente; pacote incompatível.' >&2; exit 2;
}
echo '[OK] Pacote libfm-qt 2.4.0-4.2/x86_64 e ABI 17 identificados.'
echo '[NOTA] Conteúdo e origem dos patches são validados pelo construtor + testes gráficos, não por metadados.'
sha256sum -- "$PKG"
