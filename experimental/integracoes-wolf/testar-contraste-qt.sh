#!/usr/bin/env bash
# Teste exclusivamente visual: não altera o tema, nem inicia xsettingsd.
set -euo pipefail
[[ -n "${DISPLAY:-}" ]] || { echo '[ERRO] Abra em uma sessão gráfica X11.' >&2; exit 1; }
command -v lxqt-archiver >/dev/null || { echo '[ERRO] lxqt-archiver não encontrado.' >&2; exit 1; }
echo '[INFO] Iniciando LXQt Archiver com Fusion SOMENTE nesta janela.'
echo '[INFO] Compare a legibilidade de Arquivo / Editar / Exibir / Ajuda.'
echo '[INFO] Ao fechar, o sistema continua usando seu tema anterior.'
QT_STYLE_OVERRIDE=Fusion lxqt-archiver "$@"
