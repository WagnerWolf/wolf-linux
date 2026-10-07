#!/usr/bin/env bash
set -Eeuo pipefail

WORKDIR="/tmp/wolf-theme-lab-v031"
SOURCE_URL="https://github.com/i-mint/sunrise/archive/refs/heads/master.tar.gz"

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute este script dentro da sessão MATE."
    exit 1
fi

declare -A THEME_NAME
declare -A LABEL
declare -A BG
declare -A SURFACE
declare -A SURFACE_ALT
declare -A BORDER
declare -A FG
declare -A MUTED
declare -A ACCENT
declare -A ACCENT_HI
declare -A ACCENT_DARK

THEME_NAME[1]="Wolf-Lunar"
LABEL[1]="Prata Lunar"
BG[1]="#151519"
SURFACE[1]="#1d1d22"
SURFACE_ALT[1]="#292930"
BORDER[1]="#454650"
FG[1]="#f0f0f3"
MUTED[1]="#b5b6bd"
ACCENT[1]="#6d707b"
ACCENT_HI[1]="#8a8d98"
ACCENT_DARK[1]="#555862"

THEME_NAME[2]="Wolf-Steel"
LABEL[2]="Aço Lunar"
BG[2]="#14171b"
SURFACE[2]="#1d2228"
SURFACE_ALT[2]="#29313a"
BORDER[2]="#46515d"
FG[2]="#eef1f4"
MUTED[2]="#adb5bd"
ACCENT[2]="#5e6c7a"
ACCENT_HI[2]="#748596"
ACCENT_DARK[2]="#485562"

THEME_NAME[3]="Wolf-Graphite"
LABEL[3]="Grafite"
BG[3]="#161618"
SURFACE[3]="#202023"
SURFACE_ALT[3]="#2b2b2f"
BORDER[3]="#444449"
FG[3]="#ededf0"
MUTED[3]="#b0b0b5"
ACCENT[3]="#595b63"
ACCENT_HI[3]="#72747d"
ACCENT_DARK[3]="#45474e"

THEME_NAME[4]="Wolf-Gunmetal"
LABEL[4]="Gunmetal"
BG[4]="#111317"
SURFACE[4]="#1b1e23"
SURFACE_ALT[4]="#282c33"
BORDER[4]="#4b5059"
FG[4]="#f3f3f5"
MUTED[4]="#b7bac0"
ACCENT[4]="#646a74"
ACCENT_HI[4]="#828995"
ACCENT_DARK[4]="#4c515a"

THEME_NAME[5]="Wolf-Obsidian"
LABEL[5]="Obsidiana"
BG[5]="#101012"
SURFACE[5]="#19191c"
SURFACE_ALT[5]="#242428"
BORDER[5]="#3c3c42"
FG[5]="#eeeeF1"
MUTED[5]="#aaaab0"
ACCENT[5]="#4f5058"
ACCENT_HI[5]="#686a73"
ACCENT_DARK[5]="#3e3f46"

print_menu() {
    echo
    echo "============================================================"
    echo "          WOLF LINUX - THEME LAB 2.0 (v0.31)"
    echo "============================================================"
    echo
    echo "Cada opção usa um NOME DE TEMA DIFERENTE."
    echo "Isso força GTK e Marco a recarregarem tudo sem cache do tema anterior."
    echo

    for i in 1 2 3 4 5; do
        printf "  %s) %-14s  %-15s accent=%s\n" \
            "$i" "${LABEL[$i]}" "${THEME_NAME[$i]}" "${ACCENT[$i]}"
    done

    echo
    echo "  c) Forçar notificações Coco"
    echo "  n) Ativar NumLock na sessão atual"
    echo "  q) Sair"
    echo
}

ensure_dependencies() {
    local -a missing=()

    command -v curl >/dev/null 2>&1 || missing+=(curl)
    command -v python >/dev/null 2>&1 || missing+=(python)

    python - <<'PY' >/dev/null 2>&1 || missing+=(python-pillow)
from PIL import Image
PY

    if ((${#missing[@]} > 0)); then
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    fi
}

download_source_once() {
    if [[ -n "${SOURCE_THEME:-}" && -d "${SOURCE_THEME:-}" ]]; then
        return 0
    fi

    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR/extracted"

    echo "[INFO] Baixando Sunrise-Dark limpo..."

    curl \
        -fL \
        --retry 3 \
        --connect-timeout 15 \
        "$SOURCE_URL" \
        -o "$WORKDIR/sunrise.tar.gz"

    tar -xzf "$WORKDIR/sunrise.tar.gz" -C "$WORKDIR/extracted"

    SOURCE_THEME="$(
        find "$WORKDIR/extracted" \
            -mindepth 2 \
            -maxdepth 2 \
            -type d \
            -name Sunrise-Dark \
            -print \
            -quit
    )"

    [[ -n "$SOURCE_THEME" && -d "$SOURCE_THEME" ]] || {
        echo "[ERRO] Sunrise-Dark não encontrado."
        exit 1
    }
}

force_coco() {
    if ! gsettings list-schemas | grep -Fxq 'org.mate.NotificationDaemon'; then
        echo "[ERRO] Schema org.mate.NotificationDaemon não encontrado."
        return 1
    fi

    local now=""
    local attempt

    for attempt in 1 2 3 4 5; do
        echo "Tentativa Coco $attempt/5..." >/dev/null
        gsettings set org.mate.NotificationDaemon theme 'coco'
        now="$(gsettings get org.mate.NotificationDaemon theme 2>/dev/null || true)"

        if [[ "$now" == "'coco'" ]]; then
            pkill -x mate-notification-daemon 2>/dev/null || true
            sleep 1
            echo "[OK] Notificações: coco"
            return 0
        fi

        sleep 1
    done

    echo "[ERRO] O valor não permaneceu em coco. Atual: $now"
    return 1
}

force_numlock() {
    if gsettings list-schemas | grep -Fxq 'org.mate.peripherals-keyboard'; then
        gsettings set org.mate.peripherals-keyboard remember-numlock-state false 2>/dev/null || true
        gsettings set org.mate.peripherals-keyboard numlock-state 'on' 2>/dev/null || true
    fi

    command -v numlockx >/dev/null 2>&1 && numlockx on || true
    echo "[OK] NumLock solicitado para a sessão atual."
}

install_variant() {
    local id="$1"
    local theme="${THEME_NAME[$id]}"
    local target="/usr/share/themes/$theme"

    download_source_once

    echo "[INFO] Reconstruindo $theme a partir de Sunrise-Dark limpo..."

    sudo rm -rf "$target"
    sudo cp -a "$SOURCE_THEME" "$target"

    local source_root
    source_root="$(dirname "$SOURCE_THEME")"

    if [[ -f "$source_root/COPYING" ]]; then
        sudo cp -f "$source_root/COPYING" "$target/COPYING"
    fi
}

recolor_variant() {
    local id="$1"
    local theme="${THEME_NAME[$id]}"
    local target="/usr/share/themes/$theme"

    local bg="${BG[$id]}"
    local surface="${SURFACE[$id]}"
    local surface_alt="${SURFACE_ALT[$id]}"
    local border="${BORDER[$id]}"
    local fg="${FG[$id]}"
    local muted="${MUTED[$id]}"
    local accent="${ACCENT[$id]}"
    local accent_hi="${ACCENT_HI[$id]}"
    local accent_dark="${ACCENT_DARK[$id]}"

    sudo env \
        WOLF_THEME="$theme" \
        WOLF_BG="$bg" \
        WOLF_SURFACE="$surface" \
        WOLF_SURFACE_ALT="$surface_alt" \
        WOLF_BORDER="$border" \
        WOLF_FG="$fg" \
        WOLF_MUTED="$muted" \
        WOLF_ACCENT="$accent" \
        WOLF_ACCENT_HI="$accent_hi" \
        WOLF_ACCENT_DARK="$accent_dark" \
        python - <<'PY'
from pathlib import Path
from PIL import Image
import colorsys
import os
import re

theme = os.environ["WOLF_THEME"]
root = Path("/usr/share/themes") / theme

bg = os.environ["WOLF_BG"]
surface = os.environ["WOLF_SURFACE"]
surface_alt = os.environ["WOLF_SURFACE_ALT"]
border = os.environ["WOLF_BORDER"]
fg = os.environ["WOLF_FG"]
muted = os.environ["WOLF_MUTED"]
accent = os.environ["WOLF_ACCENT"]
accent_hi = os.environ["WOLF_ACCENT_HI"]
accent_dark = os.environ["WOLF_ACCENT_DARK"]

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

ACCENT = rgb(accent)
ACCENT_HI = rgb(accent_hi)
ACCENT_DARK = rgb(accent_dark)

# As capturas mostraram restos quentes em torno de:
#   rgb(235,84,6), rgb(197,94,54)
#   rgb(96,76,73), rgb(90,68,63)
#   rgb(56,32,7), rgb(41,17,9)
# O filtro abaixo cobre inclusive marrons muito dessaturados.

def neutral_for(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)

    # Vermelho puro fica fora; pegamos vermelho-amarronzado -> amarelo.
    warm = (
        (0.010 <= h <= 0.195 and s >= 0.055 and v >= 0.08)
        or (r > g * 1.10 and g >= b * 0.90 and r-b >= 10)
    )

    if not warm:
        return None

    lum = (0.2126*r + 0.7152*g + 0.0722*b) / 255

    if lum >= 0.66:
        return ACCENT_HI
    if lum >= 0.34:
        return ACCENT
    return ACCENT_DARK

# --------------------------------------------------------------
# Text formats: #RRGGBB, #RGB, rgb(...), rgba(...)
# --------------------------------------------------------------
hex6 = re.compile(r"#[0-9a-fA-F]{6}\b")
hex3 = re.compile(r"#[0-9a-fA-F]{3}\b")
rgbfn = re.compile(
    r"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(\s*,\s*[^)]+)?\)"
)

def replace_hex6(m):
    token = m.group(0)
    r = int(token[1:3],16)
    g = int(token[3:5],16)
    b = int(token[5:7],16)
    out = neutral_for(r,g,b)
    return token if out is None else "#%02x%02x%02x" % out

def replace_hex3(m):
    token = m.group(0)
    r = int(token[1]*2,16)
    g = int(token[2]*2,16)
    b = int(token[3]*2,16)
    out = neutral_for(r,g,b)
    return token if out is None else "#%02x%02x%02x" % out

def replace_rgbfn(m):
    r,g,b = (min(255,int(m.group(i))) for i in (1,2,3))
    out = neutral_for(r,g,b)

    if out is None:
        return m.group(0)

    alpha = m.group(4) or ""
    if alpha:
        return f"rgba({out[0]}, {out[1]}, {out[2]}{alpha})"
    return f"rgb({out[0]}, {out[1]}, {out[2]})"

changed_text = 0

for path in root.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in {
        ".css", ".xml", ".rc", ".svg", ".xpm", ".theme"
    }:
        continue

    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue

    updated = hex6.sub(replace_hex6, original)
    updated = hex3.sub(replace_hex3, updated)
    updated = rgbfn.sub(replace_rgbfn, updated)
    updated = re.sub(r"\bdarkorange\b", accent_dark, updated, flags=re.I)
    updated = re.sub(r"\borange\b", accent, updated, flags=re.I)

    if updated != original:
        path.write_text(updated, encoding="utf-8")
        changed_text += 1

# --------------------------------------------------------------
# PNG assets
# --------------------------------------------------------------
changed_images = 0

for path in root.rglob("*.png"):
    try:
        im = Image.open(path).convert("RGBA")
    except Exception:
        continue

    pixels = []
    changed = False

    for r,g,b,a in im.getdata():
        out = neutral_for(r,g,b)

        if a and out is not None:
            pixels.append((out[0], out[1], out[2], a))
            changed = True
        else:
            pixels.append((r,g,b,a))

    if changed:
        im.putdata(pixels)
        im.save(path)
        changed_images += 1

# --------------------------------------------------------------
# Explicit symbolic palette.
# The previous lab did not cover link/backdrop/titlebar names
# comprehensively enough.
# --------------------------------------------------------------
defs = f"""
@define-color bg_color {bg};
@define-color fg_color {fg};
@define-color base_color {bg};
@define-color text_color {fg};

@define-color selected_bg_color {accent};
@define-color selected_fg_color #ffffff;
@define-color theme_selected_bg_color {accent};
@define-color theme_selected_fg_color #ffffff;

@define-color link_color {accent_hi};
@define-color visited_link_color {muted};
@define-color theme_link_color {accent_hi};
@define-color theme_visited_link_color {muted};

@define-color titlebar_bg_color {surface};
@define-color titlebar_fg_color {fg};

@define-color menu_bg_color {surface};
@define-color menu_fg_color {fg};
@define-color menubar_bg_color {surface};
@define-color menubar_fg_color {fg};
@define-color toolbar_bg_color {surface};
@define-color toolbar_fg_color {fg};
@define-color panel_bg_color {surface};
@define-color panel_fg_color {fg};

@define-color backdrop_bg_color {surface_alt};
@define-color backdrop_fg_color {muted};
@define-color backdrop_base_color {surface_alt};
@define-color backdrop_text_color {muted};
@define-color backdrop_selected_bg_color {accent_dark};
@define-color backdrop_selected_fg_color #ffffff;

@define-color theme_unfocused_bg_color {surface_alt};
@define-color theme_unfocused_fg_color {muted};
@define-color theme_unfocused_base_color {surface_alt};
@define-color theme_unfocused_text_color {muted};
@define-color theme_unfocused_selected_bg_color {accent_dark};
@define-color theme_unfocused_selected_fg_color #ffffff;

@define-color borders {border};
@define-color unfocused_borders {border};
"""

override = defs + f"""

/* ===== Wolf Linux hard neutralization ===== */

window,
dialog,
.background {{
    background-color: {bg};
    color: {fg};
}}

headerbar,
.titlebar,
.toolbar,
.primary-toolbar {{
    background-image: none;
    background-color: {surface};
    color: {fg};
    border-color: {border};
    box-shadow: none;
}}

headerbar:backdrop,
.titlebar:backdrop,
window:backdrop,
dialog:backdrop {{
    background-image: none;
    background-color: {surface_alt};
    color: {muted};
    border-color: {border};
}}

button,
.titlebutton,
.linked > button,
.toolbar button,
headerbar button {{
    background-image: none;
    background-color: {surface_alt};
    color: {fg};
    border-color: {border};
    box-shadow: none;
}}

button:hover,
headerbar button:hover {{
    background-image: none;
    background-color: {accent_dark};
    color: #ffffff;
    border-color: {accent_hi};
}}

button:checked,
button:active,
button.suggested-action {{
    background-image: none;
    background-color: {accent};
    color: #ffffff;
    border-color: {accent_hi};
}}

*:link,
link,
label:link {{
    color: {accent_hi};
}}

*:visited,
label:visited {{
    color: {muted};
}}

selection,
*:selected,
.view:selected,
view:selected,
treeview.view:selected,
iconview:selected,
flowboxchild:selected,
row:selected,
placessidebar row:selected {{
    background-image: none;
    background-color: {accent};
    color: #ffffff;
}}

*:backdrop:selected,
.view:backdrop:selected,
treeview.view:backdrop:selected,
iconview:backdrop:selected,
row:backdrop:selected {{
    background-image: none;
    background-color: {accent_dark};
    color: #ffffff;
}}

entry,
textview text,
treeview.view,
iconview,
view {{
    background-color: {bg};
    color: {fg};
    border-color: {border};
}}

notebook > header,
notebook > stack,
stack,
sidebar,
placessidebar {{
    background-color: {surface};
    color: {fg};
}}

notebook > header > tabs > tab {{
    background-image: none;
    background-color: {surface_alt};
    color: {muted};
    border-color: {border};
}}

notebook > header > tabs > tab:checked {{
    background-image: none;
    background-color: {accent};
    color: #ffffff;
    border-color: {accent_hi};
}}

menu,
.menu,
popover,
.context-menu {{
    background-image: none;
    background-color: {surface};
    color: {fg};
    border-color: {border};
}}
"""

for css in [
    root / "gtk-3.0" / "gtk.css",
    root / "gtk-3.20" / "gtk.css",
]:
    if css.exists():
        with css.open("a", encoding="utf-8") as f:
            f.write(override)

# GTK2: full legacy named scheme, including titlebar/link/menu names.
gtk2 = root / "gtk-2.0" / "gtkrc"

if gtk2.exists():
    scheme = {
        "bg_color": bg,
        "fg_color": fg,
        "base_color": bg,
        "text_color": fg,
        "selected_bg_color": accent,
        "selected_fg_color": "#ffffff",
        "tooltip_bg_color": surface,
        "tooltip_fg_color": fg,
        "titlebar_bg_color": surface,
        "titlebar_fg_color": fg,
        "menubar_bg_color": surface,
        "menubar_fg_color": fg,
        "toolbar_bg_color": surface,
        "toolbar_fg_color": fg,
        "menu_bg_color": surface,
        "menu_fg_color": fg,
        "panel_bg_color": surface,
        "panel_fg_color": fg,
        "link_color": accent_hi,
    }

    payload = "\\n".join(f"{k}:{v}" for k,v in scheme.items())

    with gtk2.open("a", encoding="utf-8") as f:
        f.write(
            "\n# Wolf Linux hard legacy palette\n"
            f'gtk-color-scheme = "{payload}"\n'
        )

# Metatheme
(root / "index.theme").write_text(
f"""[Desktop Entry]
Type=X-GNOME-Metatheme
Name={theme}
Comment=Wolf Linux theme test variant
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme={theme}
MetacityTheme={theme}
IconTheme=Papirus-Dark
CursorTheme=breeze-dark
NotificationTheme=coco
ButtonLayout=menu:minimize,maximize,close
""",
encoding="utf-8"
)

print("Arquivos textuais alterados:", changed_text)
print("PNGs alterados:", changed_images)
PY
}

apply_variant() {
    local id="$1"
    local theme="${THEME_NAME[$id]}"

    local bg="${BG[$id]}"
    local surface="${SURFACE[$id]}"
    local surface_alt="${SURFACE_ALT[$id]}"
    local border="${BORDER[$id]}"
    local fg="${FG[$id]}"
    local muted="${MUTED[$id]}"
    local accent="${ACCENT[$id]}"
    local accent_hi="${ACCENT_HI[$id]}"
    local accent_dark="${ACCENT_DARK[$id]}"

    # Full MATE legacy scheme: this was the missing piece visible in the screenshots.
    local scheme
    scheme="bg_color:$bg
fg_color:$fg
base_color:$bg
text_color:$fg
selected_bg_color:$accent
selected_fg_color:#ffffff
tooltip_bg_color:$surface
tooltip_fg_color:$fg
titlebar_bg_color:$surface
titlebar_fg_color:$fg
menubar_bg_color:$surface
menubar_fg_color:$fg
toolbar_bg_color:$surface
toolbar_fg_color:$fg
menu_bg_color:$surface
menu_fg_color:$fg
panel_bg_color:$surface
panel_fg_color:$fg
link_color:$accent_hi"

    # Reset old user override first, then install a complete one.
    gsettings reset org.mate.interface gtk-color-scheme 2>/dev/null || true
    gsettings set org.mate.interface gtk-color-scheme "$scheme"

    # Unique theme names force actual reload instead of in-place cache.
    gsettings set org.mate.interface gtk-theme "$theme"
    gsettings set org.mate.interface icon-theme 'Papirus-Dark'
    gsettings set org.mate.peripherals-mouse cursor-theme 'breeze-dark' 2>/dev/null || true
    gsettings set org.mate.peripherals-mouse cursor-size 24 2>/dev/null || true

    if gsettings list-schemas | grep -Fxq 'org.mate.Marco.general'; then
        gsettings set org.mate.Marco.general theme "$theme"
    fi

    # Coco LAST, after all theme changes.
    force_coco || true

    # Restart the file manager so Caja definitely reloads GTK CSS.
    caja -q 2>/dev/null || true
    sleep 1
    caja --no-default-window >/dev/null 2>&1 &

    echo
    echo "============================================================"
    echo "Aplicado: ${LABEL[$id]} ($theme)"
    echo "============================================================"
    echo "GTK ..........: $(gsettings get org.mate.interface gtk-theme)"
    echo "Marco ........: $(gsettings get org.mate.Marco.general theme 2>/dev/null || true)"
    echo "Coco .........: $(gsettings get org.mate.NotificationDaemon theme 2>/dev/null || true)"
    echo
    echo "Observe especialmente:"
    echo "  1. título da janela focada"
    echo "  2. título/janela fora de foco"
    echo "  3. seleção de pastas/arquivos no Caja"
    echo "  4. links, como 'Obter mais temas online'"
    echo

    command -v notify-send >/dev/null 2>&1 \
        && notify-send "Wolf Linux" "${LABEL[$id]} aplicada" || true
}

ensure_dependencies

while true; do
    print_menu
    read -r -p "Opção: " option

    case "$option" in
        1|2|3|4|5)
            install_variant "$option"
            recolor_variant "$option"
            apply_variant "$option"
            ;;
        c|C)
            force_coco
            ;;
        n|N)
            force_numlock
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo "Opção inválida."
            ;;
    esac
done
