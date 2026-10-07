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

    set_prop xfce4-panel /configver int 2
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
    for ((attempt=0; attempt<12; attempt++)); do
        while IFS= read -r prop; do
            [[ -n "$prop" ]] || continue
            xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" >/dev/null 2>&1 || true
            found=1
        done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)
        (( found == 1 )) && break
        sleep 1
    done
    if command -v xfdesktop >/dev/null 2>&1; then
        xfdesktop --reload >/dev/null 2>&1 || true
    fi
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
    local marker_state='pendente'
    if [[ -f "$MARKER" ]]; then marker_state='aplicado'; fi
    printf 'Marcador: %s\n' "$marker_state"
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
