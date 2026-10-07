#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

log(){ printf '[Wolf XFCE Fix 1.0.44] %s\n' "$*"; }

case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
    *XFCE*|*Xfce*) ;;
    *) log "Execute dentro da sessão XFCE X11."; exit 1 ;;
esac

log "Instalando dependências oficiais..."
sudo pacman -S --needed --noconfirm \
    materia-gtk-theme papirus-icon-theme breeze-cursors \
    ristretto xreader xarchiver xdotool xcape xdg-user-dirs-gtk gvfs \
    xfce4-pulseaudio-plugin xorg-xrandr xorg-xev xorg-xprop wmctrl xorg-xinput xf86-input-libinput python-pillow \
    noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-meslo-nerd ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono

install_alttab() {
    command -v alttab >/dev/null 2>&1 && return 0

    log "Instalando alttab para Alt+Tab por monitor..."
    if pacman -Si alttab >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm alttab && return 0
    fi

    if command -v yay >/dev/null 2>&1; then
        yay -S --needed --noconfirm alttab && return 0
    fi

    log "[AVISO] alttab não pôde ser instalado automaticamente; o restante do XFCE será corrigido normalmente."
    return 1
}
install_alttab || true

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
Exec=/usr/local/bin/wolf-xfce-launch-here browser %U
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
Exec=/usr/local/bin/wolf-xfce-launch-here home
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
Exec=/usr/local/bin/wolf-xfce-launch-here terminal
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

VERSION="0.7"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/xfce"
LAYOUT_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v7.done"
APPEARANCE_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-appearance-v1.done"
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

    # Controle de volume nativo do painel. Ele usa libpulse, portanto funciona
    # normalmente sobre pipewire-pulse; não significa voltar a PulseAudio.
    set_prop xfce4-panel /plugins/plugin-8 string pulseaudio

    set_prop xfce4-panel /plugins/plugin-9 string clock
    set_prop xfce4-panel /plugins/plugin-10 string showdesktop
}

ensure_panel_css() {
    # O xfce4-pulseaudio-plugin tende a usar um ícone maior que systray/clock
    # em painéis de 36 px. Ajuste só a imagem do botão, sem afetar o popup.
    local css="$HOME/.config/gtk-3.0/gtk.css"
    mkdir -p "$(dirname "$css")"
    python3 - "$css" <<'PYCSS'
from pathlib import Path
import sys
p = Path(sys.argv[1])
start = "/* WOLF-XFCE-PULSEAUDIO-BEGIN */"
end = "/* WOLF-XFCE-PULSEAUDIO-END */"
block = """/* WOLF-XFCE-PULSEAUDIO-BEGIN */
#pulseaudio-button > box > image {
  -gtk-icon-transform: scale(0.62);
}
#pulseaudio-button {
  padding: 3px;
}
/* WOLF-XFCE-PULSEAUDIO-END */
"""
text = p.read_text(encoding="utf-8") if p.exists() else ""
if start in text and end in text:
    before = text.split(start, 1)[0].rstrip()
    after = text.split(end, 1)[1].lstrip("\n")
    text = (before + "\n\n" if before else "") + block + ("\n" + after if after else "")
else:
    text = text.rstrip()
    text = (text + "\n\n" if text else "") + block
p.write_text(text, encoding="utf-8")
PYCSS
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

apply_first_login_appearance() {
    if [[ -f "$APPEARANCE_MARKER" ]]; then
        log "Aparência inicial já aplicada; preservando tema, wallpaper e preferências do usuário."
        return 0
    fi

    apply_style
    apply_terminal_style
    apply_wallpaper

    mkdir -p "$(dirname "$APPEARANCE_MARKER")"
    touch "$APPEARANCE_MARKER"
    log "Aparência inicial aplicada uma única vez."
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
    ensure_panel_css
    apply_first_login_appearance
    apply_user_dirs
    apply_xfce_helpers
    apply_thunar_vscode_action
    configure_all_whiskers
    apply_mouse_flat

    nohup xfce4-panel >/dev/null 2>&1 &
    sleep 2
    PANEL_RESTART_PENDING=0

    mkdir -p "$(dirname "$LAYOUT_MARKER")"
    touch "$LAYOUT_MARKER"
    log "Painel principal Wolf Linux aplicado em $out."
}

status() {
    printf 'Wolf XFCE Desktop Setup v%s\n' "$VERSION"
    local marker_state="pendente" appearance_state="pendente"
    [[ -f "$LAYOUT_MARKER" ]] && marker_state="aplicado"
    [[ -f "$APPEARANCE_MARKER" ]] && appearance_state="aplicada/preservada"
    printf 'Layout inicial: %s\n' "$marker_state"
    printf 'Aparência inicial: %s\n' "$appearance_state"
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
        if (( FORCE == 0 )); then
            if [[ -f "$LAYOUT_MARKER" ]] || compgen -G "${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v*.done" >/dev/null; then
                # Layout e aparência são política de PRIMEIRO LOGIN. Revisões
                # futuras não reconstroem o painel de um usuário já configurado.
                exit 0
            fi
        fi
        apply_layout
        ;;
    force|--force)
        FORCE=1
        apply_layout
        ;;
    css|ensure-css)
        ensure_panel_css
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
EOF_MM
cat > "$tmp/whisker" <<'EOF_WHISKER'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

# Abre a instância do Whisker pertencente ao monitor onde está o ponteiro,
# sempre ancorada ao BOTÃO do painel. O bool:false é importante: versões
# recentes do Whisker aceitam o parâmetro "popup" com um booleano que define
# se o menu deve nascer no ponteiro (true) ou junto ao applet (false).

command -v xfconf-query >/dev/null 2>&1 || exit 1
command -v xrandr >/dev/null 2>&1 || exit 1
command -v xfce4-panel >/dev/null 2>&1 || exit 1

mouse_x=0
mouse_y=0
if command -v xdotool >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
        case "$key" in
            X) mouse_x="$value" ;;
            Y) mouse_y="$value" ;;
        esac
    done < <(xdotool getmouselocation --shell 2>/dev/null || true)
fi

# Uma única consulta ao RandR por acionamento da tecla.
randr_query="$(xrandr --query 2>/dev/null || true)"
randr_monitors="$(xrandr --listmonitors 2>/dev/null || true)"

point_output=""
while IFS= read -r line; do
    [[ "$line" == *" connected "* ]] || continue
    out="${line%% *}"
    if [[ "$line" =~ ([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) ]]; then
        w="${BASH_REMATCH[1]}"
        h="${BASH_REMATCH[2]}"
        x="${BASH_REMATCH[3]}"
        y="${BASH_REMATCH[4]}"
        if (( mouse_x >= x && mouse_x < x+w && mouse_y >= y && mouse_y < y+h )); then
            point_output="$out"
            break
        fi
    fi
done <<< "$randr_query"

primary_output="$(awk 'NR>1 && /\*/ {print $NF; exit}' <<< "$randr_monitors")"
[[ -n "$primary_output" ]] || primary_output="$(awk '$2=="connected" {print $1; exit}' <<< "$randr_query")"
[[ -n "$point_output" ]] || point_output="$primary_output"

panel_id=""
first_panel=""
while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    [[ -n "$first_panel" ]] || first_panel="$p"
    out="$(xfconf-query -c xfce4-panel -p "/panels/panel-$p/output-name" 2>/dev/null || true)"
    if [[ "$out" == "$point_output" ]]; then
        panel_id="$p"
        break
    fi
    if [[ "$point_output" == "$primary_output" && "$out" == "Automatic" ]]; then
        panel_id="$p"
    fi
done < <(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true)

monitor_count="$(awk 'NR>1 {n++} END {print n+0}' <<< "$randr_monitors")"
if [[ -z "$panel_id" && "$monitor_count" -le 1 ]]; then
    panel_id="$first_panel"
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
    # O booleano false força popup junto ao applet, e não sob o ponteiro.
    if xfce4-panel --plugin-event="whiskermenu-${whisker_id}:popup:bool:false" >/dev/null 2>&1; then
        exit 0
    fi

    # Fallback apenas para builds antigos. Nunca use --pointer.
    if command -v xfce4-popup-whiskermenu >/dev/null 2>&1 \
       && xfce4-popup-whiskermenu --instance="$whisker_id" >/dev/null 2>&1; then
        exit 0
    fi
fi

if (( monitor_count <= 1 )) && command -v xfce4-popup-whiskermenu >/dev/null 2>&1; then
    exec xfce4-popup-whiskermenu
fi

printf '[Wolf XFCE Whisker] Não encontrei uma instância do Whisker no monitor %s.\n' \
    "${point_output:-desconhecido}" >&2
exit 1
EOF_WHISKER
cat > "$tmp/placement" <<'EOF_PLACEMENT'
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
                    # O contexto do Whisker vale somente para a primeira nova
                    # janela. Evite capturar abas destacadas/diálogos depois.
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
EOF_PLACEMENT
cat > "$tmp/launch" <<'EOF_LAUNCH'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

profile="${1:-}"
[[ -n "$profile" ]] || { echo "Uso: $0 {browser|home|terminal|command} [args...]" >&2; exit 2; }
shift || true

arm() {
    local expected="$1"
    if [[ -x /usr/local/bin/wolf-xfce-whisker-placement ]]; then
        /usr/local/bin/wolf-xfce-whisker-placement arm "$expected" >/dev/null 2>&1 || true
    fi
}

case "$profile" in
    browser)
        arm 'google-chrome|Google-chrome|chrome'
        exec /usr/bin/google-chrome-stable "$@"
        ;;
    home)
        arm 'Thunar|thunar'
        exec /usr/bin/thunar "$@"
        ;;
    terminal)
        arm 'xfce4-terminal|Xfce4-terminal'
        exec /usr/bin/xfce4-terminal "$@"
        ;;
    command)
        expected="${1:-}"
        [[ -n "$expected" ]] || { echo "Uso: $0 command <regex-classe> <comando> [args...]" >&2; exit 2; }
        shift
        (($# > 0)) || { echo "Comando ausente." >&2; exit 2; }
        arm "$expected"
        exec "$@"
        ;;
    *)
        echo "Perfil desconhecido: $profile" >&2
        exit 2
        ;;
esac
EOF_LAUNCH
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

# LibreOffice anuncia text/plain entre os MIME types possíveis. Como o bloco
# de escritório roda depois do Mousepad, reafirme explicitamente o editor de
# texto simples por último para que .txt nunca caia no Writer.
set_default org.xfce.mousepad.desktop text/plain

# Reforça navegador padrão também pela API do xdg-settings.
xdg-settings set default-web-browser google-chrome.desktop >/dev/null 2>&1 || true
EOF_DEFAULTS
cat > "$tmp/alttab" <<'EOF_ALTTAB'
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
EOF_ALTTAB
cat > "$tmp/super" <<'EOF_SUPER'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in *XFCE*|*Xfce*) ;; *) exit 0 ;; esac

command -v xfconf-query >/dev/null 2>&1 || exit 0
command -v xcape >/dev/null 2>&1 || exit 0

setcmd() {
    local key="$1" cmd="$2"
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "/commands/custom/$key" -n -t string -s "$cmd" 2>/dev/null \
        || xfconf-query -c xfce4-keyboard-shortcuts \
            -p "/commands/custom/$key" -s "$cmd" 2>/dev/null || true
}

# Remova somente bindings legados que disputariam com o toque isolado de Super.
# A combinação privada também é limpa explicitamente para eliminar um valor
# antigo que usava --pointer antes de gravar o helper.
while IFS= read -r prop; do
    [[ "$prop" == /commands/custom/* ]] || continue
    value="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)"
    if [[ "$prop" == '/commands/custom/<Primary><Alt><Shift>F12' ]]; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
        continue
    fi
    if [[ "$prop" == *Super* && "$value" == *xfce4-popup-whiskermenu* ]]; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
    fi
done < <(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null || true)

setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'

pkill -x xcape >/dev/null 2>&1 || true
exec xcape -e 'Super_L=Control_L|Alt_L|Shift_L|F12'
EOF_SUPER

sudo install -m 0755 "$tmp/setup" /usr/local/bin/wolf-xfce-desktop-setup
sudo install -m 0755 "$tmp/mm" /usr/local/bin/wolf-xfce-multimonitor
sudo install -m 0755 "$tmp/whisker" /usr/local/bin/wolf-xfce-whisker-current
sudo install -m 0755 "$tmp/placement" /usr/local/bin/wolf-xfce-whisker-placement
sudo install -m 0755 "$tmp/launch" /usr/local/bin/wolf-xfce-launch-here
sudo install -m 0755 "$tmp/defaults" /usr/local/bin/wolf-xfce-default-apps
sudo install -m 0755 "$tmp/alttab" /usr/local/bin/wolf-xfce-alttab
sudo install -m 0755 "$tmp/super" /usr/local/bin/wolf-xfce-super-setup

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
Exec=sh -c 'sleep 8; /usr/local/bin/wolf-xfce-multimonitor watch'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
sudo tee /etc/xdg/autostart/wolf-xfce-alttab.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Alt+Tab por monitor
Exec=sh -c 'sleep 6; /usr/local/bin/wolf-xfce-alttab start'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
sudo tee /etc/xdg/autostart/wolf-xfce-whisker-placement.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Posicionamento de janelas por contexto
Exec=sh -c 'sleep 6; /usr/local/bin/wolf-xfce-whisker-placement start'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
sudo tee /etc/xdg/autostart/wolf-xfce-super-key.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Super abre Whisker por monitor
Exec=sh -c 'sleep 4; exec /usr/local/bin/wolf-xfce-super-setup'
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
setcmd '<Primary><Alt>t' '/usr/local/bin/wolf-xfce-launch-here terminal'
setcmd '<Super>e' '/usr/local/bin/wolf-xfce-launch-here home'

# Remova atalhos antigos que abriam xfce4-popup-whiskermenu diretamente ao
# pressionar Super. Se um deles sobreviver, ele disputa com o xcape e pode
# abrir o menu no ponteiro antes do helper por monitor.
while IFS= read -r prop; do
    [[ "$prop" == /commands/custom/* ]] || continue
    [[ "$prop" == *Super* ]] || continue
    value="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)"
    if [[ "$value" == *xfce4-popup-whiskermenu* ]]; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
    fi
done < <(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null || true)

setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'
pkill -x xcape >/dev/null 2>&1 || true
nohup /usr/local/bin/wolf-xfce-super-setup >/dev/null 2>&1 &

# Migração 1.0.43: PRESERVE o painel existente. Se qualquer layout Wolf já
# foi aplicado, marque a revisão atual sem reconstruir plugins/propriedades.
mkdir -p "$HOME/.config/wolf-linux"
if compgen -G "$HOME/.config/wolf-linux/xfce-layout-v*.done" >/dev/null; then
    touch "$HOME/.config/wolf-linux/xfce-appearance-v1.done"
    touch "$HOME/.config/wolf-linux/xfce-layout-v7.done"
fi

# Atualiza as cópias dos launchers que o XFCE guarda dentro do perfil sem
# alterar a ordem dos itens nem qualquer preferência do painel.
for desktop in wolf-xfce-browser.desktop wolf-xfce-home.desktop wolf-xfce-terminal.desktop; do
    while IFS= read -r copy; do
        [[ -n "$copy" ]] || continue
        cp -f "/usr/share/applications/$desktop" "$copy"
    done < <(find "$HOME/.config/xfce4/panel" -type f -name "$desktop" 2>/dev/null || true)
done

# Encerra somente os watchers antigos. A partir desta revisão ambos são
# orientados a eventos e permanecem bloqueados em xev/xprop até algo acontecer.
pkill -f '/usr/local/bin/wolf-xfce-multimonitor watch' >/dev/null 2>&1 || true
/usr/local/bin/wolf-xfce-whisker-placement stop >/dev/null 2>&1 || true

# Atualize apenas o CSS; NÃO force wolf-xfce-desktop-setup, pois isso apagaria
# customizações que agora pertencem ao usuário.
/usr/local/bin/wolf-xfce-desktop-setup ensure-css
/usr/local/bin/wolf-xfce-default-apps
/usr/local/bin/wolf-xfce-multimonitor apply
/usr/local/bin/wolf-disable-mouse-accel.sh || true

# Uma única reinicialização explícita nesta migração é necessária para o GTK
# reler o seletor corrigido do ícone de volume. Não existe mais restart no boot.
xfce4-panel -r >/dev/null 2>&1 || true
sleep 1

/usr/local/bin/wolf-xfce-alttab restart || log "[AVISO] Alt+Tab por monitor ainda não pôde ser ativado."
/usr/local/bin/wolf-xfce-whisker-placement restart || log "[AVISO] Posicionamento contextual não pôde ser ativado."
nohup /usr/local/bin/wolf-xfce-multimonitor watch >/dev/null 2>&1 &

# Recarrega Thunar para a UCA aparecer imediatamente.
thunar -q >/dev/null 2>&1 || true

log "Estado final:"
/usr/local/bin/wolf-xfce-desktop-setup status || true
/usr/local/bin/wolf-xfce-multimonitor status || true
/usr/local/bin/wolf-xfce-whisker-placement status || true

echo
echo '[OK] XFCE 1.0.43 aplicado.'
echo 'Painéis existentes foram preservados; o MultiMonitor só cria/reassocia painéis quando a topologia realmente muda.'
echo 'Super abre o Whisker do monitor do ponteiro com popup:bool:false, ancorado ao botão.'
echo 'Alt+Tab continua limitado ao monitor do ponteiro.'
echo 'Whisker e launchers Wolf usam posicionamento por eventos; não existe polling contínuo do mouse.'
echo 'Chrome/Terminal/Home dos painéis registram o monitor de origem antes do lançamento.'
echo 'Tema e wallpaper continuam sendo política de primeiro login.'
