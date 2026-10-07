#!/usr/bin/env bash
set -Eeuo pipefail

LOGO_NAME="wolf-linux"
LOGO_PATH="/usr/share/pixmaps/wolf-linux.png"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux"
FORCE=0

[[ "${1:-}" == "--force" || "${1:-}" == "force" ]] && FORCE=1

log()  { printf '[Wolf Branding] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }

[[ -f "$LOGO_PATH" ]] || { warn "Logo Wolf Linux não encontrado em $LOGO_PATH"; exit 1; }
mkdir -p "$CONFIG_ROOT"

apply_cinnamon() {
    local marker="$CONFIG_ROOT/branding-cinnamon-v1.done"
    (( FORCE == 1 )) || [[ ! -f "$marker" ]] || return 0

    if command -v gsettings >/dev/null 2>&1; then
        if gsettings list-keys org.cinnamon 2>/dev/null | grep -Fxq 'app-menu-icon-name'; then
            gsettings set org.cinnamon app-menu-icon-name "$LOGO_NAME" 2>/dev/null || true
        fi
        if gsettings list-keys org.cinnamon 2>/dev/null | grep -Fxq 'app-menu-label'; then
            gsettings set org.cinnamon app-menu-label '' 2>/dev/null || true
        fi
    fi

    python3 - "$LOGO_PATH" <<'PY'
import json
import pathlib
import sys

logo = sys.argv[1]
roots = [
    pathlib.Path.home() / ".config/cinnamon/spices/CinnVIIStarkMenu@NikoKrause",
    pathlib.Path.home() / ".cinnamon/configs/CinnVIIStarkMenu@NikoKrause",
    pathlib.Path.home() / ".config/cinnamon/spices/menu@cinnamon.org",
    pathlib.Path.home() / ".cinnamon/configs/menu@cinnamon.org",
]

def set_setting(data, key, value):
    if key in data and isinstance(data[key], dict):
        data[key]["value"] = value
    elif key in data:
        data[key] = value
    else:
        data[key] = {"value": value}

for root in roots:
    if not root.is_dir():
        continue
    for path in sorted(root.glob("*.json")):
        try:
            data = json.loads(path.read_text())
        except Exception:
            continue
        set_setting(data, "menu-custom", True)
        set_setting(data, "menu-icon", logo)
        set_setting(data, "menu-label", "")
        path.write_text(json.dumps(data, ensure_ascii=False, indent=4) + "\n")
        print(f"Wolf Branding: {path}")
PY

    : > "$marker"
    log "Cinnamon: ícone Wolf configurado para o menu de aplicativos."
}

apply_plasma() {
    local marker="$CONFIG_ROOT/branding-plasma-v1.done"
    (( FORCE == 1 )) || [[ ! -f "$marker" ]] || return 0
    command -v qdbus6 >/dev/null 2>&1 || { warn "qdbus6 não encontrado; adiando branding do Plasma."; return 0; }

    for _ in {1..20}; do
        if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
            'panels().forEach(function(p){p.widgets().forEach(function(w){if(w.type === "org.kde.plasma.kickoff"){w.currentConfigGroup=["General"];w.writeConfig("icon","wolf-linux");w.reloadConfig();}});});' \
            >/dev/null 2>&1; then
            : > "$marker"
            log "Plasma: ícone Wolf configurado no Application Launcher."
            return 0
        fi
        sleep 0.25
    done
    warn "plasmashell ainda não estava pronto; branding será tentado novamente no próximo login."
}

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*) apply_cinnamon ;;
    *KDE*|*Plasma*) apply_plasma ;;
    *) exit 0 ;;
esac
