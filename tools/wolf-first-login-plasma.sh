#!/usr/bin/env bash
# Wolf Linux - single-shot Plasma setup after the first graphical login.
# Deliberately no systemd service, cron task or permanent watcher.
set -Eeuo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/first-login-plasma"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/wolf-first-login-plasma.desktop"
HELPERS="${WOLF_HELPERS_ROOT:-/usr/local/lib/wolf-linux/helpers/experimental}"
BRANDING="$HELPERS/wolf-plasma-branding-0.2.sh"
MULTIMONITOR="$HELPERS/wolf-plasma-multimonitor-0.3.sh"
DONE="$STATE_DIR/completed"
LOG="$STATE_DIR/setup.log"

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/run.lock"
flock -n 9 || exit 0

if [[ -f "$DONE" ]]; then
    rm -f -- "$AUTOSTART"
    exit 0
fi

# A manual override before the first login can opt out cleanly.
if [[ -e "${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/first-login-plasma.disabled" ]]; then
    printf '%s\n' '[Wolf] Setup do primeiro login desativado manualmente.' >> "$LOG"
    rm -f -- "$AUTOSTART"
    exit 0
fi

case ":${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}:" in
    *KDE*|*Plasma*) ;;
    *) exit 0 ;; # Other sessions must not consume the pending KDE setup.
esac

{
    printf '\n[%s] Configuracao inicial do Plasma\n' "$(date -Is)"
    printf 'Desktop: %s\n' "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-?}}"
} >> "$LOG"

if [[ ! -x "$BRANDING" || ! -x "$MULTIMONITOR" ]]; then
    printf '[ERRO] Helpers ausentes: %s ; %s\n' "$BRANDING" "$MULTIMONITOR" >> "$LOG"
    exit 1
fi

# Autostart can start before Plasma has constructed the default panel.
# Bounded readiness check: stop after 30 seconds, then retry at next login.
ready=0
for ((i=0; i<30; ++i)); do
    if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        'print(panels().length > 0 ? "wolf-panels-ready" : "wolf-panels-pending")' \
        2>/dev/null | grep -Fq 'wolf-panels-ready'; then
        ready=1
        break
    fi
    sleep 1
done
if (( ready == 0 )); then
    printf '[ERRO] Plasma nao ficou pronto apos 30 segundos. Tentara no proximo login.\n' >> "$LOG"
    exit 1
fi

# Ordering matters: first apply chosen SVG to existing Kickoff widgets;
# then create panels (if needed) by inheriting that icon.
if ! "$BRANDING" apply >> "$LOG" 2>&1; then
    printf '[ERRO] Branding falhou; tentara novamente no proximo login.\n' >> "$LOG"
    exit 1
fi
if ! "$MULTIMONITOR" apply >> "$LOG" 2>&1; then
    printf '[ERRO] MultiMonitor falhou; tentara novamente no proximo login.\n' >> "$LOG"
    exit 1
fi

printf '[OK] Branding e MultiMonitor aplicados sem watcher permanente.\n' >> "$LOG"
date -Is > "$DONE"
rm -f -- "$AUTOSTART"
