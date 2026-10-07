#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.2"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/xfce"
MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v2.done"
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
FORCE=0

log(){ printf '[Wolf XFCE Setup] %s\n' "$*"; }

if [[ "${1:-apply}" == "--force" || "${2:-}" == "--force" ]]; then
    FORCE=1
fi

wait_for_xfce() {
    local i
    for ((i=0; i<30; i++)); do
        if xfconf-query -c xsettings -p /Net/ThemeName >/dev/null 2>&1 \
            && xrandr --listmonitors >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log "xfconf/XRandR ainda não ficaram prontos; tentando mesmo assim."
}

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

connected_outputs() {
    xrandr --query 2>/dev/null | awk '$2 == "connected" {print $1}'
}

primary_output() {
    local out
    out="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && /\*/ {print $NF; exit}')"
    [[ -n "$out" ]] || out="$(connected_outputs | head -n1)"
    printf '%s\n' "$out"
}

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
    [[ -f "$source" ]] || { log "Launcher ausente: $source"; return 1; }
    base="$(basename "$source")"
    dir="$HOME/.config/xfce4/panel/launcher-$id"
    mkdir -p "$dir"
    cp -f "$source" "$dir/$base"
    chmod 644 "$dir/$base"
    set_prop xfce4-panel "/plugins/plugin-$id" string launcher
    set_string_array xfce4-panel "/plugins/plugin-$id/items" "$base"
}

configure_tasklist() {
    local id="$1"
    set_prop xfce4-panel "/plugins/plugin-$id" string tasklist
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-monitors" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-workspaces" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/grouping" uint 1
    set_prop xfce4-panel "/plugins/plugin-$id/show-labels" bool true
}

create_main_panel() {
    local out="$1"
    local ids=(1 2 3 4 5 6 7 8 9)

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
    create_launcher 2 browser
    create_launcher 3 home
    create_launcher 4 terminal
    configure_tasklist 5

    set_prop xfce4-panel /plugins/plugin-6 string separator
    set_prop xfce4-panel /plugins/plugin-6/expand bool true
    set_prop xfce4-panel /plugins/plugin-6/style uint 0

    set_prop xfce4-panel /plugins/plugin-7 string systray
    set_prop xfce4-panel /plugins/plugin-7/square-icons bool true
    set_prop xfce4-panel /plugins/plugin-8 string clock
    set_prop xfce4-panel /plugins/plugin-9 string showdesktop
}

apply_style() {
    set_prop xsettings /Net/ThemeName string Materia-dark
    set_prop xsettings /Net/IconThemeName string Papirus-Dark
    set_prop xsettings /Gtk/CursorThemeName string breeze_cursors
    set_prop xsettings /Gtk/CursorThemeSize int 24
    set_prop xsettings /Gtk/MonospaceFontName string 'MesloLGS Nerd Font 11'
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

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    fi
}

apply_terminal_style() {
    mkdir -p "$HOME/.config/xfce4/terminal"
    cat > "$HOME/.config/xfce4/terminal/terminalrc" <<'EOF_TERMINAL'
[Configuration]
FontName=MesloLGS Nerd Font 11
ColorForeground=#FFFFFF
ColorBackground=#000000
ColorUseTheme=FALSE
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=120x30
MiscInheritGeometry=FALSE
MiscMenubarDefault=FALSE
MiscMouseAutohide=FALSE
MiscMouseWheelZoom=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
ScrollingBar=TERMINAL_SCROLLBAR_NONE
ScrollingLines=10000
EOF_TERMINAL
}

path_to_uri() {
    python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve().as_uri())
PY
}

apply_user_dirs() {
    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        xdg-user-dirs-update >/dev/null 2>&1 || true
    fi
    mkdir -p "$HOME/.config/gtk-3.0"
    local bookmarks="$HOME/.config/gtk-3.0/bookmarks" tmp kind path uri label
    tmp="$(mktemp)"
    [[ -f "$bookmarks" ]] && cat "$bookmarks" > "$tmp"

    for kind in DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS TEMPLATES PUBLICSHARE; do
        path="$(xdg-user-dir "$kind" 2>/dev/null || true)"
        [[ -n "$path" && "$path" != "$HOME" && -d "$path" ]] || continue
        uri="$(path_to_uri "$path")"
        label="$(basename "$path")"
        grep -Fq "$uri" "$tmp" 2>/dev/null || printf '%s %s\n' "$uri" "$label" >> "$tmp"
    done
    mv -f "$tmp" "$bookmarks"
}

apply_wallpaper() {
    [[ -f "$WALLPAPER" ]] || { log "Wallpaper Wolf não encontrado: $WALLPAPER"; return 0; }

    set_prop xfce4-desktop /backdrop/single-workspace-mode bool true
    set_prop xfce4-desktop /backdrop/single-workspace-number int 0

    local out base prop
    while IFS= read -r out; do
        [[ -n "$out" ]] || continue
        base="/backdrop/screen0/monitor${out}/workspace0"
        set_prop xfce4-desktop "$base/last-image" string "$WALLPAPER"
        set_prop xfce4-desktop "$base/image-style" int 5
        set_prop xfce4-desktop "$base/color-style" int 0
    done < <(connected_outputs)

    while IFS= read -r prop; do
        [[ -n "$prop" ]] || continue
        case "$prop" in
            */last-image|*/last-single-image|*/image-path)
                xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" >/dev/null 2>&1 || true
                ;;
        esac
    done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null || true)

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
    wait_for_xfce

    local out
    out="$(primary_output)"
    [[ -n "$out" ]] || { log "Nenhum monitor ativo detectado."; return 1; }

    backup_current
    xfce4-panel -q >/dev/null 2>&1 || true
    sleep 1
    xfconf-query -c xfce4-panel -p /panels -r -R >/dev/null 2>&1 || true
    xfconf-query -c xfce4-panel -p /plugins -r -R >/dev/null 2>&1 || true
    xfconf-query -c xfce4-panel -p /configver -r >/dev/null 2>&1 || true
    rm -rf "$HOME/.config/xfce4/panel/launcher-"* 2>/dev/null || true

    create_main_panel "$out"
    apply_style
    apply_terminal_style
    apply_user_dirs
    apply_wallpaper

    nohup xfce4-panel >/dev/null 2>&1 &
    sleep 2

    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    log "Painel principal Wolf Linux aplicado em $out."
}

status() {
    printf 'Wolf XFCE Desktop Setup v%s\n' "$VERSION"
    local marker_state="pendente"
    [[ -f "$MARKER" ]] && marker_state="aplicado"
    printf 'Marcador: %s\n' "$marker_state"
    printf 'Tema: %s\n' "$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)"
    printf 'Tema XFWM: %s\n' "$(xfconf-query -c xfwm4 -p /general/theme 2>/dev/null || true)"
    printf 'Workspaces: %s\n' "$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || true)"
    printf 'Painéis: '
    xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true
    printf 'Fonte terminal: '
    grep '^FontName=' "$HOME/.config/xfce4/terminal/terminalrc" 2>/dev/null || true
}

case "${1:-apply}" in
    apply)
        wait_for_xfce
        if [[ -f "$MARKER" && "$FORCE" -eq 0 ]]; then
            apply_style
            apply_terminal_style
            apply_user_dirs
            apply_wallpaper
            exit 0
        fi
        apply_layout
        ;;
    force|--force)
        FORCE=1
        apply_layout
        ;;
    status) status ;;
    *) echo "Uso: $0 [apply|force|status]" >&2; exit 2 ;;
esac
