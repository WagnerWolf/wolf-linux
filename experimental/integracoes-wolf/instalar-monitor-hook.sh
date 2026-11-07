#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:---help}" in
 --help)
  echo 'Uso: bash instalar-monitor-hook.sh --check | --install | --remove'
  echo 'Instala apenas o hook de AVISO sobre libfm-qt; nao compila e nao troca pacotes.'
  ;;
 --check)
  for f in /etc/pacman.d/hooks/90-wolf-libfm-integration.hook /usr/local/lib/wolf-linux/integrations/wolf_integration_hook.py; do
    if [[ -f "$f" ]]; then echo "[INSTALADO] $f"; else echo "[AUSENTE] $f"; fi
  done
  ;;
 --install)
  if (( EUID == 0 )); then echo 'Execute como usuario normal, com sudo quando solicitado.' >&2; exit 1; fi
  sudo install -d -m 0755 /etc/pacman.d/hooks /usr/local/lib/wolf-linux/integrations
  sudo install -m 0644 "$here/90-wolf-libfm-integration.hook" /etc/pacman.d/hooks/
  sudo install -m 0644 "$here/wolf_integration_hook.py" /usr/local/lib/wolf-linux/integrations/
  echo '[OK] Hook instalado. Apenas registrara revisoes apos atualizar libfm-qt.'
  ;;
 --remove)
  if (( EUID == 0 )); then echo 'Execute como usuario normal.' >&2; exit 1; fi
  sudo rm -f /etc/pacman.d/hooks/90-wolf-libfm-integration.hook /usr/local/lib/wolf-linux/integrations/wolf_integration_hook.py
  echo '[OK] Hook retirado. Registro historico nao foi apagado.'
  ;;
 *) echo 'Opcao desconhecida' >&2; exit 2;;
esac
