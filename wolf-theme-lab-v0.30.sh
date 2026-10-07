#!/usr/bin/env bash
set -Eeuo pipefail

THEME_NAME="Wolf-Sunrise-Dark"
THEME_DIR="/usr/share/themes/$THEME_NAME"
WORKDIR="/tmp/wolf-theme-lab"
SOURCE_URL="https://github.com/i-mint/sunrise/archive/refs/heads/master.tar.gz"

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute este script dentro da sessão MATE."
    exit 1
fi

declare -A PALETTE_NAME
declare -A BG
declare -A SURFACE
declare -A SURFACE_ALT
declare -A BORDER
declare -A FG
declare -A MUTED
declare -A ACCENT
declare -A ACCENT_HI
declare -A ACCENT_DARK

# 1 - perfil mais próximo do branding atual
PALETTE_NAME[1]="Prata Lunar"
BG[1]="#151519"
SURFACE[1]="#1d1d22"
SURFACE_ALT[1]="#292930"
BORDER[1]="#454650"
FG[1]="#f0f0f3"
MUTED[1]="#b5b6bd"
ACCENT[1]="#6d707b"
ACCENT_HI[1]="#8a8d98"
ACCENT_DARK[1]="#555862"

# 2 - leve tonalidade fria, sem virar azul forte
PALETTE_NAME[2]="Aço Lunar"
BG[2]="#14171b"
SURFACE[2]="#1d2228"
SURFACE_ALT[2]="#29313a"
BORDER[2]="#46515d"
FG[2]="#eef1f4"
MUTED[2]="#adb5bd"
ACCENT[2]="#5e6c7a"
ACCENT_HI[2]="#748596"
ACCENT_DARK[2]="#485562"

# 3 - mais neutro e discreto
PALETTE_NAME[3]="Grafite"
BG[3]="#161618"
SURFACE[3]="#202023"
SURFACE_ALT[3]="#2b2b2f"
BORDER[3]="#444449"
FG[3]="#ededf0"
MUTED[3]="#b0b0b5"
ACCENT[3]="#595b63"
ACCENT_HI[3]="#72747d"
ACCENT_DARK[3]="#45474e"

# 4 - contraste um pouco maior
PALETTE_NAME[4]="Gunmetal"
BG[4]="#111317"
SURFACE[4]="#1b1e23"
SURFACE_ALT[4]="#282c33"
BORDER[4]="#4b5059"
FG[4]="#f3f3f5"
MUTED[4]="#b7bac0"
ACCENT[4]="#646a74"
ACCENT_HI[4]="#828995"
ACCENT_DARK[4]="#4c515a"

# 5 - quase monocromático
PALETTE_NAME[5]="Obsidiana"
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
    echo "              WOLF LINUX - THEME LAB v0.30"
    echo "============================================================"
    echo
    echo "Escolha uma paleta:"
    echo
    for i in 1 2 3 4 5; do
        printf "  %s) %-14s  accent=%s\n" "$i" "${PALETTE_NAME[$i]}" "${ACCENT[$i]}"
    done
    echo
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
        echo "Instalando dependências do laboratório: ${missing[*]}"
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    fi
}

download_clean_sunrise() {
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

install_clean_theme() {
    sudo rm -rf "$THEME_DIR"
    sudo cp -a "$SOURCE_THEME" "$THEME_DIR"

    local root
    root="$(dirname "$SOURCE_THEME")"

    if [[ -f "$root/COPYING" ]]; then
        sudo cp -f "$root/COPYING" "$THEME_DIR/COPYING"
    fi
}

apply_palette() {
    local id="$1"

    local bg="${BG[$id]}"
    local surface="${SURFACE[$id]}"
    local surface_alt="${SURFACE_ALT[$id]}"
    local border="${BORDER[$id]}"
    local fg="${FG[$id]}"
    local muted="${MUTED[$id]}"
    local accent="${ACCENT[$id]}"
    local accent_hi="${ACCENT_HI[$id]}"
    local accent_dark="${ACCENT_DARK[$id]}"

    echo
    echo "[INFO] Aplicando ${PALETTE_NAME[$id]}..."
    echo "       bg=$bg surface=$surface accent=$accent"

    sudo env \
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

root = Path("/usr/share/themes/Wolf-Sunrise-Dark")

bg = os.environ["WOLF_BG"]
surface = os.environ["WOLF_SURFACE"]
surface_alt = os.environ["WOLF_SURFACE_ALT"]
border = os.environ["WOLF_BORDER"]
fg = os.environ["WOLF_FG"]
muted = os.environ["WOLF_MUTED"]
accent = os.environ["WOLF_ACCENT"]
accent_hi = os.environ["WOLF_ACCENT_HI"]
accent_dark = os.environ["WOLF_ACCENT_DARK"]

def rgb(hexstr):
    s = hexstr.lstrip("#")
    return tuple(int(s[i:i+2], 16) for i in (0,2,4))

ACCENT = rgb(accent)
ACCENT_HI = rgb(accent_hi)
ACCENT_DARK = rgb(accent_dark)

# ------------------------------------------------------------------
# Text files: CSS/XML/RC/SVG/XPM
# ------------------------------------------------------------------
hex_re = re.compile(r"#[0-9a-fA-F]{6}\b")
extensions = {".css", ".xml", ".rc", ".svg", ".xpm", ".theme"}

def warm_replacement(match):
    token = match.group(0)

    r = int(token[1:3],16) / 255
    g = int(token[3:5],16) / 255
    b = int(token[5:7],16) / 255

    h,s,v = colorsys.rgb_to_hsv(r,g,b)

    # Cobre marrom, âmbar, laranja e amarelo-alaranjado.
    if not (0.015 <= h <= 0.19 and s >= 0.08 and v >= 0.12):
        return token

    lum = 0.2126*r + 0.7152*g + 0.0722*b

    if lum >= 0.67:
        out = ACCENT_HI
    elif lum >= 0.38:
        out = ACCENT
    else:
        out = ACCENT_DARK

    return "#%02x%02x%02x" % out

changed_text = 0

for path in root.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in extensions:
        continue

    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue

    updated = hex_re.sub(warm_replacement, original)

    updated = re.sub(r"\bdarkorange\b", accent_dark, updated, flags=re.I)
    updated = re.sub(r"\borange\b", accent, updated, flags=re.I)

    if updated != original:
        path.write_text(updated, encoding="utf-8")
        changed_text += 1

# ------------------------------------------------------------------
# Raster assets: neutraliza pixels quentes em PNG.
# Isso pega inclusive decoração/gradientes usados pelo Marco.
# ------------------------------------------------------------------
changed_images = 0

for path in root.rglob("*.png"):
    try:
        image = Image.open(path).convert("RGBA")
    except Exception:
        continue

    data = list(image.getdata())
    out = []
    changed = False

    for r,g,b,a in data:
        if a == 0:
            out.append((r,g,b,a))
            continue

        h,s,v = colorsys.rgb_to_hsv(r/255,g/255,b/255)

        if 0.015 <= h <= 0.19 and s >= 0.08 and v >= 0.12:
            lum = (0.2126*r + 0.7152*g + 0.0722*b) / 255

            if lum >= 0.67:
                nr,ng,nb = ACCENT_HI
            elif lum >= 0.38:
                nr,ng,nb = ACCENT
            else:
                nr,ng,nb = ACCENT_DARK

            out.append((nr,ng,nb,a))
            changed = True
        else:
            out.append((r,g,b,a))

    if changed:
        image.putdata(out)
        image.save(path)
        changed_images += 1

# ------------------------------------------------------------------
# Strong GTK3 overrides
# ------------------------------------------------------------------
override = f"""

/* ==========================================================
 * Wolf Linux Theme Lab generated palette
 * ========================================================== */
@define-color theme_bg_color {bg};
@define-color theme_fg_color {fg};
@define-color theme_base_color {bg};
@define-color theme_text_color {fg};

@define-color theme_selected_bg_color {accent};
@define-color theme_selected_fg_color #ffffff;

@define-color theme_unfocused_bg_color {surface};
@define-color theme_unfocused_fg_color {muted};
@define-color theme_unfocused_base_color {surface};
@define-color theme_unfocused_text_color {muted};
@define-color theme_unfocused_selected_bg_color {accent_dark};
@define-color theme_unfocused_selected_fg_color #ffffff;

@define-color borders {border};
@define-color unfocused_borders {border};

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
button.suggested-action,
row:selected,
treeview.view:selected,
iconview:selected,
flowboxchild:selected,
*:selected {{
    background-image: none;
    background-color: {accent};
    color: #ffffff;
    border-color: {accent_hi};
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

for candidate in [
    root / "gtk-3.0" / "gtk.css",
    root / "gtk-3.20" / "gtk.css",
]:
    if candidate.exists():
        with candidate.open("a", encoding="utf-8") as f:
            f.write(override)

# ------------------------------------------------------------------
# GTK2
# ------------------------------------------------------------------
gtk2 = root / "gtk-2.0" / "gtkrc"

if gtk2.exists():
    with gtk2.open("a", encoding="utf-8") as f:
        f.write(
            "\n# Wolf Linux Theme Lab\n"
            'gtk-color-scheme = "'
            f"bg_color:{bg}\\n"
            f"fg_color:{fg}\\n"
            f"base_color:{bg}\\n"
            f"text_color:{fg}\\n"
            f"selected_bg_color:{accent}\\n"
            "selected_fg_color:#ffffff\\n"
            f"tooltip_bg_color:{surface}\\n"
            f"tooltip_fg_color:{fg}"
            '"\n'
        )

# ------------------------------------------------------------------
# Metatheme
# ------------------------------------------------------------------
index = root / "index.theme"
index.write_text(
f"""[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Wolf-Sunrise-Dark
Comment=Wolf Linux dark theme based on Sunrise-Dark
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Wolf-Sunrise-Dark
MetacityTheme=Wolf-Sunrise-Dark
IconTheme=Papirus-Dark
CursorTheme=breeze-dark
NotificationTheme=coco
ButtonLayout=menu:minimize,maximize,close
""",
encoding="utf-8"
)

print(f"Arquivos textuais recoloridos: {changed_text}")
print(f"Imagens PNG recoloridas: {changed_images}")
PY

    # MATE's legacy color scheme override, useful for GTK2 and some controls.
    gsettings set org.mate.interface gtk-color-scheme \
        "bg_color:$bg
fg_color:$fg
base_color:$bg
text_color:$fg
selected_bg_color:$accent
selected_fg_color:#ffffff" || true

    # Coco notifications.
    if gsettings list-schemas | grep -Fxq 'org.mate.NotificationDaemon'; then
        gsettings set org.mate.NotificationDaemon theme 'coco'
        pkill -f mate-notification-daemon 2>/dev/null || true
    fi

    # Force immediate theme reload.
    if [[ -d /usr/share/themes/Adwaita-dark ]]; then
        gsettings set org.mate.interface gtk-theme 'Adwaita-dark'
        sleep 1
    fi

    gsettings set org.mate.interface gtk-theme "$THEME_NAME"
    gsettings set org.mate.interface icon-theme 'Papirus-Dark'

    if gsettings list-schemas | grep -Fxq 'org.mate.Marco.general'; then
        # Pick any other valid Marco theme briefly, then switch back.
        alternate="$(
            find /usr/share/themes \
                -mindepth 2 \
                -maxdepth 2 \
                -type d \
                -name metacity-1 \
                ! -path "$THEME_DIR/*" \
                -printf '%h\n' 2>/dev/null \
                | xargs -r -n1 basename \
                | head -1
        )"

        if [[ -n "${alternate:-}" ]]; then
            gsettings set org.mate.Marco.general theme "$alternate" || true
            sleep 1
        fi

        gsettings set org.mate.Marco.general theme "$THEME_NAME"
    fi

    echo
    echo "============================================================"
    echo "Paleta aplicada: ${PALETTE_NAME[$id]}"
    echo "============================================================"
    echo "Tema GTK ....: $(gsettings get org.mate.interface gtk-theme)"
    echo "Tema Marco ..: $(gsettings get org.mate.Marco.general theme 2>/dev/null || true)"
    echo "Notificações : $(gsettings get org.mate.NotificationDaemon theme 2>/dev/null || true)"
    echo
    echo "Teste agora principalmente:"
    echo "  • janela focada e não focada"
    echo "  • seleção de pastas no Caja"
    echo "  • botões/abas"
    echo "  • menus"
    echo "  • notificação Coco"
    echo
    echo "Para gerar uma notificação de teste:"
    echo "  notify-send 'Wolf Linux' 'Teste da notificação Coco'"
    echo

    command -v notify-send >/dev/null 2>&1 \
        && notify-send "Wolf Linux" "Paleta ${PALETTE_NAME[$id]} aplicada" || true
}

ensure_dependencies
download_clean_sunrise

while true; do
    print_menu
    read -r -p "Opção: " option

    case "$option" in
        1|2|3|4|5)
            install_clean_theme
            apply_palette "$option"
            ;;
        q|Q)
            echo "Saindo."
            exit 0
            ;;
        *)
            echo "Opção inválida."
            ;;
    esac
done
