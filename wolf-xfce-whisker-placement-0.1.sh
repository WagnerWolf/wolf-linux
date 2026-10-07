#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -u

VERSION="0.1"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}/wolf-linux"
PID_FILE="$RUNTIME_BASE/xfce-whisker-placement.pid"
POLL_SECONDS="0.10"
LAUNCH_WINDOW_MS=5000

log(){ printf '[Wolf XFCE Whisker Placement] %s\n' "$*"; }

now_ms() {
    date +%s%3N
}

monitor_for_point() {
    local px="$1" py="$2" line out w h x y
    while IFS= read -r line; do
        [[ "$line" == *" connected "* ]] || continue
        out="${line%% *}"
        if [[ "$line" =~ ([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) ]]; then
            w="${BASH_REMATCH[1]}"; h="${BASH_REMATCH[2]}"
            x="${BASH_REMATCH[3]}"; y="${BASH_REMATCH[4]}"
            if (( px >= x && px < x+w && py >= y && py < y+h )); then
                printf '%s\t%s\t%s\t%s\t%s\n' "$out" "$x" "$y" "$w" "$h"
                return 0
            fi
        fi
    done < <(xrandr --query 2>/dev/null || true)
    return 1
}

is_whisker_window() {
    local wid="$1" pid cmd name
    [[ "$wid" =~ ^[0-9]+$ ]] || return 1

    pid="$(xdotool getwindowpid "$wid" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]]; then
        cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
        if [[ "$cmd" == *wrapper-2.0* && "$cmd" == *whiskermenu* ]]; then
            return 0
        fi
    fi

    # Fallback para versões/empacotamentos em que o wrapper não aparece
    # claramente no cmdline. Esses são os títulos conhecidos no nosso perfil.
    name="$(xdotool getwindowname "$wid" 2>/dev/null || true)"
    case "$name" in
        'Whisker Menu'|'Menu Whisker') return 0 ;;
    esac
    return 1
}

active_whisker_window() {
    local wid

    # Caminho rápido: o campo de busca do Whisker normalmente recebe foco.
    wid="$(xdotool getactivewindow 2>/dev/null || true)"
    if is_whisker_window "$wid"; then
        printf '%s\n' "$wid"
        return 0
    fi

    # Fallback importante para clique no painel: procura um wrapper visível do
    # plugin, sem depender de a janela popup ter virado _NET_ACTIVE_WINDOW.
    while IFS= read -r wid; do
        is_whisker_window "$wid" || continue
        printf '%s\n' "$wid"
        return 0
    done < <(xdotool search --onlyvisible --class 'wrapper-2.0' 2>/dev/null || true)

    return 1
}

monitor_for_window() {
    local wid="$1" geometry cx cy
    geometry="$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1

    local X=0 Y=0 WIDTH=0 HEIGHT=0
    while IFS='=' read -r key value; do
        case "$key" in
            X) X="$value" ;;
            Y) Y="$value" ;;
            WIDTH) WIDTH="$value" ;;
            HEIGHT) HEIGHT="$value" ;;
        esac
    done <<< "$geometry"

    [[ "$X" =~ ^-?[0-9]+$ && "$Y" =~ ^-?[0-9]+$ && "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]] || return 1
    cx=$((X + WIDTH / 2)); cy=$((Y + HEIGHT / 2))
    monitor_for_point "$cx" "$cy"
}

client_ids() {
    wmctrl -l 2>/dev/null | awk '{print $1}'
}

window_class() {
    local wid="$1"
    wmctrl -lx 2>/dev/null | awk -v id="$wid" 'tolower($1)==tolower(id) {print $3; exit}'
}

candidate_window() {
    local wid="$1" klass title
    klass="$(window_class "$wid")"
    case "${klass,,}" in
        *xfce4-panel*|*wrapper-2.0*|*xfdesktop*|*xfce4-notifyd*|*alttab*) return 1 ;;
    esac

    title="$(xdotool getwindowname "$((wid))" 2>/dev/null || true)"
    [[ -n "$title" ]] || return 1
    return 0
}

move_window_to_target() {
    local wid_hex="$1" target_x="$2" target_y="$3" target_w="$4" target_h="$5"
    local wid_dec geometry wx wy ww wh cx cy current
    local src_x src_y local_x local_y max_x max_y new_x new_y state
    local was_max_h=0 was_max_v=0 was_fullscreen=0

    wid_dec=$((wid_hex))
    geometry="$(xdotool getwindowgeometry --shell "$wid_dec" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1

    wx=0; wy=0; ww=0; wh=0
    while IFS='=' read -r key value; do
        case "$key" in
            X) wx="$value" ;;
            Y) wy="$value" ;;
            WIDTH) ww="$value" ;;
            HEIGHT) wh="$value" ;;
        esac
    done <<< "$geometry"
    [[ "$wx" =~ ^-?[0-9]+$ && "$wy" =~ ^-?[0-9]+$ && "$ww" =~ ^[0-9]+$ && "$wh" =~ ^[0-9]+$ ]] || return 1

    cx=$((wx + ww / 2)); cy=$((wy + wh / 2))
    if (( cx >= target_x && cx < target_x+target_w && cy >= target_y && cy < target_y+target_h )); then
        return 0
    fi

    src_x=0; src_y=0
    current="$(monitor_for_point "$cx" "$cy" 2>/dev/null || true)"
    if [[ -n "$current" ]]; then
        IFS=$'\t' read -r _ src_x src_y _ _ <<< "$current"
    fi

    local_x=$((wx - src_x)); local_y=$((wy - src_y))
    (( local_x < 0 )) && local_x=0
    (( local_y < 0 )) && local_y=0
    max_x=$((target_w - ww)); max_y=$((target_h - wh))
    (( max_x < 0 )) && max_x=0
    (( max_y < 0 )) && max_y=0
    (( local_x > max_x )) && local_x="$max_x"
    (( local_y > max_y )) && local_y="$max_y"
    new_x=$((target_x + local_x)); new_y=$((target_y + local_y))

    state="$(xprop -id "$wid_hex" _NET_WM_STATE 2>/dev/null || true)"
    [[ "$state" == *_NET_WM_STATE_MAXIMIZED_HORZ* ]] && was_max_h=1
    [[ "$state" == *_NET_WM_STATE_MAXIMIZED_VERT* ]] && was_max_v=1
    [[ "$state" == *_NET_WM_STATE_FULLSCREEN* ]] && was_fullscreen=1

    if (( was_max_h || was_max_v || was_fullscreen )); then
        wmctrl -ir "$wid_hex" -b remove,fullscreen,maximized_vert,maximized_horz >/dev/null 2>&1 || true
        sleep 0.05
    fi

    xdotool windowmove --sync "$wid_dec" "$new_x" "$new_y" >/dev/null 2>&1 || return 1

    if (( was_max_h )); then wmctrl -ir "$wid_hex" -b add,maximized_horz >/dev/null 2>&1 || true; fi
    if (( was_max_v )); then wmctrl -ir "$wid_hex" -b add,maximized_vert >/dev/null 2>&1 || true; fi
    if (( was_fullscreen )); then wmctrl -ir "$wid_hex" -b add,fullscreen >/dev/null 2>&1 || true; fi
    return 0
}

daemon_loop() {
    command -v xdotool >/dev/null 2>&1 || exit 0
    command -v xrandr >/dev/null 2>&1 || exit 0
    command -v wmctrl >/dev/null 2>&1 || exit 0
    command -v xprop >/dev/null 2>&1 || exit 0

    mkdir -p "$RUNTIME_BASE"
    if [[ -r "$PID_FILE" ]]; then
        local old_pid
        old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            exit 0
        fi
    fi
    printf '%s\n' "$$" > "$PID_FILE"
    trap 'rm -f "$PID_FILE"' EXIT
    trap 'rm -f "$PID_FILE"; exit 0' INT TERM

    local menu_open=0 menu_wid="" target="" target_out="" target_x=0 target_y=0 target_w=0 target_h=0
    local pending_until=0 now id
    declare -A baseline=()

    while true; do
        menu_wid="$(active_whisker_window 2>/dev/null || true)"
        if [[ -n "$menu_wid" ]]; then
            target="$(monitor_for_window "$menu_wid" 2>/dev/null || true)"
            if [[ -n "$target" ]]; then
                IFS=$'\t' read -r target_out target_x target_y target_w target_h <<< "$target"
            fi

            if (( menu_open == 0 )); then
                baseline=()
                while IFS= read -r id; do
                    [[ "$id" =~ ^0x[0-9a-fA-F]+$ ]] && baseline["${id,,}"]=1
                done < <(client_ids)
                menu_open=1
                pending_until=0
            fi
        elif (( menu_open )); then
            menu_open=0
            now="$(now_ms)"
            pending_until=$((now + LAUNCH_WINDOW_MS))
        fi

        if (( pending_until > 0 )); then
            now="$(now_ms)"
            if (( now >= pending_until )); then
                pending_until=0
            elif [[ -n "$target_out" ]]; then
                while IFS= read -r id; do
                    [[ "$id" =~ ^0x[0-9a-fA-F]+$ ]] || continue
                    id="${id,,}"
                    [[ -n "${baseline[$id]:-}" ]] && continue
                    candidate_window "$id" || continue
                    move_window_to_target "$id" "$target_x" "$target_y" "$target_w" "$target_h" || true
                done < <(client_ids)
            fi
        fi

        sleep "$POLL_SECONDS"
    done
}

start_daemon() {
    mkdir -p "$RUNTIME_BASE"
    if [[ -r "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    nohup "$0" daemon >/dev/null 2>&1 &
}

stop_daemon() {
    local pid=""
    if [[ -r "$PID_FILE" ]]; then pid="$(cat "$PID_FILE" 2>/dev/null || true)"; fi
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
}

status_daemon() {
    printf 'Wolf XFCE Whisker Placement v%s\n' "$VERSION"
    printf 'Regra: primeira(s) janela(s) nova(s) após o Whisker seguem o monitor do menu\n'
    if [[ -r "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            printf 'Processo: ativo (PID %s)\n' "$pid"
            return 0
        fi
    fi
    printf 'Processo: parado\n'
    return 1
}

case "${1:-start}" in
    daemon) daemon_loop ;;
    start) start_daemon ;;
    stop) stop_daemon ;;
    restart) stop_daemon; start_daemon ;;
    status) status_daemon ;;
    *) echo "Uso: $0 {start|stop|restart|status|daemon}" >&2; exit 2 ;;
esac
