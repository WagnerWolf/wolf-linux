#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in *XFCE*|*Xfce*) ;; *) exit 0 ;; esac

command -v xfconf-query >/dev/null 2>&1 || exit 0
command -v xcape >/dev/null 2>&1 || exit 0

# Sem atraso fixo de vários segundos: espere somente o xfconf ficar pronto.
for _ in {1..20}; do
    if xfconf-query -c xfce4-keyboard-shortcuts -l >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

setcmd() {
    local key="$1" cmd="$2"
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "/commands/custom/$key" -n -t string -s "$cmd" 2>/dev/null \
        || xfconf-query -c xfce4-keyboard-shortcuts \
            -p "/commands/custom/$key" -s "$cmd" 2>/dev/null || true
}

while IFS= read -r prop; do
    [[ "$prop" == /commands/custom/* ]] || continue
    value="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)"
    if [[ "$prop" == '/commands/custom/<Primary><Alt><Shift>F12' ]]; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
        continue
    fi
    if [[ "$prop" == *Super* && "$value" == *xfce4-popup-whiskermenu* ]]; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
    fi
done < <(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null || true)

# Autoridade única dos atalhos Wolf no XFCE.
setcmd '<Primary><Alt>t' '/usr/local/bin/wolf-xfce-launch-here terminal'
setcmd '<Super>e' '/usr/local/bin/wolf-xfce-launch-here home'
setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'

pkill -x xcape >/dev/null 2>&1 || true
exec xcape -e 'Super_L=Control_L|Alt_L|Shift_L|F12'
