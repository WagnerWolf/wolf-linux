#!/usr/bin/env bash
set -Eeuo pipefail
PKG="${1:-}"
[[ -n "$PKG" && -f "$PKG" && ! -L "$PKG" ]] || { echo '[ERRO] libfm-qt Wolf ausente ou caminho inválido.' >&2; exit 2; }
[[ "$(basename "$PKG")" == 'libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst' ]] || { echo '[ERRO] Nome de pacote inesperado.' >&2; exit 2; }
command -v zstd >/dev/null && command -v tar >/dev/null || { echo '[ERRO] Requer zstd e tar.' >&2; exit 2; }
INFO="$(zstd -dc -- "$PKG" | tar -xOf - .PKGINFO)" || { echo '[ERRO] Pacote danificado.' >&2; exit 2; }
grep -Fxq 'pkgname = libfm-qt' <<< "$INFO" || { echo '[ERRO] pkgname inesperado.' >&2; exit 2; }
grep -Fxq 'pkgver = 2.4.0-4.1' <<< "$INFO" || { echo '[ERRO] pkgver inesperado.' >&2; exit 2; }
grep -Fxq 'arch = x86_64' <<< "$INFO" || { echo '[ERRO] arquitetura inesperada.' >&2; exit 2; }
# Uma validação de metadados não prova o conteúdo exato do patch.
echo '[OK] Pacote libfm-qt 2.4.0-4.1/x86_64 identificado; conteúdo C++ validado no hardware pelo usuário.'
sha256sum -- "$PKG"
