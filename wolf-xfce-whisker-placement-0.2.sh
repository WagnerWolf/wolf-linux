#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -u

VERSION="0.2"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}/wolf-linux"
PID_FILE="$RUNTIME_BASE/xfce-whisker-placement.pid"
CONTEXT_FILE="$RUNTIME_BASE/xfce-launch-context.tsv"
CONTEXT_TTL_MS=8000
WHISKER_TTL_MS=6000

log(){ printf '[Wolf XFCE Window Placement] %s\n' "$*"; }
now_ms(){ date +%s%3N; }

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

pointer_target() {
    local loc mx=0 my=0 key value
    loc="$(xdotool getmouselocation --shell 2>/dev/null || true)"
    while IFS='=' read -r key value; do
        case "$key" in
            X) mx="$value" ;;
            Y) my="$value" ;;
        esac
    done <<< "$loc"
    [[ "$mx" =~ ^-?[0-9]+$ && "$my" =~ ^-?[0-9]+$ ]] || return 1
    monitor_for_point "$mx" "$my"
}

monitor_for_window() {
    local wid="$1" geometry cx cy key value
    local wx=0 wy=0 ww=0 wh=0
    geometry="$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1
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
    monitor_for_point "$cx" "$cy"
}

window_class() {
    local wid="$1" class
    class="$(xprop -id "$wid" WM_CLASS 2>/dev/null || true)"
    class="${class#*= }"
    printf '%s\n' "$class"
}

is_whisker_window() {
    local wid="$1" class pid cmd name
    [[ "$wid" =~ ^0x[0-9a-fA-F]+$ ]] || return 1

    class="$(window_class "$wid")"
    if [[ "${class,,}" == *wrapper-2.0* ]]; then
        name="$(xprop -id "$wid" _NET_WM_NAME WM_NAME 2>/dev/null || true)"
        if [[ "${name,,}" == *whisker* || "${name,,}" == *'menu whisker'* ]]; then
            return 0
        fi
    fi

    pid="$(xdotool getwindowpid "$((wid))" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]]; then
        cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
        [[ "$cmd" == *wrapper-2.0* && "$cmd" == *whiskermenu* ]] && return 0
    fi
    return 1
}

candidate_window() {
    local wid="$1" class type
    class="$(window_class "$wid")"
    case "${class,,}" in
        *xfce4-panel*|*wrapper-2.0*|*xfdesktop*|*xfce4-notifyd*|*alttab*) return 1 ;;
    esac

    type="$(xprop -id "$wid" _NET_WM_WINDOW_TYPE 2>/dev/null || true)"
    case "$type" in
        *_NET_WM_WINDOW_TYPE_DESKTOP*|*_NET_WM_WINDOW_TYPE_DOCK*|*_NET_WM_WINDOW_TYPE_NOTIFICATION*|*_NET_WM_WINDOW_TYPE_TOOLTIP*|*_NET_WM_WINDOW_TYPE_POPUP_MENU*) return 1 ;;
    esac
    return 0
}

window_matches_expected() {
    local wid="$1" expected="$2" i class
    [[ -z "$expected" ]] && return 0
    for ((i=0; i<10; i++)); do
        class="$(window_class "$wid")"
        if [[ -n "$class" ]] && grep -Eiq "$expected" <<< "$class"; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

window_is_on_target() {
    local wid="$1" tx="$2" ty="$3" tw="$4" th="$5" geometry key value
    local wx=0 wy=0 ww=0 wh=0 cx cy
    geometry="$(xdotool getwindowgeometry --shell "$((wid))" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1
    while IFS='=' read -r key value; do
        case "$key" in
            X) wx="$value" ;;
            Y) wy="$value" ;;
            WIDTH) ww="$value" ;;
            HEIGHT) wh="$value" ;;
        esac
    done <<< "$geometry"
    cx=$((wx + ww / 2)); cy=$((wy + wh / 2))
    (( cx >= tx && cx < tx+tw && cy >= ty && cy < ty+th ))
}

move_window_to_target() {
    local wid="$1" target_x="$2" target_y="$3" target_w="$4" target_h="$5"
    local geometry key value wx=0 wy=0 ww=0 wh=0 cx cy current
    local src_x=0 src_y=0 local_x local_y max_x max_y new_x new_y state
    local was_max_h=0 was_max_v=0 was_fullscreen=0

    geometry="$(xdotool getwindowgeometry --shell "$((wid))" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1
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

    state="$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)"
    [[ "$state" == *_NET_WM_STATE_MAXIMIZED_HORZ* ]] && was_max_h=1
    [[ "$state" == *_NET_WM_STATE_MAXIMIZED_VERT* ]] && was_max_v=1
    [[ "$state" == *_NET_WM_STATE_FULLSCREEN* ]] && was_fullscreen=1

    if (( was_max_h || was_max_v || was_fullscreen )); then
        wmctrl -ir "$wid" -b remove,fullscreen,maximized_vert,maximized_horz >/dev/null 2>&1 || true
        sleep 0.04
    fi

    xdotool windowmove --sync "$((wid))" "$new_x" "$new_y" >/dev/null 2>&1 || return 1

    if (( was_max_h )); then wmctrl -ir "$wid" -b add,maximized_horz >/dev/null 2>&1 || true; fi
    if (( was_max_v )); then wmctrl -ir "$wid" -b add,maximized_vert >/dev/null 2>&1 || true; fi
    if (( was_fullscreen )); then wmctrl -ir "$wid" -b add,fullscreen >/dev/null 2>&1 || true; fi
    return 0
}

settle_and_move() {
    local wid="$1" tx="$2" ty="$3" tw="$4" th="$5"
    # O Chromium pode restaurar a geometria gravada alguns instantes depois de
    # mapear a janela. Trabalhamos apenas quando uma janela realmente surge:
    # não existe polling contínuo aqui.
    sleep 0.18
    move_window_to_target "$wid" "$tx" "$ty" "$tw" "$th" || true
    sleep 0.65
    if ! window_is_on_target "$wid" "$tx" "$ty" "$tw" "$th"; then
        move_window_to_target "$wid" "$tx" "$ty" "$tw" "$th" || true
    fi
}

arm_context() {
    local expected="${1:-}" target out x y w h expiry tmp
    command -v xdotool >/dev/null 2>&1 || return 1
    command -v xrandr >/dev/null 2>&1 || return 1
    target="$(pointer_target 2>/dev/null || true)"
    [[ -n "$target" ]] || return 1
    IFS=$'\t' read -r out x y w h <<< "$target"
    expiry=$(( $(now_ms) + CONTEXT_TTL_MS ))
    mkdir -p "$RUNTIME_BASE"
    tmp="$CONTEXT_FILE.$$"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$expiry" "$out" "$x" "$y" "$w" "$h" "$expected" > "$tmp"
    mv -f "$tmp" "$CONTEXT_FILE"
}

read_context() {
    CTX_EXPIRY=0; CTX_X=0; CTX_Y=0; CTX_W=0; CTX_H=0; CTX_EXPECTED=""
    [[ -r "$CONTEXT_FILE" ]] || return 1
    IFS=$'\t' read -r CTX_EXPIRY _ CTX_X CTX_Y CTX_W CTX_H CTX_EXPECTED < "$CONTEXT_FILE" || return 1
    if [[ ! "$CTX_EXPIRY" =~ ^[0-9]+$ ]] || (( $(now_ms) >= CTX_EXPIRY )); then
        rm -f "$CONTEXT_FILE"
        return 1
    fi
    return 0
}

consume_context() { rm -f "$CONTEXT_FILE"; }

parse_client_ids() {
    local line="$1" payload token
    local -a tokens=()
    payload="${line#*#}"
    payload="${payload//,/ }"
    read -r -a tokens <<< "$payload"
    for token in "${tokens[@]}"; do
        if [[ "$token" =~ ^0x[0-9a-fA-F]+$ ]]; then
            printf '%s\n' "${token,,}"
        fi
    done
}

initial_clients() {
    local line
    line="$(xprop -root _NET_CLIENT_LIST 2>/dev/null || true)"
    parse_client_ids "$line"
}

handle_explicit_active() {
    local wid="$1"
    read_context || return 1
    candidate_window "$wid" || return 1
    window_matches_expected "$wid" "$CTX_EXPECTED" || return 1
    settle_and_move "$wid" "$CTX_X" "$CTX_Y" "$CTX_W" "$CTX_H"
    consume_context
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

    trap 'pkill -P "$$" -x xprop >/dev/null 2>&1 || true; rm -f "$PID_FILE"' EXIT
    trap 'exit 0' INT TERM

    local whisker_until=0 target_out="" target_x=0 target_y=0 target_w=0 target_h=0
    local line wid target now id active
    declare -A seen=() current=()

    while IFS= read -r id; do seen["${id,,}"]=1; done < <(initial_clients)

    while true; do
        while IFS= read -r line; do
            if [[ "$line" == _NET_ACTIVE_WINDOW* ]]; then
                active="$(grep -Eo '0x[0-9a-fA-F]+' <<< "$line" | tail -n1 || true)"
                [[ "$active" =~ ^0x[0-9a-fA-F]+$ && "$active" != 0x0 ]] || continue
                active="${active,,}"

                if is_whisker_window "$active"; then
                    target="$(monitor_for_window "$((active))" 2>/dev/null || true)"
                    if [[ -n "$target" ]]; then
                        IFS=$'\t' read -r target_out target_x target_y target_w target_h <<< "$target"
                        whisker_until=$(( $(now_ms) + WHISKER_TTL_MS ))
                    fi
                else
                    # Contextos explícitos vêm dos launchers Wolf (Chrome,
                    # Terminal, Home). Isso também cobre um app já existente
                    # que é apenas reativado e não cria um novo client X11.
                    handle_explicit_active "$active" || true
                fi
                continue
            fi

            [[ "$line" == _NET_CLIENT_LIST* ]] || continue
            current=()
            while IFS= read -r id; do
                [[ -n "$id" ]] && current["$id"]=1
            done < <(parse_client_ids "$line")

            for id in "${!current[@]}"; do
                [[ -n "${seen[$id]:-}" ]] && continue

                if is_whisker_window "$id"; then
                    target="$(monitor_for_window "$((id))" 2>/dev/null || true)"
                    if [[ -n "$target" ]]; then
                        IFS=$'\t' read -r target_out target_x target_y target_w target_h <<< "$target"
                        whisker_until=$(( $(now_ms) + WHISKER_TTL_MS ))
                    fi
                    continue
                fi

                candidate_window "$id" || continue

                if read_context && window_matches_expected "$id" "$CTX_EXPECTED"; then
                    settle_and_move "$id" "$CTX_X" "$CTX_Y" "$CTX_W" "$CTX_H"
                    consume_context
                    continue
                fi

                now="$(now_ms)"
                if (( whisker_until > now )) && [[ -n "$target_out" ]]; then
                    settle_and_move "$id" "$target_x" "$target_y" "$target_w" "$target_h"
                    # Um lançamento pelo Whisker deve fornecer contexto apenas
                    # para a primeira nova janela de aplicação. Não deixe a
                    # janela de 6 s continuar elegível para uma aba do Chrome
                    # destacada logo depois, diálogos ou outras janelas.
                    whisker_until=0
                    target_out=""
                fi
            done

            seen=()
            for id in "${!current[@]}"; do seen["$id"]=1; done
        done < <(LC_ALL=C xprop -root -spy _NET_CLIENT_LIST _NET_ACTIVE_WINDOW 2>/dev/null)

        # xprop só deve sair se a sessão X estiver encerrando ou por erro.
        # Em erro transitório, reinicie o listener sem criar um loop agressivo.
        sleep 2
    done
}

start_daemon() {
    mkdir -p "$RUNTIME_BASE"
    if [[ -r "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then return 0; fi
    fi
    nohup "$0" daemon >/dev/null 2>&1 &
}

stop_daemon() {
    local pid=""
    [[ -r "$PID_FILE" ]] && pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE" "$CONTEXT_FILE"
}

status_daemon() {
    printf 'Wolf XFCE Window Placement v%s\n' "$VERSION"
    printf 'Modo: orientado a eventos (_NET_CLIENT_LIST/_NET_ACTIVE_WINDOW); sem polling do mouse\n'
    printf 'Whisker: novas janelas seguem o monitor onde o menu foi aberto\n'
    printf 'Launchers Wolf: seguem o monitor do ponteiro no momento do clique\n'
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
    arm) shift; arm_context "${1:-}" ;;
    *) echo "Uso: $0 {start|stop|restart|status|daemon|arm [regex-classe]}" >&2; exit 2 ;;
esac
