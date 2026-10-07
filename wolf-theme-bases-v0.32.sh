#!/usr/bin/env bash
set -Eeuo pipefail

WORKDIR="/tmp/wolf-theme-base-lab"
SUNRISE_URL="https://github.com/i-mint/sunrise/archive/refs/heads/master.tar.gz"
WOLF_BORDER="/usr/share/themes/Wolf-Sunrise-Border"

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute este script dentro da sessão MATE."
    exit 1
fi

log()  { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*"; }

ensure_native_themes() {
    if [[ ! -d /usr/share/themes/BlackMATE ]]; then
        sudo pacman -S --needed --noconfirm mate-themes
    fi

    [[ -d /usr/share/themes/BlackMATE ]] || {
        echo "[ERRO] BlackMATE não encontrado."
        exit 1
    }
}

force_coco() {
    if gsettings list-schemas | grep -Fxq 'org.mate.NotificationDaemon'; then
        local attempt current

        for attempt in 1 2 3 4 5; do
            gsettings set org.mate.NotificationDaemon theme 'coco' || true
            current="$(gsettings get org.mate.NotificationDaemon theme 2>/dev/null || true)"

            if [[ "$current" == "'coco'" ]]; then
                pkill -x mate-notification-daemon 2>/dev/null || true
                sleep 1
                return 0
            fi

            echo "Tentativa Coco $attempt/5..."
            sleep 1
        done
    fi

    return 1
}

reset_user_color_overrides() {
    # Theme Labs anteriores deixaram gtk-color-scheme persistente no usuário.
    # Isso pode misturar cores do tema novo com cores antigas.
    gsettings reset org.mate.interface gtk-color-scheme 2>/dev/null || true

    if [[ -s "$HOME/.config/gtk-3.0/gtk.css" ]]; then
        warn "Existe ~/.config/gtk-3.0/gtk.css."
        warn "Ele também pode sobrepor as cores do tema."
    fi
}

prepare_wolf_sunrise_border() {
    if [[ -d "$WOLF_BORDER/metacity-1" ]]; then
        return 0
    fi

    log "Preparando somente a decoração Sunrise, em tons neutros..."

    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR/extracted"

    curl \
        -fL \
        --retry 3 \
        --connect-timeout 15 \
        "$SUNRISE_URL" \
        -o "$WORKDIR/sunrise.tar.gz"

    tar -xzf "$WORKDIR/sunrise.tar.gz" -C "$WORKDIR/extracted"

    local source_theme
    source_theme="$(
        find "$WORKDIR/extracted" \
            -mindepth 2 \
            -maxdepth 2 \
            -type d \
            -name Sunrise-Dark \
            -print \
            -quit
    )"

    [[ -n "$source_theme" ]] || {
        echo "[ERRO] Sunrise-Dark não encontrado."
        exit 1
    }

    sudo rm -rf "$WOLF_BORDER"
    sudo install -d "$WOLF_BORDER"
    sudo cp -a "$source_theme/metacity-1" "$WOLF_BORDER/metacity-1"

    if [[ -f "$(dirname "$source_theme")/COPYING" ]]; then
        sudo cp -f "$(dirname "$source_theme")/COPYING" "$WOLF_BORDER/COPYING"
    fi

    sudo tee "$WOLF_BORDER/index.theme" >/dev/null <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Wolf-Sunrise-Border
Comment=Neutral Sunrise window decoration for Wolf Linux
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=BlackMATE
MetacityTheme=Wolf-Sunrise-Border
IconTheme=Papirus-Dark
CursorTheme=breeze-dark
NotificationTheme=coco
ButtonLayout=menu:minimize,maximize,close
EOF

    sudo python - <<'PY'
from pathlib import Path
from PIL import Image
import colorsys
import re

root = Path("/usr/share/themes/Wolf-Sunrise-Border/metacity-1")

ACCENT = (96, 99, 109)
ACCENT_HI = (132, 135, 146)
ACCENT_DARK = (67, 69, 77)

def neutral(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)

    warm = (
        (0.01 <= h <= 0.20 and s >= 0.05 and v >= 0.08)
        or (r > g * 1.10 and g >= b * 0.88 and r-b >= 9)
    )

    if not warm:
        return None

    lum = (0.2126*r + 0.7152*g + 0.0722*b) / 255

    if lum >= 0.67:
        return ACCENT_HI
    if lum >= 0.34:
        return ACCENT
    return ACCENT_DARK

hex6 = re.compile(r"#[0-9a-fA-F]{6}\b")
hex3 = re.compile(r"#[0-9a-fA-F]{3}\b")
rgbfn = re.compile(
    r"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(\s*,\s*[^)]+)?\)"
)

def h6(m):
    s = m.group(0)
    out = neutral(int(s[1:3],16), int(s[3:5],16), int(s[5:7],16))
    return s if out is None else "#%02x%02x%02x" % out

def h3(m):
    s = m.group(0)
    out = neutral(int(s[1]*2,16), int(s[2]*2,16), int(s[3]*2,16))
    return s if out is None else "#%02x%02x%02x" % out

def rgb_replace(m):
    r, g, b = [min(255, int(m.group(i))) for i in (1,2,3)]
    out = neutral(r,g,b)
    if out is None:
        return m.group(0)

    alpha = m.group(4) or ""

    if alpha:
        return f"rgba({out[0]}, {out[1]}, {out[2]}{alpha})"

    return f"rgb({out[0]}, {out[1]}, {out[2]})"

for path in root.rglob("*"):
    if not path.is_file():
        continue

    if path.suffix.lower() in {".xml", ".svg", ".xpm", ".rc"}:
        try:
            old = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        new = hex6.sub(h6, old)
        new = hex3.sub(h3, new)
        new = rgbfn.sub(rgb_replace, new)
        new = re.sub(r"\bdarkorange\b", "#43454d", new, flags=re.I)
        new = re.sub(r"\borange\b", "#60636d", new, flags=re.I)

        if new != old:
            path.write_text(new, encoding="utf-8")

    elif path.suffix.lower() == ".png":
        try:
            im = Image.open(path).convert("RGBA")
        except Exception:
            continue

        changed = False
        data = []

        for r,g,b,a in im.getdata():
            out = neutral(r,g,b)

            if a and out:
                data.append((*out,a))
                changed = True
            else:
                data.append((r,g,b,a))

        if changed:
            im.putdata(data)
            im.save(path)
PY

    ok "Wolf-Sunrise-Border preparado."
}

apply_theme() {
    local gtk_theme="$1"
    local marco_theme="$2"
    local label="$3"

    reset_user_color_overrides

    echo
    log "Aplicando $label"
    echo "  GTK   : $gtk_theme"
    echo "  Marco : $marco_theme"

    gsettings set org.mate.interface gtk-theme "$gtk_theme"
    gsettings set org.mate.interface icon-theme 'Papirus-Dark'

    if gsettings list-schemas | grep -Fxq 'org.mate.Marco.general'; then
        gsettings set org.mate.Marco.general theme "$marco_theme"
    fi

    gsettings set org.mate.peripherals-mouse cursor-theme 'breeze-dark' 2>/dev/null || true
    gsettings set org.mate.peripherals-mouse cursor-size 24 2>/dev/null || true

    force_coco || warn "Coco não pôde ser confirmado."

    # Reinicia somente processos que precisam reler o GTK theme.
    caja -q 2>/dev/null || true
    pkill mate-panel 2>/dev/null || true

    sleep 2
    caja --no-default-window >/dev/null 2>&1 &

    echo
    echo "------------------------------------------------------------"
    echo "GTK ...........: $(gsettings get org.mate.interface gtk-theme)"
    echo "Marco .........: $(gsettings get org.mate.Marco.general theme 2>/dev/null || true)"
    echo "Coco ..........: $(gsettings get org.mate.NotificationDaemon theme 2>/dev/null || true)"
    echo "------------------------------------------------------------"
    echo
    echo "Observe:"
    echo "  - painel inteiro"
    echo "  - Brisk"
    echo "  - lista de janelas"
    echo "  - Caja ativo/inativo"
    echo "  - seleção de pasta"
    echo "  - Preferências de aparência"
}

install_materia_if_needed() {
    if [[ ! -d /usr/share/themes/Materia-dark ]]; then
        sudo pacman -S --needed --noconfirm materia-gtk-theme
    fi
}

menu() {
    echo
    echo "============================================================"
    echo "         WOLF LINUX - THEME BASE LAB 3.0"
    echo "============================================================"
    echo
    echo "Agora testamos BASES diferentes, não apenas cores da mesma base."
    echo
    echo "  1) BlackMATE completo"
    echo "     Integração nativa com MATE, painel, Caja e applets."
    echo
    echo "  2) BlackMATE + borda Sunrise Wolf"
    echo "     Mantém GTK/painel nativo e usa apenas a decoração Sunrise."
    echo
    echo "  3) Adwaita-dark + borda Sunrise Wolf"
    echo "     Mais genérico/moderno."
    echo
    echo "  4) Materia-dark + borda Sunrise Wolf"
    echo "     Visual Material; instala materia-gtk-theme se necessário."
    echo
    echo "  r) Resetar gtk-color-scheme do usuário"
    echo "  c) Forçar Coco"
    echo "  q) Sair"
    echo
}

ensure_native_themes
prepare_wolf_sunrise_border

while true; do
    menu
    read -r -p "Opção: " option

    case "$option" in
        1)
            apply_theme "BlackMATE" "BlackMATE" "BlackMATE completo"
            ;;
        2)
            apply_theme "BlackMATE" "Wolf-Sunrise-Border" "BlackMATE + Sunrise Wolf"
            ;;
        3)
            apply_theme "Adwaita-dark" "Wolf-Sunrise-Border" "Adwaita-dark + Sunrise Wolf"
            ;;
        4)
            install_materia_if_needed
            apply_theme "Materia-dark" "Wolf-Sunrise-Border" "Materia-dark + Sunrise Wolf"
            ;;
        r|R)
            reset_user_color_overrides
            ok "gtk-color-scheme resetado."
            ;;
        c|C)
            force_coco && ok "Coco confirmado."
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo "Opção inválida."
            ;;
    esac
done
