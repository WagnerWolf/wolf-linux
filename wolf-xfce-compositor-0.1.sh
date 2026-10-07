#!/usr/bin/env bash
set -Eeuo pipefail

PICOM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/picom"
PICOM_CONFIG="$PICOM_CONFIG_DIR/wolf-xfce.conf"
PICOM_AUTOSTART="$HOME/.config/autostart/picom.desktop"
WOLF_AUTOSTART="$HOME/.config/autostart/wolf-xfce-picom.desktop"
WOLF_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux"
DEFAULT_MARKER="$WOLF_CONFIG_DIR/xfce-compositor-v1.done"

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

check_xfce() {
    case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
        *XFCE*|*Xfce*) ;;
        *) die "Este helper foi feito para uma sessão XFCE." ;;
    esac
    [[ "${XDG_SESSION_TYPE:-x11}" == "x11" ]] || die "Picom é um compositor X11; esta sessão não é X11."
    command -v xfconf-query >/dev/null 2>&1 || die "xfconf-query não encontrado."
}

wait_xfwm_xfconf() {
    for _ in {1..40}; do
        if xfconf-query -c xfwm4 -p /general/use_compositing >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

mark_compositor_decision() {
    mkdir -p "$WOLF_CONFIG_DIR"
    : > "$DEFAULT_MARKER"
}

ensure_picom() {
    if command -v picom >/dev/null 2>&1; then
        return 0
    fi
    command -v pacman >/dev/null 2>&1 || die "picom não instalado e pacman não encontrado."
    info "Instalando picom dos repositórios oficiais..."
    sudo pacman -S --needed picom
}

disable_vendor_autostart() {
    mkdir -p "$(dirname "$PICOM_AUTOSTART")"
    cat > "$PICOM_AUTOSTART" <<'PICOM_DESKTOP'
[Desktop Entry]
Type=Application
Name=Picom
Hidden=true
PICOM_DESKTOP
}

stop_picom() {
    pkill -x picom >/dev/null 2>&1 || true
    rm -f "$WOLF_AUTOSTART"
}

disable_xfwm_compositor() {
    xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false 2>/dev/null \
        || xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
}

write_config() {
    local backend="$1"
    mkdir -p "$PICOM_CONFIG_DIR"

    if [[ "$backend" == "xrender" ]]; then
        cat > "$PICOM_CONFIG" <<'PICOM_CONF'
backend = "xrender";
vsync = true;
shadow = true;
shadow-radius = 10;
shadow-opacity = 0.35;
shadow-offset-x = -7;
shadow-offset-y = -7;
fading = false;
inactive-opacity = 1.0;
active-opacity = 1.0;
frame-opacity = 1.0;
use-damage = true;
mark-wmwin-focused = true;
mark-ovredir-focused = true;
detect-rounded-corners = true;
detect-client-opacity = true;
PICOM_CONF
    else
        cat > "$PICOM_CONFIG" <<'PICOM_CONF'
backend = "glx";
vsync = true;
xrender-sync-fence = true;
shadow = true;
shadow-radius = 10;
shadow-opacity = 0.35;
shadow-offset-x = -7;
shadow-offset-y = -7;
fading = false;
inactive-opacity = 1.0;
active-opacity = 1.0;
frame-opacity = 1.0;
use-damage = true;
mark-wmwin-focused = true;
mark-ovredir-focused = true;
detect-rounded-corners = true;
detect-client-opacity = true;
PICOM_CONF
    fi
}

start_mode() {
    local backend="$1"
    check_xfce
    ensure_picom
    disable_vendor_autostart
    disable_xfwm_compositor
    stop_picom
    write_config "$backend"
    nohup picom --config "$PICOM_CONFIG" >/dev/null 2>&1 &
    sleep 0.5
    pgrep -x picom >/dev/null 2>&1 || die "Picom não permaneceu em execução. Rode 'picom --config $PICOM_CONFIG' no terminal para ver o erro."
    ok "Picom ativo com backend $backend. Esta alteração ainda NÃO é persistente."
    info "Teste o arraste de abas do Chrome. Use '$(basename "$0") off' para voltar ao modo sem compositor."
}

persist_mode() {
    local backend="$1"
    start_mode "$backend"
    mkdir -p "$(dirname "$WOLF_AUTOSTART")"
    cat > "$WOLF_AUTOSTART" <<PICOM_DESKTOP
[Desktop Entry]
Type=Application
Name=Wolf Linux - Picom XFCE ($backend)
Comment=Compositor Picom validado pelo usuário para XFCE
Exec=sh -c 'xfconf-query -c xfwm4 -p /general/use_compositing -s false >/dev/null 2>&1 || true; exec picom --config "$PICOM_CONFIG"'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
PICOM_DESKTOP
    mark_compositor_decision
    ok "Modo $backend persistirá nos próximos logins XFCE."
}

mode_off() {
    check_xfce
    stop_picom
    disable_vendor_autostart
    disable_xfwm_compositor
    mark_compositor_decision
    ok "Picom parado e compositor do xfwm4 desligado."
}

ensure_default() {
    check_xfce
    [[ -f "$DEFAULT_MARKER" ]] && return 0

    wait_xfwm_xfconf || info "xfconf ainda não respondeu; tentando aplicar o padrão mesmo assim."
    info "Primeiro login XFCE: aplicando Picom/XRender como compositor padrão Wolf."
    persist_mode xrender
}

status() {
    check_xfce
    local xfwm picom_state backend="-"
    xfwm="$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null || printf '?')"
    if pgrep -x picom >/dev/null 2>&1; then
        picom_state="ativo"
    else
        picom_state="inativo"
    fi
    if [[ -r "$PICOM_CONFIG" ]]; then
        backend="$(sed -nE 's/^[[:space:]]*backend[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$PICOM_CONFIG" | head -n1)"
    fi
    say "XFWM compositor: $xfwm"
    say "Picom: $picom_state"
    say "Backend configurado: ${backend:--}"
    say "Persistente: $([[ -f "$WOLF_AUTOSTART" ]] && printf sim || printf não)"
    say "Decisão inicial registrada: $([[ -f "$DEFAULT_MARKER" ]] && printf sim || printf não)"
}

usage() {
    cat <<USAGE
Uso: $(basename "$0") COMANDO

  xrender           testa Picom/XRender nesta sessão
  glx               testa Picom/GLX + xrender-sync-fence nesta sessão
  persist-xrender   mantém XRender nos próximos logins
  persist-glx       mantém GLX nos próximos logins
  ensure-default    aplica XRender uma única vez no primeiro login XFCE
  off               para Picom e mantém composição do xfwm4 desligada
  status            mostra o estado atual
USAGE
}

case "${1:-status}" in
    xrender) start_mode xrender ;;
    glx) start_mode glx ;;
    persist-xrender) persist_mode xrender ;;
    persist-glx) persist_mode glx ;;
    ensure-default) ensure_default ;;
    off) mode_off ;;
    status) status ;;
    *) usage; exit 2 ;;
esac
