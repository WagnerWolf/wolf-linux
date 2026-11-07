#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.2.1"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/plasma-branding"
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
KICKOFF_ICON="/usr/share/icons/hicolor/scalable/apps/wolf-linux-kickoff.svg"

log()  { printf '[Wolf Plasma Branding] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

check_environment() {
    case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
        *KDE*|*Plasma*) ;;
        *) die "Este helper é somente para KDE Plasma." ;;
    esac

    command -v qdbus6 >/dev/null 2>&1 || die "qdbus6 não encontrado."
    command -v kwriteconfig6 >/dev/null 2>&1 || die "kwriteconfig6 não encontrado."
    command -v kreadconfig6 >/dev/null 2>&1 || die "kreadconfig6 não encontrado."
}

wait_plasma_ready() {
    local _
    for _ in {1..40}; do
        if qdbus6 org.kde.plasmashell /PlasmaShell \
            org.kde.PlasmaShell.evaluateScript 'print("wolf-ready")' \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

make_backup() {
    mkdir -p "$STATE_ROOT"
    local stamp dir
    stamp="$(date +%Y%m%d-%H%M%S)"
    dir="$STATE_ROOT/$stamp"
    mkdir -p "$dir"

    local f
    for f in \
        "$HOME/.config/kdeglobals" \
        "$HOME/.config/kcminputrc" \
        "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"; do
        [[ -f "$f" ]] && cp -a "$f" "$dir/"
    done

    printf '%s\n' "$dir" > "$STATE_ROOT/latest"
    ok "Backup salvo em $dir"
}

apply_kickoff_icon() {
    [[ -f "$KICKOFF_ICON" ]] || die "Ícone dedicado não encontrado: $KICKOFF_ICON"
    wait_plasma_ready || die "plasmashell não ficou pronto."

    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        'panels().forEach(function(p){
            p.widgets().forEach(function(w){
                if(w.type === "org.kde.plasma.kickoff"){
                    w.currentConfigGroup=["General"];
                    w.writeConfig("icon","'"$KICKOFF_ICON"'");
                    w.reloadConfig();
                }
            });
        });' >/dev/null

    log "Ícone SVG dedicado aplicado aos Kickoffs."
}

apply_dark_appearance() {
    if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
        plasma-apply-colorscheme BreezeDark >/dev/null
        log "Esquema de cores Breeze Dark aplicado."
    else
        warn "plasma-apply-colorscheme não encontrado."
    fi

    # Papirus-Dark é visual, não altera layout/painéis.
    if [[ -d /usr/share/icons/Papirus-Dark ]]; then
        kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Dark
        log "Tema de ícones Papirus-Dark aplicado."
    else
        warn "Papirus-Dark não está instalado; preservando tema de ícones atual."
    fi
}

apply_wallpaper() {
    [[ -f "$WALLPAPER" ]] || {
        warn "Wallpaper Wolf não encontrado: $WALLPAPER"
        return 0
    }

    if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
        plasma-apply-wallpaperimage "$WALLPAPER" >/dev/null
        log "Wallpaper Wolf aplicado aos desktops Plasma."
    else
        warn "plasma-apply-wallpaperimage não encontrado."
    fi
}

apply_branding() {
    check_environment
    make_backup
    apply_dark_appearance
    apply_wallpaper
    apply_kickoff_icon
    ok "Branding Plasma 0.2.1 aplicado."
    log "Nenhum autostart, daemon, watcher ou polling foi criado."
}

kickoff_status() {
    wait_plasma_ready || {
        warn "plasmashell não ficou pronto."
        return 1
    }

    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        'panels().forEach(function(p){
            p.widgets().forEach(function(w){
                if(w.type === "org.kde.plasma.kickoff"){
                    w.currentConfigGroup=["General"];
                    print("panel="+p.id+" widget="+w.id+" icon="+w.readConfig("icon"));
                }
            });
        });'
}

wallpaper_status() {
    wait_plasma_ready || return 1
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        'desktops().forEach(function(d){
            d.currentConfigGroup=["Wallpaper","org.kde.image","General"];
            print("screen="+d.screen+" wallpaper="+d.readConfig("Image"));
        });' 2>/dev/null || true
}

status_branding() {
    check_environment
    printf 'Wolf Plasma Branding v%s\n' "$VERSION"
    printf 'ColorScheme=%s\n' \
        "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)"
    printf 'IconTheme=%s\n' \
        "$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"
    printf 'Kickoff icon source=%s\n' "$KICKOFF_ICON"
    kickoff_status
    wallpaper_status
}

restore_latest() {
    check_environment
    [[ -f "$STATE_ROOT/latest" ]] || die "Nenhum backup encontrado."
    local dir
    dir="$(cat "$STATE_ROOT/latest")"
    [[ -d "$dir" ]] || die "Backup inválido: $dir"

    local base
    for base in kdeglobals kcminputrc plasma-org.kde.plasma.desktop-appletsrc; do
        if [[ -f "$dir/$base" ]]; then
            cp -a "$dir/$base" "$HOME/.config/$base"
        fi
    done

    if systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1; then
        :
    else
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        nohup plasmashell --replace >/dev/null 2>&1 &
    fi
    ok "Último backup restaurado."
}

case "${1:-status}" in
    apply) apply_branding ;;
    status) status_branding ;;
    restore) restore_latest ;;
    *)
        echo "Uso: $(basename "$0") {status|apply|restore}"
        exit 2
        ;;
esac
