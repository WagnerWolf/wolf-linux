#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="1.0.36"
log(){ printf '[Wolf XFCE Fix %s] %s\n' "$VERSION" "$*"; }

[[ $EUID -ne 0 ]] || {
    echo "Execute este helper como usuário normal; ele solicitará sudo quando necessário." >&2
    exit 1
}

log "Instalando integração XDG/Thunar..."
sudo pacman -S --needed --noconfirm xdg-user-dirs-gtk gvfs

log "Atualizando launchers Wolf XFCE..."
sudo tee /usr/share/applications/wolf-xfce-browser.desktop >/dev/null <<'EOF_BROWSER'
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=google-chrome-stable %U
Icon=google-chrome
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=Network;WebBrowser;
EOF_BROWSER
sudo tee /usr/share/applications/wolf-xfce-home.desktop >/dev/null <<'EOF_HOME'
[Desktop Entry]
Type=Application
Name=Pasta pessoal
Exec=thunar
Icon=user-home
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=System;FileTools;FileManager;
EOF_HOME
sudo tee /usr/share/applications/wolf-xfce-terminal.desktop >/dev/null <<'EOF_TERMINAL_DESKTOP'
[Desktop Entry]
Type=Application
Name=Terminal
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=System;TerminalEmulator;
EOF_TERMINAL_DESKTOP

log "Instalando Wolf XFCE Desktop Setup v0.2..."
tmp_setup="$(mktemp)"
cat > "$tmp_setup" <<'WOLF_SETUP'
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
WOLF_SETUP
sudo install -m 0755 "$tmp_setup" /usr/local/bin/wolf-xfce-desktop-setup
rm -f "$tmp_setup"

log "Instalando Wolf XFCE MultiMonitor v0.3..."
tmp_mm="$(mktemp)"
cat > "$tmp_mm" <<'WOLF_MM'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.3"
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
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" browser
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" home
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" terminal
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

    local primary out pid max_panel=1 used
    local -a outputs=() panels=() managed=() secondary_outputs=() unused_managed=()
    mapfile -t outputs < <(monitor_outputs)
    ((${#outputs[@]})) || return 0
    primary="$(primary_output)"

    mapfile -t panels < <(panel_ids)
    if ((${#panels[@]} == 0)); then
        /usr/local/bin/wolf-xfce-desktop-setup force >/dev/null 2>&1 || true
        mapfile -t panels < <(panel_ids)
    fi

    set_prop xfce4-panel /panels/panel-1/output-name string "$primary"
    set_prop xfce4-panel /panels/dark-mode bool true

    for out in "${outputs[@]}"; do [[ "$out" == "$primary" ]] || secondary_outputs+=("$out"); done

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
                assigned["$out"]="$pid"; break
            fi
        done
    done

    for pid in "${managed[@]}"; do
        used=0
        for out in "${!assigned[@]}"; do [[ "${assigned[$out]}" == "$pid" ]] && used=1; done
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
WOLF_MM
sudo install -m 0755 "$tmp_mm" /usr/local/bin/wolf-xfce-multimonitor
rm -f "$tmp_mm"

rm -f "$HOME/.config/wolf-linux/xfce-layout-v1.done"       "$HOME/.config/wolf-linux/xfce-layout-v2.done"       "$HOME/.config/wolf-linux/terminal-v2.done" 2>/dev/null || true

log "Atualizando diretórios XDG..."
xdg-user-dirs-update >/dev/null 2>&1 || true

log "Reconstruindo painel, tema, wallpaper e terminal..."
/usr/local/bin/wolf-xfce-desktop-setup force
/usr/local/bin/wolf-xfce-multimonitor apply

log "Estado final:"
/usr/local/bin/wolf-xfce-desktop-setup status || true
/usr/local/bin/wolf-xfce-multimonitor status || true

echo
echo "[OK] Polimento XFCE aplicado."
echo "Painel: Whisker | Chrome | Pasta pessoal | Terminal | apps locais | tray | relógio | mostrar desktop."
echo "Nos monitores secundários, 'mostrar desktop' é omitido por ser uma ação global."
echo
echo "Feche e reabra Thunar/xfce4-terminal para enxergar imediatamente todas as mudanças."
echo "Se algum aplicativo antigo continuar claro, faça logout/login uma vez."
