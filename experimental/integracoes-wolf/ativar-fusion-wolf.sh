#!/usr/bin/env bash
# Atualiza apenas o aplicador de tema Wolf + estilo Qt do usuário. Sem touch em GTK.
set -Eeuo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$DIR/../.." && pwd)"
[[ $(id -u) -ne 0 ]] || { echo 'Execute sem sudo (o script solicitará senha quando necessário).' >&2; exit 2; }
case "${1:---check}" in
  --check)
    python3 "$DIR/wolf-fusion-session.py" --check
    if [[ -f /usr/local/bin/wolf-appearance-dark ]]; then echo '[OK] Wolf appearance instalado'; else echo '[AVISO] Wolf appearance não instalado'; fi
    ;;
  --apply)
    src="$ROOT/tools/lxqt/wolf-appearance-dark"
    [[ -r "$src" ]] || { echo "Arquivo ausente: $src" >&2; exit 1; }
    dest=/usr/local/bin/wolf-appearance-dark
    backup="$HOME/wolf-backups/qt-fusion/aplicador-$(date +%Y%m%d-%H%M%S-%N)"
    mkdir -p "$backup"
    [[ -f "$dest" ]] && sudo cat "$dest" > "$backup/wolf-appearance-dark.old"
    sudo install -m 755 "$src" "$dest"
    python3 "$DIR/wolf-fusion-session.py" --apply
    echo "[OK] Aplicador de tema atualizado; backup do binário: $backup"
    echo '[INFO] Encerre a sessão LXQt e entre novamente. GTK e demais temas permanecem.'
    ;;
  *) echo 'Uso: bash ativar-fusion-wolf.sh [--check|--apply]' >&2; exit 2;;
esac
