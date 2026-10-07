#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="1.0.35"
log(){ printf '[Wolf XFCE Fix %s] %s\n' "$VERSION" "$*"; }

[[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" == *XFCE* || "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" == *Xfce* ]]     || log "Aviso: execute preferencialmente dentro de uma sessão XFCE X11."

sudo install -d /usr/local/bin /usr/local/sbin /etc/pacman.d/hooks /etc/xdg/autostart /usr/share/applications /etc/xdg/xfce4/panel

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/wolf-xfce-desktop-setup" <<'SETUP'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.1"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/xfce"
MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v1.done"
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
FORCE=0

log(){ printf '[Wolf XFCE Setup] %s\n' "$*"; }

if [[ "${1:-apply}" == "--force" || "${2:-}" == "--force" ]]; then
    FORCE=1
fi

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
    for v in "$@"; do
        args+=( -t int -s "$v" )
    done
    "${args[@]}" >/dev/null 2>&1 || true
}

set_string_array() {
    local channel="$1" prop="$2"; shift 2
    local args=(xfconf-query -c "$channel" -p "$prop") v
    xfconf-query -c "$channel" -p "$prop" -r >/dev/null 2>&1 || true
    args+=( -n -a )
    for v in "$@"; do
        args+=( -t string -s "$v" )
    done
    "${args[@]}" >/dev/null 2>&1 || true
}

primary_output() {
    local out
    out="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && /\*/ {print $NF; exit}')"
    if [[ -z "$out" ]]; then
        out="$(xrandr --listmonitors 2>/dev/null | awk 'NR==2 {print $NF; exit}')"
    fi
    printf '%s\n' "$out"
}

create_launcher() {
    local id="$1" desktop_file="$2"
    set_prop xfce4-panel "/plugins/plugin-$id" string launcher
    set_string_array xfce4-panel "/plugins/plugin-$id/items" "$desktop_file"
}

create_main_panel() {
    local out="$1"
    local ids=(1 2 3 4 5 6 7 8 9 10)

    set_int_array xfce4-panel /panels 1
    set_prop xfce4-panel /panels/dark-mode bool true

    set_prop xfce4-panel /panels/panel-1/output-name string "$out"
    set_prop xfce4-panel /panels/panel-1/position string 'p=8;x=0;y=0'
    set_prop xfce4-panel /panels/panel-1/position-locked bool true
    set_prop xfce4-panel /panels/panel-1/length uint 100
    set_prop xfce4-panel /panels/panel-1/size uint 36
    set_prop xfce4-panel /panels/panel-1/nrows uint 1
    set_prop xfce4-panel /panels/panel-1/span-monitors bool false
    set_prop xfce4-panel /panels/panel-1/autohide-behavior uint 0
    set_int_array xfce4-panel /panels/panel-1/plugin-ids "${ids[@]}"

    set_prop xfce4-panel /plugins/plugin-1 string whiskermenu
    create_launcher 2 wolf-files.desktop
    create_launcher 3 wolf-terminal.desktop
    create_launcher 4 wolf-browser.desktop
    create_launcher 5 wolf-code.desktop

    set_prop xfce4-panel /plugins/plugin-6 string tasklist
    set_prop xfce4-panel /plugins/plugin-6/include-all-monitors bool false
    set_prop xfce4-panel /plugins/plugin-6/include-all-workspaces bool false
    set_prop xfce4-panel /plugins/plugin-6/grouping uint 1
    set_prop xfce4-panel /plugins/plugin-6/show-labels bool true

    set_prop xfce4-panel /plugins/plugin-7 string separator
    set_prop xfce4-panel /plugins/plugin-7/expand bool true
    set_prop xfce4-panel /plugins/plugin-7/style uint 0

    set_prop xfce4-panel /plugins/plugin-8 string systray
    set_prop xfce4-panel /plugins/plugin-8/square-icons bool true

    set_prop xfce4-panel /plugins/plugin-9 string clock
    set_prop xfce4-panel /plugins/plugin-10 string showdesktop
}

apply_style() {
    set_prop xsettings /Net/ThemeName string Materia-dark
    set_prop xsettings /Net/IconThemeName string Papirus-Dark
    set_prop xsettings /Gtk/CursorThemeName string breeze_cursors
    set_prop xsettings /Gtk/CursorThemeSize int 24
    set_prop xsettings /Xfce/SyncThemes bool true
    set_prop xfwm4 /general/theme string Materia-dark
    set_prop xfwm4 /general/workspace_count int 1

    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.local/share/icons/default"
    cat > "$HOME/.config/gtk-3.0/settings.ini" <<'GTK'
[Settings]
gtk-application-prefer-dark-theme=true
gtk-theme-name=Materia-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=breeze_cursors
gtk-cursor-theme-size=24
GTK
    cp -f "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
    cat > "$HOME/.local/share/icons/default/index.theme" <<'CURSOR'
[Icon Theme]
Inherits=breeze_cursors
CURSOR
}

apply_wallpaper() {
    [[ -f "$WALLPAPER" ]] || return 0
    local attempt prop found=0
    for attempt in {1..12}; do
        while IFS= read -r prop; do
            [[ -n "$prop" ]] || continue
            xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" >/dev/null 2>&1 || true
            found=1
        done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)
        (( found == 1 )) && break
        sleep 1
    done
    command -v xfdesktop >/dev/null 2>&1 && xfdesktop --reload >/dev/null 2>&1 || true
}

backup_current() {
    local stamp dest
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="$STATE_DIR/$stamp"
    mkdir -p "$dest"
    if [[ -d "$HOME/.config/xfce4" ]]; then
        cp -a "$HOME/.config/xfce4" "$dest/xfce4-config" 2>/dev/null || true
    fi
    xfconf-query -c xfce4-panel -lv > "$dest/xfce4-panel.txt" 2>/dev/null || true
    printf '%s\n' "$dest" > "$STATE_DIR/latest"
    log "Backup: $dest"
}

apply_layout() {
    command -v xfconf-query >/dev/null 2>&1 || return 0
    command -v xrandr >/dev/null 2>&1 || return 0

    local out
    out="$(primary_output)"
    [[ -n "$out" ]] || { log "Nenhum monitor ativo detectado."; return 1; }

    backup_current

    xfce4-panel -q >/dev/null 2>&1 || true
    sleep 1
    xfconf-query -c xfce4-panel -p /panels -r -R >/dev/null 2>&1 || true
    xfconf-query -c xfce4-panel -p /plugins -r -R >/dev/null 2>&1 || true
    xfconf-query -c xfce4-panel -p /configver -r >/dev/null 2>&1 || true

    create_main_panel "$out"
    apply_style
    apply_wallpaper

    nohup xfce4-panel >/dev/null 2>&1 &
    sleep 2

    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    log "Painel principal Wolf Linux aplicado em $out."
}

status() {
    printf 'Wolf XFCE Desktop Setup v%s\n' "$VERSION"
    printf 'Marcador: %s\n' "$([[ -f "$MARKER" ]] && echo aplicado || echo pendente)"
    printf 'Tema: %s\n' "$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)"
    printf 'Tema XFWM: %s\n' "$(xfconf-query -c xfwm4 -p /general/theme 2>/dev/null || true)"
    printf 'Workspaces: %s\n' "$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || true)"
    printf 'Painéis: '
    xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true
}

case "${1:-apply}" in
    apply)
        if [[ -f "$MARKER" && "$FORCE" -eq 0 ]]; then
            apply_style
            apply_wallpaper
            exit 0
        fi
        apply_layout
        ;;
    force|--force)
        FORCE=1
        apply_layout
        ;;
    status)
        status
        ;;
    *)
        echo "Uso: $0 [apply|force|status]" >&2
        exit 2
        ;;
esac
SETUP
cat > "$tmp/wolf-xfce-multimonitor" <<'MM'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.2"
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

monitor_outputs() {
    xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $NF}'
}

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

panel_ids() {
    xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' || true
}

create_launcher() {
    local id="$1" desktop_file="$2"
    set_prop xfce4-panel "/plugins/plugin-$id" string launcher
    set_string_array xfce4-panel "/plugins/plugin-$id/items" "$desktop_file"
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

    id="$next"; next=$((next+1)); ids+=("$id"); set_prop xfce4-panel "/plugins/plugin-$id" string whiskermenu
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" wolf-files.desktop
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" wolf-terminal.desktop
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" wolf-browser.desktop
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" wolf-code.desktop
    id="$next"; next=$((next+1)); ids+=("$id"); configure_tasklist "$id"
    id="$next"; next=$((next+1)); ids+=("$id"); set_prop xfce4-panel "/plugins/plugin-$id" string separator; set_prop xfce4-panel "/plugins/plugin-$id/expand" bool true; set_prop xfce4-panel "/plugins/plugin-$id/style" uint 0
    id="$next"; next=$((next+1)); ids+=("$id"); set_prop xfce4-panel "/plugins/plugin-$id" string systray; set_prop xfce4-panel "/plugins/plugin-$id/square-icons" bool true
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

    local primary out pid max_panel=1
    local -a outputs=() panels=() managed=() secondary_outputs=() unused_managed=()
    mapfile -t outputs < <(monitor_outputs)
    ((${#outputs[@]})) || return 0
    primary="$(primary_output)"

    mapfile -t panels < <(panel_ids)
    if ((${#panels[@]} == 0)); then
        /usr/local/bin/wolf-xfce-desktop-setup force >/dev/null 2>&1 || true
        mapfile -t panels < <(panel_ids)
    fi

    # O painel 1 é sempre o painel completo e acompanha o monitor principal.
    set_prop xfce4-panel /panels/panel-1/output-name string "$primary"
    set_prop xfce4-panel /panels/dark-mode bool true

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

    # Primeiro reaproveite painéis já associados às telas secundárias atuais.
    declare -A assigned=()
    for out in "${secondary_outputs[@]}"; do
        for pid in "${managed[@]}"; do
            if [[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/output-name" 2>/dev/null || true)" == "$out" ]]; then
                assigned["$out"]="$pid"
                break
            fi
        done
    done

    for pid in "${managed[@]}"; do
        local used=0
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
        else
            max_panel=$((max_panel + 1)); pid="$max_panel"
            panels+=("$pid")
            set_int_array xfce4-panel /panels "${panels[@]}"
            create_secondary_layout "$pid" "$out"
            assigned["$out"]="$pid"
            log "painel secundário criado em $out (panel-$pid)"
        fi
    done

    ensure_tasklists_local
    xfce4-panel -r >/dev/null 2>&1 || true
}

status() {
    printf 'Wolf XFCE MultiMonitor v%s\n' "$VERSION"
    printf 'Automático: %s\n' "$([[ -e "$DISABLED_MARKER" ]] && echo desativado || echo ativado)"
    xrandr --listmonitors 2>/dev/null || true
    echo 'Painéis:'
    local pid
    while IFS= read -r pid; do
        printf '  panel-%s -> %s%s\n' "$pid" \
            "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/output-name" 2>/dev/null || echo Automatic)" \
            "$([[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/wolf-managed" 2>/dev/null || true)" == true ]] && echo ' [Wolf]' || true)"
    done < <(panel_ids)
}

watch_loop() {
    local old="" new=""
    while true; do
        [[ -e "$DISABLED_MARKER" ]] && { sleep 5; continue; }
        new="$(xrandr --listmonitors 2>/dev/null | tail -n +2 | sha256sum | awk '{print $1}')"
        if [[ "$new" != "$old" ]]; then
            sleep 2
            apply_layout
            old="$new"
        fi
        sleep 3
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
MM
sudo install -m 0755 "$tmp/wolf-xfce-desktop-setup" /usr/local/bin/wolf-xfce-desktop-setup
sudo install -m 0755 "$tmp/wolf-xfce-multimonitor" /usr/local/bin/wolf-xfce-multimonitor

cat > "$tmp/wolf-disable-xfce-wayland" <<'X11'
#!/usr/bin/env bash
set -euo pipefail
rm -f /usr/share/wayland-sessions/xfce-wayland.desktop
X11
sudo install -m 0755 "$tmp/wolf-disable-xfce-wayland" /usr/local/sbin/wolf-disable-xfce-wayland

cat > "$tmp/wolf-xfce-x11-only.hook" <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = xfce4-session

[Action]
Description = Wolf Linux: mantendo XFCE somente em X11...
When = PostTransaction
Exec = /usr/local/sbin/wolf-disable-xfce-wayland
HOOK
sudo install -m 0644 "$tmp/wolf-xfce-x11-only.hook" /etc/pacman.d/hooks/wolf-xfce-x11-only.hook
sudo /usr/local/sbin/wolf-disable-xfce-wayland

cat > "$tmp/wolf-files.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Arquivos
Exec=thunar
Icon=system-file-manager
Terminal=false
NoDisplay=true
EOF
cat > "$tmp/wolf-terminal.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Terminal
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
NoDisplay=true
EOF
cat > "$tmp/wolf-browser.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=google-chrome-stable %U
Icon=google-chrome
Terminal=false
NoDisplay=true
EOF
cat > "$tmp/wolf-code.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Visual Studio Code
Exec=code %F
Icon=visual-studio-code
Terminal=false
NoDisplay=true
EOF
sudo install -m 0644 "$tmp"/wolf-*.desktop /usr/share/applications/

cat > "$tmp/wolf-xfce-desktop-setup.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - XFCE Desktop Setup
Exec=sh -c 'sleep 3; /usr/local/bin/wolf-xfce-desktop-setup apply'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
EOF
cat > "$tmp/wolf-xfce-multimonitor.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - XFCE MultiMonitor
Exec=sh -c 'sleep 7; /usr/local/bin/wolf-xfce-multimonitor watch'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
EOF
sudo install -m 0644 "$tmp/wolf-xfce-desktop-setup.desktop" /etc/xdg/autostart/
sudo install -m 0644 "$tmp/wolf-xfce-multimonitor.desktop" /etc/xdg/autostart/

log "Aplicando tema, um workspace e painel Wolf nesta sessão..."
/usr/local/bin/wolf-xfce-desktop-setup force
sleep 2
/usr/local/bin/wolf-xfce-multimonitor apply

log "Concluído. Wayland do XFCE removido; faça logout/login para confirmar o SDDM."
