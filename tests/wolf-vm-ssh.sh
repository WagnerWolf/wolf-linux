#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SSH_PORT="${WOLF_SSH_PORT:-2222}"
SSH_USER="${1:-${WOLF_SSH_USER:-root}}"

echo "Conectando à VM:"
echo "  ${SSH_USER}@127.0.0.1:${SSH_PORT}"
echo

exec ssh \
    -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$SSH_USER@127.0.0.1"
