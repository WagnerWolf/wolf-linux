#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.5"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/xfce"
MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v5.done"
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
WHISKER_ICON="$HOME/.local/share/icons/wolf-whisker.png"
FORCE=0
PANEL_RESTART_PENDING=0

log(){ printf '[Wolf XFCE Setup] %s\n' "$*"; }

ensure_panel_on_exit() {
    if (( PANEL_RESTART_PENDING )) && command -v xfce4-panel >/dev/null 2>&1; then
        log "Reconstrução interrompida; reiniciando xfce4-panel como proteção."
        nohup xfce4-panel >/dev/null 2>&1 &
    fi
}
trap ensure_panel_on_exit EXIT

report_setup_error() {
    local rc="$?"
    local line="${BASH_LINENO[0]:-${LINENO}}"
    printf '[Wolf XFCE Setup] ERRO: linha %s: %s (status %s)\n' \
        "$line" "$BASH_COMMAND" "$rc" >&2
    return "$rc"
}
trap report_setup_error ERR

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

create_whisker_icon() {
    local src=""
    for candidate in \
        /usr/share/plymouth/themes/wolf-linux/logo.png \
        /usr/share/icons/hicolor/256x256/apps/wolf-linux.png \
        /usr/share/pixmaps/wolf-linux.png; do
        if [[ -r "$candidate" ]]; then src="$candidate"; break; fi
    done
    [[ -n "$src" ]] || return 0
    mkdir -p "$(dirname "$WHISKER_ICON")"
    python3 - "$src" "$WHISKER_ICON" <<'PYICON'
from PIL import Image, ImageDraw
import sys
src, dst = sys.argv[1:3]
im = Image.open(src).convert('RGBA')
alpha = im.getchannel('A')
bbox = alpha.getbbox()
if bbox:
    im = im.crop(bbox)
size = 128
canvas = Image.new('RGBA', (size, size), (0,0,0,0))
d = ImageDraw.Draw(canvas)
d.ellipse((3,3,size-4,size-4), fill=(24,24,27,245), outline=(220,220,224,255), width=4)
im.thumbnail((92,92), Image.Resampling.LANCZOS)
x=(size-im.width)//2; y=(size-im.height)//2
canvas.alpha_composite(im, (x,y))
canvas.save(dst)
PYICON
}

set_rc_value() {
    local file="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

configure_whisker() {
    local id="$1"
    local rc="$HOME/.config/xfce4/panel/whiskermenu-${id}.rc"
    set_prop xfce4-panel "/plugins/plugin-$id" string whiskermenu
    create_whisker_icon
    [[ -f "$WHISKER_ICON" ]] && set_rc_value "$rc" button-icon "$WHISKER_ICON"
    set_rc_value "$rc" show-button-title false
    set_rc_value "$rc" show-button-icon true
}

configure_all_whiskers() {
    local prop id type
    while IFS= read -r prop; do
        [[ "$prop" =~ ^/plugins/plugin-([0-9]+)$ ]] || continue
        id="${BASH_REMATCH[1]}"
        type="$(xfconf-query -c xfce4-panel -p "$prop" 2>/dev/null || true)"
        if [[ "$type" == whiskermenu ]]; then
            configure_whisker "$id"
        fi
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+$' || true)

    # Com `set -e`, o status da última condição dentro de um while pode
    # vazar como status da função. Esta função é de varredura/best-effort:
    # não encontrar Whisker no último plugin nunca deve abortar o layout.
    return 0
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

    configure_whisker 1
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
    # Novas janelas seguem o monitor do ponteiro. Isso faz lançamentos pelo
    # Whisker de cada tela tenderem naturalmente a nascer naquela mesma tela.
    set_prop xfwm4 /general/placement_mode string mouse
    set_prop xfwm4 /general/placement_ratio int 100
    set_prop xfwm4 /general/focus_new bool true
    set_prop xfce4-panel /panels/dark-mode bool true

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

apply_xfce_helpers() {
    mkdir -p "$HOME/.config/xfce4" "$HOME/.local/share/xfce4/helpers"
    cat > "$HOME/.config/xfce4/helpers.rc" <<'HELPERS'
WebBrowser=custom-WebBrowser
FileManager=Thunar
TerminalEmulator=xfce4-terminal
HELPERS
    cat > "$HOME/.local/share/xfce4/helpers/custom-WebBrowser.desktop" <<'BROWSER'
[Desktop Entry]
NoDisplay=true
Version=1.0
Encoding=UTF-8
Type=X-XFCE-Helper
X-XFCE-Category=WebBrowser
X-XFCE-CommandsWithParameter=/usr/bin/google-chrome-stable "%s"
Icon=google-chrome
Name=Google Chrome
X-XFCE-Commands=/usr/bin/google-chrome-stable
BROWSER
}

apply_thunar_vscode_action() {
    command -v code >/dev/null 2>&1 || return 0
    mkdir -p "$HOME/.config/Thunar"
    python3 - "$HOME/.config/Thunar/uca.xml" <<'PYUCA'
from pathlib import Path
import sys, xml.etree.ElementTree as ET
p=Path(sys.argv[1])
try:
    tree=ET.parse(p); root=tree.getroot()
except Exception:
    root=ET.Element('actions'); tree=ET.ElementTree(root)
name='Abrir esta pasta no VS Code'
for action in list(root.findall('action')):
    n=action.find('name')
    uid=action.find('unique-id')
    if (n is not None and n.text == name) or (uid is not None and uid.text == 'wolf-open-vscode'):
        root.remove(action)
a=ET.SubElement(root,'action')
for tag,text in [
    ('icon','visual-studio-code'),
    ('name',name),
    ('submenu',''),
    ('unique-id','wolf-open-vscode'),
    ('command','code --new-window "%f"'),
    ('description','Abrir a pasta atual no Visual Studio Code'),
    ('range','*'),
    ('patterns','*'),
]:
    e=ET.SubElement(a,tag); e.text=text
ET.SubElement(a,'directories')
ET.indent(tree, space='  ')
p.parent.mkdir(parents=True,exist_ok=True)
tree.write(p,encoding='UTF-8',xml_declaration=True)
PYUCA
}

apply_mouse_flat() {
    if [[ "${XDG_SESSION_TYPE:-x11}" == x11 ]] && [[ -x /usr/local/bin/wolf-disable-mouse-accel.sh ]]; then
        /usr/local/bin/wolf-disable-mouse-accel.sh >/dev/null 2>&1 || true
    fi
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

    # Tudo que pode falhar sem tocar no painel é preparado antes da etapa destrutiva.
    create_whisker_icon
    backup_current
    PANEL_RESTART_PENDING=1
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
    apply_xfce_helpers
    apply_thunar_vscode_action
    apply_wallpaper
    configure_all_whiskers
    apply_mouse_flat

    nohup xfce4-panel >/dev/null 2>&1 &
    sleep 2
    PANEL_RESTART_PENDING=0

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
    printf 'Placement: %s\n' "$(xfconf-query -c xfwm4 -p /general/placement_mode 2>/dev/null || true)"
    printf 'Ícone Whisker: %s\n' "$WHISKER_ICON"
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
            apply_xfce_helpers
            apply_thunar_vscode_action
            apply_wallpaper
            configure_all_whiskers
            apply_mouse_flat
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
