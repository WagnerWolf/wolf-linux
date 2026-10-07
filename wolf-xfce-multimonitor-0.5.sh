#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.5"
DISABLED_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-multimonitor.disabled"

log(){ printf '[Wolf XFCE MultiMonitor] %s\n' "$*"; }

set_prop() {
    local channel="$1" prop="$2" type="$3" value="$4"
    if xfconf-query -c "$channel" -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$prop" -s "$value" >/dev/null 2>&1 || true
    else
        xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" >/dev/null 2>&1 || true
    fi
}

set_int_array() {
    local channel="$1" prop="$2"; shift 2
    local args=(xfconf-query -c "$channel" -p "$prop") v
    xfconf-query -c "$channel" -p "$prop" -r >/dev/null 2>&1 || true
    args+=( -n -a )
    for v in "$@"; do args+=( -t int -s "$v" ); done
    "${args[@]}" >/dev/null 2>&1 || true
}

set_string_array() {
    local channel="$1" prop="$2"; shift 2
    local args=(xfconf-query -c "$channel" -p "$prop") v
    xfconf-query -c "$channel" -p "$prop" -r >/dev/null 2>&1 || true
    args+=( -n -a )
    for v in "$@"; do args+=( -t string -s "$v" ); done
    "${args[@]}" >/dev/null 2>&1 || true
}

monitor_outputs() { xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $NF}'; }
primary_output() {
    local out
    out="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && /\*/ {print $NF; exit}')"
    [[ -n "$out" ]] || out="$(monitor_outputs | head -n1)"
    printf '%s\n' "$out"
}

next_plugin_id() {
    local max=0 prop id
    while IFS= read -r prop; do
        [[ "$prop" =~ ^/plugins/plugin-([0-9]+)$ ]] || continue
        id="${BASH_REMATCH[1]}"
        (( id > max )) && max="$id"
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+$' || true)
    echo $((max + 1))
}

panel_ids() { xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' || true; }

launcher_source() {
    case "$1" in
        browser)  printf '%s\n' /usr/share/applications/wolf-xfce-browser.desktop ;;
        home)     printf '%s\n' /usr/share/applications/wolf-xfce-home.desktop ;;
        terminal) printf '%s\n' /usr/share/applications/wolf-xfce-terminal.desktop ;;
        *) return 1 ;;
    esac
}

create_launcher() {
    local id="$1" kind="$2" source base dir
    source="$(launcher_source "$kind")"
    [[ -f "$source" ]] || return 1
    base="$(basename "$source")"
    dir="$HOME/.config/xfce4/panel/launcher-$id"
    mkdir -p "$dir"
    cp -f "$source" "$dir/$base"
    chmod 644 "$dir/$base"
    set_prop xfce4-panel "/plugins/plugin-$id" string launcher
    set_string_array xfce4-panel "/plugins/plugin-$id/items" "$base"
}

configure_whisker() {
    local id="$1"
    set_prop xfce4-panel "/plugins/plugin-$id" string whiskermenu
    local icon="$HOME/.local/share/icons/wolf-whisker.png"
    local rc="$HOME/.config/xfce4/panel/whiskermenu-${id}.rc"
    mkdir -p "$(dirname "$rc")"
    touch "$rc"
    if [[ -f "$icon" ]]; then
        if grep -q '^button-icon=' "$rc"; then
            sed -i "s|^button-icon=.*|button-icon=$icon|" "$rc"
        else
            printf 'button-icon=%s\n' "$icon" >> "$rc"
        fi
    fi
    for kv in 'show-button-title=false' 'show-button-icon=true'; do
        local key="${kv%%=*}" value="${kv#*=}"
        if grep -q "^${key}=" "$rc"; then sed -i "s|^${key}=.*|${key}=${value}|" "$rc"; else printf '%s\n' "$kv" >> "$rc"; fi
    done
}

configure_tasklist() {
    local id="$1"
    set_prop xfce4-panel "/plugins/plugin-$id" string tasklist
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-monitors" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-workspaces" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/grouping" uint 1
    set_prop xfce4-panel "/plugins/plugin-$id/show-labels" bool true
}

create_secondary_layout() {
    local pid="$1" out="$2" next id
    local ids=()
    next="$(next_plugin_id)"

    set_prop xfce4-panel "/panels/panel-$pid/output-name" string "$out"
    set_prop xfce4-panel "/panels/panel-$pid/position" string 'p=8;x=0;y=0'
    set_prop xfce4-panel "/panels/panel-$pid/position-locked" bool true
    set_prop xfce4-panel "/panels/panel-$pid/length" uint 100
    set_prop xfce4-panel "/panels/panel-$pid/size" uint 36
    set_prop xfce4-panel "/panels/panel-$pid/nrows" uint 1
    set_prop xfce4-panel "/panels/panel-$pid/span-monitors" bool false
    set_prop xfce4-panel "/panels/panel-$pid/autohide-behavior" uint 0
    set_prop xfce4-panel "/panels/panel-$pid/wolf-managed" bool true
    set_prop xfce4-panel "/panels/panel-$pid/wolf-layout-version" int 5

    id="$next"; next=$((next+1)); ids+=("$id"); configure_whisker "$id"
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" browser
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" home
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" terminal
    id="$next"; next=$((next+1)); ids+=("$id"); configure_tasklist "$id"
    id="$next"; next=$((next+1)); ids+=("$id"); set_prop xfce4-panel "/plugins/plugin-$id" string separator; set_prop xfce4-panel "/plugins/plugin-$id/expand" bool true; set_prop xfce4-panel "/plugins/plugin-$id/style" uint 0
    id="$next"; ids+=("$id"); set_prop xfce4-panel "/plugins/plugin-$id" string clock

    set_int_array xfce4-panel "/panels/panel-$pid/plugin-ids" "${ids[@]}"
}

ensure_tasklists_local() {
    local prop type
    while IFS= read -r prop; do
        [[ "$prop" =~ ^/plugins/plugin-[0-9]+$ ]] || continue
        type="$(xfconf-query -c xfce4-panel -p "$prop" 2>/dev/null || true)"
        [[ "$type" == tasklist ]] || continue
        set_prop xfce4-panel "$prop/include-all-monitors" bool false
        set_prop xfce4-panel "$prop/include-all-workspaces" bool false
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+$' || true)
}

apply_layout() {
    [[ -e "$DISABLED_MARKER" ]] && return 0
    command -v xfconf-query >/dev/null 2>&1 || return 0
    command -v xrandr >/dev/null 2>&1 || return 0

    local primary out pid max_panel=1 used current_output
    local -a outputs=() panels=() managed=() secondary_outputs=() unused_managed=()
    mapfile -t outputs < <(monitor_outputs)
    ((${#outputs[@]})) || return 0
    primary="$(primary_output)"

    mapfile -t panels < <(panel_ids)
    if ((${#panels[@]} == 0)); then
        # Recuperação excepcional: só reconstrua o layout base se realmente
        # não existir painel algum. Em condições normais, nunca reescrevemos
        # preferências de plugins já existentes.
        /usr/local/bin/wolf-xfce-desktop-setup force >/dev/null 2>&1 || true
        mapfile -t panels < <(panel_ids)
    fi

    # A única preferência do painel principal gerenciada continuamente é o
    # output físico. Não tocamos em tamanho, scroll, autohide, plugins etc.
    current_output="$(xfconf-query -c xfce4-panel -p /panels/panel-1/output-name 2>/dev/null || true)"
    if [[ -n "$primary" && "$current_output" != "$primary" ]]; then
        set_prop xfce4-panel /panels/panel-1/output-name string "$primary"
        log "painel principal associado a $primary"
    fi

    for out in "${outputs[@]}"; do
        [[ "$out" == "$primary" ]] || secondary_outputs+=("$out")
    done

    for pid in "${panels[@]}"; do
        (( pid > max_panel )) && max_panel="$pid"
        [[ "$pid" == 1 ]] && continue
        if [[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/wolf-managed" 2>/dev/null || true)" == true ]]; then
            managed+=("$pid")
        fi
    done

    declare -A assigned=()
    for out in "${secondary_outputs[@]}"; do
        for pid in "${managed[@]}"; do
            if [[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/output-name" 2>/dev/null || true)" == "$out" ]]; then
                assigned["$out"]="$pid"
                break
            fi
        done
    done

    # Não fazemos mais "upgrade destrutivo" de painéis já existentes por
    # versão. O usuário pode personalizar scroll, tamanho, plugins e comportamento
    # à vontade; esses ajustes sobrevivem a reboot e hotplug.
    for pid in "${managed[@]}"; do
        used=0
        for out in "${!assigned[@]}"; do
            [[ "${assigned[$out]}" == "$pid" ]] && used=1
        done
        (( used == 0 )) && unused_managed+=("$pid")
    done

    for out in "${secondary_outputs[@]}"; do
        [[ -n "${assigned[$out]:-}" ]] && continue
        if ((${#unused_managed[@]})); then
            pid="${unused_managed[0]}"
            unused_managed=("${unused_managed[@]:1}")
            set_prop xfce4-panel "/panels/panel-$pid/output-name" string "$out"
            assigned["$out"]="$pid"
            log "painel Wolf existente reassociado a $out (panel-$pid)"
        else
            max_panel=$((max_panel + 1)); pid="$max_panel"
            panels+=("$pid")
            set_int_array xfce4-panel /panels "${panels[@]}"
            create_secondary_layout "$pid" "$out"
            assigned["$out"]="$pid"
            log "painel secundário criado em $out (panel-$pid)"
        fi
    done

    # Esta é parte essencial da política multimonitor e não altera scroll nem
    # demais preferências do tasklist.
    ensure_tasklists_local

    # NÃO execute xfce4-panel -r aqui. O painel observa xfconf em tempo real e
    # um restart no login estava sobrescrevendo/perturbando ajustes do usuário.
}

status() {
    printf 'Wolf XFCE MultiMonitor v%s\n' "$VERSION"
    local auto_state='ativado'
    [[ -e "$DISABLED_MARKER" ]] && auto_state='desativado'
    printf 'Automático: %s\n' "$auto_state"
    xrandr --listmonitors 2>/dev/null || true
    echo 'Painéis:'
    local pid
    while IFS= read -r pid; do
        local suffix=""
        [[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/wolf-managed" 2>/dev/null || true)" == true ]] && suffix=" [Wolf]"
        printf '  panel-%s -> %s%s\n' "$pid" \
            "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/output-name" 2>/dev/null || echo Automatic)" \
            "$suffix"
    done < <(panel_ids)
}

watch_loop() {
    command -v xev >/dev/null 2>&1 || {
        log "xev não encontrado; aplicando layout uma vez e encerrando o watcher."
        apply_layout
        return 0
    }

    # Reconciliação leve no início da sessão. Como apply_layout é não destrutivo,
    # isso não reinicia o painel nem restaura preferências padrão.
    apply_layout

    local line now last_apply=0
    while true; do
        while IFS= read -r line; do
            [[ -e "$DISABLED_MARKER" ]] && continue
            if [[ "$line" == *"RRScreenChangeNotify event"* || "$line" == *"RRNotify event"* ]]; then
                now="$(date +%s%3N)"
                # XRandR pode emitir vários eventos para uma única operação.
                # Debounce sem polling: apenas ignore a rajada por 1500 ms.
                if (( now - last_apply < 1500 )); then
                    continue
                fi
                last_apply="$now"
                sleep 1
                apply_layout
            fi
        done < <(LC_ALL=C xev -root -event randr 2>/dev/null)

        # Reinicie o listener somente se xev morrer inesperadamente.
        sleep 2
    done
}

case "${1:-apply}" in
    apply) apply_layout ;;
    watch) watch_loop ;;
    status) status ;;
    enable) rm -f "$DISABLED_MARKER"; apply_layout ;;
    disable) mkdir -p "$(dirname "$DISABLED_MARKER")"; touch "$DISABLED_MARKER" ;;
    *) echo "Uso: $0 [apply|watch|status|enable|disable]" >&2; exit 2 ;;
esac
