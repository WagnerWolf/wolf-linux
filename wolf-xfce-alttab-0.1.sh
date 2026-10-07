#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.1"
ALTTAB_ARGS=(-w 1 -d 0 -sc 0 -vp pointer)

log(){ printf '[Wolf XFCE AltTab] %s\n' "$*"; }

set_xfconf() {
    local channel="$1" prop="$2" type="$3" value="$4"
    if xfconf-query -c "$channel" -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$prop" -s "$value" >/dev/null
    else
        xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" >/dev/null
    fi
}

configure_shortcuts() {
    command -v xfconf-query >/dev/null 2>&1 || {
        log "xfconf-query não encontrado; atalhos não foram alterados."
        return 1
    }

    # O xfwm4 pode restaurar o atalho padrão se a ação cycle_windows_key
    # simplesmente desaparecer. Mantemos as ações em combinações privadas
    # praticamente inalcançáveis e deixamos Alt+Tab/Alt+Shift+Tab vazios.
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/override' bool true
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Primary><Alt><Shift>F23' string cycle_windows_key
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Primary><Alt><Shift>F24' string cycle_reverse_windows_key
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Alt>Tab' string ''
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Alt><Shift>Tab' string ''
}

start_switcher() {
    if ! command -v alttab >/dev/null 2>&1; then
        log "alttab não está instalado; mantendo o Alt+Tab nativo intacto."
        return 1
    fi

    configure_shortcuts

    if pgrep -u "$UID" -x alttab >/dev/null 2>&1; then
        return 0
    fi

    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux"
    mkdir -p "$state_dir"
    nohup alttab "${ALTTAB_ARGS[@]}" >"$state_dir/xfce-alttab.log" 2>&1 &
}

stop_switcher() {
    pkill -u "$UID" -x alttab >/dev/null 2>&1 || true
}

restart_switcher() {
    stop_switcher
    start_switcher
}

status_switcher() {
    printf 'Wolf XFCE AltTab v%s\n' "$VERSION"
    printf 'Modo: workspace atual + monitor sob o ponteiro\n'
    printf 'Argumentos: alttab %s\n' "${ALTTAB_ARGS[*]}"
    if command -v alttab >/dev/null 2>&1; then
        printf 'Binário: %s\n' "$(command -v alttab)"
    else
        printf 'Binário: ausente\n'
    fi
    if pgrep -u "$UID" -x alttab >/dev/null 2>&1; then
        printf 'Processo: ativo\n'
    else
        printf 'Processo: parado\n'
    fi
}

case "${1:-start}" in
    configure) configure_shortcuts ;;
    start) start_switcher ;;
    restart) restart_switcher ;;
    stop) stop_switcher ;;
    status) status_switcher ;;
    *)
        echo "Uso: $0 {configure|start|restart|stop|status}" >&2
        exit 2
        ;;
esac
