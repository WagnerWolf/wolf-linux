#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
PORT="${1:-8000}"

cd "$PROJECT"

echo "======================================================"
echo "          WOLF LINUX - SERVIDOR DE TESTE"
echo "======================================================"
echo "Projeto: $PROJECT"
echo "Porta  : $PORT"
echo
echo "Na VM QEMU (user networking), o host normalmente é:"
echo
echo "  http://10.0.2.2:$PORT/"
echo
echo "Para habilitar SSH na ISO live:"
echo
echo "  curl -fsSL http://10.0.2.2:$PORT/tests/wolf-enable-ssh-live.sh -o /tmp/wolf-enable-ssh-live.sh"
echo "  bash /tmp/wolf-enable-ssh-live.sh"
echo
echo "Depois, pelo SSH ou console:"
echo
echo "  curl http://10.0.2.2:$PORT/install/wolf-install.sh -o wolf-install.sh"
echo "  curl http://10.0.2.2:$PORT/package-profiles/packages.conf -o packages.conf"
echo
echo "======================================================"

exec python -m http.server "$PORT" --bind 0.0.0.0
