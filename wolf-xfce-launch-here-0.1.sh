#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

profile="${1:-}"
[[ -n "$profile" ]] || { echo "Uso: $0 {browser|home|terminal|command} [args...]" >&2; exit 2; }
shift || true

arm() {
    local expected="$1"
    if [[ -x /usr/local/bin/wolf-xfce-whisker-placement ]]; then
        /usr/local/bin/wolf-xfce-whisker-placement arm "$expected" >/dev/null 2>&1 || true
    fi
}

case "$profile" in
    browser)
        arm 'google-chrome|Google-chrome|chrome'
        exec /usr/bin/google-chrome-stable "$@"
        ;;
    home)
        arm 'Thunar|thunar'
        exec /usr/bin/thunar "$@"
        ;;
    terminal)
        arm 'xfce4-terminal|Xfce4-terminal'
        exec /usr/bin/xfce4-terminal "$@"
        ;;
    command)
        expected="${1:-}"
        [[ -n "$expected" ]] || { echo "Uso: $0 command <regex-classe> <comando> [args...]" >&2; exit 2; }
        shift
        (($# > 0)) || { echo "Comando ausente." >&2; exit 2; }
        arm "$expected"
        exec "$@"
        ;;
    *)
        echo "Perfil desconhecido: $profile" >&2
        exit 2
        ;;
esac
