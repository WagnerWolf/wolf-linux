#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

log(){ printf '[Wolf XFCE Fix 1.0.38] %s\n' "$*"; }

case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
    *XFCE*|*Xfce*) ;;
    *) log "Execute dentro da sessão XFCE X11."; exit 1 ;;
esac

log "Instalando dependências oficiais..."
sudo pacman -S --needed --noconfirm \
    materia-gtk-theme papirus-icon-theme breeze-cursors \
    ristretto xreader xarchiver xdotool xcape xdg-user-dirs-gtk gvfs \
    xorg-xinput xf86-input-libinput python-pillow

# X11-only persistente.
sudo install -d /usr/local/sbin /etc/pacman.d/hooks /etc/X11/xorg.conf.d /etc/xdg/autostart
sudo tee /usr/local/sbin/wolf-disable-xfce-wayland >/dev/null <<'EOF_X11'
#!/usr/bin/env bash
set -euo pipefail
rm -f /usr/share/wayland-sessions/xfce-wayland.desktop
EOF_X11
sudo chmod 755 /usr/local/sbin/wolf-disable-xfce-wayland
sudo tee /etc/pacman.d/hooks/wolf-xfce-x11-only.hook >/dev/null <<'EOF_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = xfce4-session

[Action]
Description = Wolf Linux: mantendo XFCE somente em X11...
When = PostTransaction
Exec = /usr/local/sbin/wolf-disable-xfce-wayland
EOF_HOOK
sudo /usr/local/sbin/wolf-disable-xfce-wayland

# Mouse flat persistente.
sudo tee /etc/X11/xorg.conf.d/50-wolf-mouse-no-accel.conf >/dev/null <<'EOF_XORG'
Section "InputClass"
    Identifier "Wolf Linux - Mouse sem aceleracao"
    MatchIsPointer "on"
    MatchIsTouchpad "off"
    MatchDriver "libinput"
    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
EndSection
EOF_XORG
sudo tee /usr/local/bin/wolf-disable-mouse-accel.sh >/dev/null <<'EOF_MOUSE'
#!/usr/bin/env bash
set -u
sleep 2
command -v xinput >/dev/null 2>&1 || exit 0
while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    props="$(xinput list-props "$id" 2>/dev/null || true)"
    grep -q 'libinput Tapping Enabled' <<<"$props" && continue
    line="$(grep -m1 'libinput Accel Profile Enabled (' <<<"$props" || true)"
    values="${line##*:}"; values="$(tr -d '[:space:]' <<<"$values")"
    case "$values" in
        *,*,*) xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 0 >/dev/null 2>&1 || true ;;
        *,*)   xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 >/dev/null 2>&1 || true ;;
    esac
    if grep -q 'libinput Accel Speed' <<<"$props"; then
        xinput set-prop "$id" 'libinput Accel Speed' 0 >/dev/null 2>&1 || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
EOF_MOUSE
sudo chmod 755 /usr/local/bin/wolf-disable-mouse-accel.sh

# Launchers fixos do painel Wolf.
sudo tee /usr/share/applications/wolf-xfce-browser.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=google-chrome-stable %U
Icon=google-chrome
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=Network;WebBrowser;
EOF
sudo tee /usr/share/applications/wolf-xfce-home.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Pasta pessoal
Exec=thunar
Icon=user-home
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=System;FileTools;FileManager;
EOF
sudo tee /usr/share/applications/wolf-xfce-terminal.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Terminal
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=System;TerminalEmulator;
EOF

# Helpers atualizados.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/setup" <<'EOF_SETUP'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.4"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/xfce"
MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v4.done"
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
        [[ "$type" == whiskermenu ]] && configure_whisker "$id"
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+$' || true)
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
EOF_SETUP
cat > "$tmp/mm" <<'EOF_MM'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.4"
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
    set_prop xfce4-panel "/panels/panel-$pid/wolf-layout-version" int 4

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

    # Reconstroi uma vez painéis Wolf antigos (v1-v3), removendo o systray
    # duplicado que o XFCE não permite em múltiplas instâncias.
    for pid in "${managed[@]}"; do
        ver="$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/wolf-layout-version" 2>/dev/null || echo 0)"
        if [[ "$ver" != 4 ]]; then
            out="$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/output-name" 2>/dev/null || true)"
            [[ -n "$out" ]] && create_secondary_layout "$pid" "$out"
        fi
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
EOF_MM
cat > "$tmp/whisker" <<'EOF_WHISKER'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

# Abre a instância do Whisker que pertence ao monitor onde está o ponteiro,
# mas deixa o próprio Whisker ancorar o popup ao botão do painel.
# Isso evita o visual de --pointer (menu solto no meio da tela).

command -v xfconf-query >/dev/null 2>&1 || exit 1
command -v xdotool >/dev/null 2>&1 || exec xfce4-popup-whiskermenu

mouse_x=0 mouse_y=0
while IFS='=' read -r key value; do
    case "$key" in
        X) mouse_x="$value" ;;
        Y) mouse_y="$value" ;;
    esac
done < <(xdotool getmouselocation --shell 2>/dev/null || true)

point_output=""
while IFS= read -r line; do
    [[ "$line" == *" connected "* ]] || continue
    out="${line%% *}"
    if [[ "$line" =~ ([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) ]]; then
        w="${BASH_REMATCH[1]}"; h="${BASH_REMATCH[2]}"
        x="${BASH_REMATCH[3]}"; y="${BASH_REMATCH[4]}"
        if (( mouse_x >= x && mouse_x < x+w && mouse_y >= y && mouse_y < y+h )); then
            point_output="$out"
            break
        fi
    fi
done < <(xrandr --query 2>/dev/null || true)

# Fallback para o monitor principal/primeiro ativo.
if [[ -z "$point_output" ]]; then
    point_output="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && /\*/ {print $NF; exit}')"
fi
if [[ -z "$point_output" ]]; then
    point_output="$(xrandr --query 2>/dev/null | awk '$2=="connected" {print $1; exit}')"
fi

panel_id=""
while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    out="$(xfconf-query -c xfce4-panel -p "/panels/panel-$p/output-name" 2>/dev/null || true)"
    if [[ "$out" == "$point_output" ]]; then
        panel_id="$p"
        break
    fi
done < <(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true)

# Se o painel principal estiver em modo Automatic, ainda podemos usá-lo quando
# o ponteiro está no output principal.
if [[ -z "$panel_id" ]]; then
    panel_id="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' | head -n1 || true)"
fi

whisker_id=""
if [[ -n "$panel_id" ]]; then
    while IFS= read -r id; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue
        type="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" 2>/dev/null || true)"
        if [[ "$type" == "whiskermenu" ]]; then
            whisker_id="$id"
            break
        fi
    done < <(xfconf-query -c xfce4-panel -p "/panels/panel-$panel_id/plugin-ids" 2>/dev/null || true)
fi

if [[ -n "$whisker_id" ]]; then
    # Whisker 2.8+ aceita --instance. Quando não aceita o ID numérico do plugin,
    # o remote event do painel continua sendo um fallback confiável.
    if xfce4-popup-whiskermenu --list 2>/dev/null | grep -Eq "(^|[^0-9])${whisker_id}([^0-9]|$)"; then
        exec xfce4-popup-whiskermenu --instance="$whisker_id"
    fi
    if xfce4-panel --plugin-event="whiskermenu-${whisker_id}:popup" >/dev/null 2>&1; then
        exit 0
    fi
fi

exec xfce4-popup-whiskermenu
EOF_WHISKER
cat > "$tmp/defaults" <<'EOF_DEFAULTS'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in *XFCE*|*Xfce*) ;; *) exit 0 ;; esac

set_default() {
    local desktop="$1"; shift
    [[ -r "/usr/share/applications/$desktop" ]] || return 0
    local mime
    for mime in "$@"; do
        [[ -n "$mime" ]] || continue
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
        if command -v gio >/dev/null 2>&1; then
            gio mime "$mime" "$desktop" >/dev/null 2>&1 || true
        fi
    done
}

set_from_desktop() {
    local desktop="$1" filter="${2:-}" prefix=""
    [[ -r "/usr/share/applications/$desktop" ]] || return 0

    if [[ -n "$filter" && "${filter: -2}" == '/*' ]]; then
        prefix="${filter::-1}"
    fi

    while IFS= read -r mime; do
        [[ -n "$mime" ]] || continue
        if [[ -n "$filter" ]]; then
            if [[ -n "$prefix" ]]; then
                [[ "$mime" == "$prefix"* ]] || continue
            else
                [[ "$mime" == "$filter" ]] || continue
            fi
        fi
        set_default "$desktop" "$mime"
    done < <(sed -n 's/^MimeType=//p' "/usr/share/applications/$desktop" | tr ';' '\n' | sed '/^$/d')
}

# Helpers nativos do XFCE.
mkdir -p "$HOME/.config/xfce4"
cat > "$HOME/.config/xfce4/helpers.rc" <<'HELPERS'
WebBrowser=custom-WebBrowser
FileManager=Thunar
TerminalEmulator=xfce4-terminal
HELPERS

mkdir -p "$HOME/.local/share/xfce4/helpers"
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

# Pastas.
set_default thunar.desktop inode/directory

# Web.
set_default google-chrome.desktop \
    text/html application/xhtml+xml \
    x-scheme-handler/http x-scheme-handler/https \
    x-scheme-handler/about x-scheme-handler/unknown

# Imagens: usa todos os MIME types anunciados pelo Ristretto.
set_from_desktop org.xfce.ristretto.desktop 'image/*'
set_default org.xfce.ristretto.desktop \
    image/jpeg image/png image/gif image/webp image/bmp image/tiff image/svg+xml image/avif image/heif image/heic

# PDFs/documentos de leitura.
set_from_desktop xreader.desktop
set_default xreader.desktop application/pdf application/postscript application/epub+zip application/x-cbr application/x-cbz

# Texto/código simples.
set_from_desktop org.xfce.mousepad.desktop 'text/*'
set_default org.xfce.mousepad.desktop application/json application/xml application/x-shellscript

# Vídeo e áudio.
set_from_desktop io.github.mpc_qt.mpc-qt.desktop 'video/*'
set_default io.github.mpc_qt.mpc-qt.desktop application/x-matroska
set_from_desktop audacious.desktop 'audio/*'
set_default audacious.desktop application/xspf+xml

# Compactados.
set_from_desktop xarchiver.desktop

# Torrents/magnet.
set_from_desktop transmission-qt.desktop
set_default transmission-qt.desktop application/x-bittorrent x-scheme-handler/magnet

# Escritório.
set_from_desktop libreoffice-writer.desktop
set_from_desktop libreoffice-calc.desktop
set_from_desktop libreoffice-impress.desktop

# Reforça navegador padrão também pela API do xdg-settings.
xdg-settings set default-web-browser google-chrome.desktop >/dev/null 2>&1 || true
EOF_DEFAULTS
sudo install -m 0755 "$tmp/setup" /usr/local/bin/wolf-xfce-desktop-setup
sudo install -m 0755 "$tmp/mm" /usr/local/bin/wolf-xfce-multimonitor
sudo install -m 0755 "$tmp/whisker" /usr/local/bin/wolf-xfce-whisker-current
sudo install -m 0755 "$tmp/defaults" /usr/local/bin/wolf-xfce-default-apps

# Autostarts.
sudo tee /etc/xdg/autostart/wolf-xfce-desktop-setup.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - XFCE Desktop Setup
Exec=sh -c 'sleep 5; /usr/local/bin/wolf-xfce-desktop-setup apply'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
sudo tee /etc/xdg/autostart/wolf-xfce-multimonitor.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - XFCE MultiMonitor
Exec=sh -c 'sleep 10; /usr/local/bin/wolf-xfce-multimonitor watch'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
sudo tee /etc/xdg/autostart/wolf-xfce-default-apps.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Aplicativos padrão XFCE
Exec=sh -c 'sleep 7; /usr/local/bin/wolf-xfce-default-apps'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
sudo tee /etc/xdg/autostart/wolf-xfce-mouse-flat.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Mouse sem aceleração
Exec=/usr/local/bin/wolf-disable-mouse-accel.sh
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

# Atalhos: Super sozinho vira combinação privada via xcape; Super+E continua Thunar.
setcmd() {
    local key="$1" cmd="$2"
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$key" -n -t string -s "$cmd" 2>/dev/null \
      || xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$key" -s "$cmd" 2>/dev/null || true
}
setcmd '<Primary><Alt>t' 'xfce4-terminal'
setcmd '<Super>e' 'thunar'
setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'
pkill -x xcape >/dev/null 2>&1 || true
xcape -e 'Super_L=Control_L|Alt_L|Shift_L|F12' >/dev/null 2>&1 &

# Remove markers antigos e reconstrói o layout uma única vez.
rm -f "$HOME/.config/wolf-linux/xfce-layout-v1.done" \
      "$HOME/.config/wolf-linux/xfce-layout-v2.done" \
      "$HOME/.config/wolf-linux/xfce-layout-v3.done" \
      "$HOME/.config/wolf-linux/xfce-layout-v4.done" 2>/dev/null || true

pkill -f '/usr/local/bin/wolf-xfce-multimonitor watch' >/dev/null 2>&1 || true
/usr/local/bin/wolf-xfce-desktop-setup force
/usr/local/bin/wolf-xfce-default-apps
/usr/local/bin/wolf-xfce-multimonitor apply
/usr/local/bin/wolf-disable-mouse-accel.sh || true
nohup /usr/local/bin/wolf-xfce-multimonitor watch >/dev/null 2>&1 &

# Recarrega Thunar para a UCA aparecer imediatamente.
thunar -q >/dev/null 2>&1 || true

log "Estado final:"
/usr/local/bin/wolf-xfce-desktop-setup status || true
/usr/local/bin/wolf-xfce-multimonitor status || true

echo
echo '[OK] XFCE 1.0.38 aplicado.'
echo 'Principal: Whisker | Chrome | Pasta pessoal | Terminal | apps locais | tray | relógio | mostrar desktop.'
echo 'Secundários: Whisker | Chrome | Pasta pessoal | Terminal | apps locais | relógio.'
echo 'Super abre o Whisker do monitor do ponteiro, ancorado ao botão do painel.'
echo 'Faça logout/login uma vez para validar tema e mouse desde o início da sessão.'
