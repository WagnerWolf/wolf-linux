#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.2"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/plasma-multimonitor"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux"
DISABLED_MARKER="$CONFIG_ROOT/plasma-multimonitor.disabled"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/wolf-plasma-multimonitor-${UID}.pid"
PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
LOG_FILE="$STATE_ROOT/watch.log"

log()  { printf '\033[1;34m[Wolf Plasma MultiMonitor]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

check_environment() {
    case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
        *KDE*|*Plasma*) ;;
        *) die "Este helper é somente para KDE Plasma." ;;
    esac
    command -v qdbus6 >/dev/null 2>&1 || die "qdbus6 não encontrado."
}

plasma_eval() {
    local script="$1"
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script"
}

topology_signature() {
    if command -v kscreen-doctor >/dev/null 2>&1; then
        kscreen-doctor -o 2>/dev/null \
            | grep -E '^[[:space:]]*Output:|^[[:space:]]*enabled|^[[:space:]]*connected|^[[:space:]]*Geometry:' \
            | tr '\n' '|' || true
    elif command -v xrandr >/dev/null 2>&1; then
        xrandr --listmonitors 2>/dev/null | tail -n +2 | tr '\n' '|' || true
    else
        printf 'plasma-only'
    fi
}

make_backup() {
    mkdir -p "$STATE_ROOT"
    local stamp dir
    stamp="$(date +%Y%m%d-%H%M%S)"
    dir="$STATE_ROOT/$stamp"
    mkdir -p "$dir"
    [[ -f "$PLASMA_CONFIG" ]] && cp -a "$PLASMA_CONFIG" "$dir/plasma-org.kde.plasma.desktop-appletsrc"
    printf '%s\n' "$dir" > "$STATE_ROOT/latest"
    ok "Backup salvo em $dir"
}

ensure_baseline_backup() {
    local marker="$STATE_ROOT/automatic-baseline"
    [[ -f "$marker" ]] && return 0
    make_backup
    cp "$STATE_ROOT/latest" "$marker"
}

reconcile_plasma() {
    check_environment

    local js
    read -r -d '' js <<'JS' || true
function uniqueScreens() {
    var seen = {};
    var out = [];
    desktops().forEach(function(d) {
        var s = d.screen;
        if (s >= 0 && !seen[s]) {
            seen[s] = true;
            out.push(s);
        }
    });
    out.sort(function(a, b) { return a - b; });
    return out;
}

function isTaskWidget(w) {
    return w.type === "org.kde.plasma.taskmanager" ||
           w.type === "org.kde.plasma.icontasks";
}

function makeTasksLocal(panel) {
    panel.widgets().forEach(function(w) {
        if (!isTaskWidget(w)) return;
        w.currentConfigGroup = ["General"];
        w.writeConfig("showOnlyCurrentScreen", true);
        w.reloadConfig();
    });
}

function makeKickoffWolf(panel) {
    panel.widgets().forEach(function(w) {
        if (w.type !== "org.kde.plasma.kickoff") return;
        w.currentConfigGroup = ["General"];
        w.writeConfig("icon", "wolf-linux");
        w.reloadConfig();
    });
}

var screens = uniqueScreens();
var allPanels = panels();
var panelForScreen = {};

allPanels.forEach(function(p) {
    if (p.screen >= 0 && panelForScreen[p.screen] === undefined) {
        panelForScreen[p.screen] = p;
    }
    makeTasksLocal(p);
    makeKickoffWolf(p);
});

screens.forEach(function(screen) {
    if (panelForScreen[screen] !== undefined) return;

    var panel = new Panel;
    panel.screen = screen;
    panel.location = "bottom";
    panel.height = Math.round(gridUnit * 2.2);

    var kickoff = panel.addWidget("org.kde.plasma.kickoff");
    kickoff.currentConfigGroup = ["General"];
    kickoff.writeConfig("icon", "wolf-linux");
    kickoff.reloadConfig();

    var tasks = panel.addWidget("org.kde.plasma.icontasks");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("showOnlyCurrentScreen", true);
    tasks.writeConfig("showOnlyCurrentActivity", true);
    tasks.reloadConfig();

    panel.addWidget("org.kde.plasma.panelspacer");
    panel.addWidget("org.kde.plasma.digitalclock");
    panel.addWidget("org.kde.plasma.showdesktop");

    print("Wolf Plasma MultiMonitor: painel criado na tela " + screen + " (id=" + panel.id + ")");
});

// Reafirma filtro e identidade em todas as instâncias após a criação.
panels().forEach(function(p) { makeTasksLocal(p); makeKickoffWolf(p); });
JS
    plasma_eval "$js" >/dev/null
}

show_state() {
    check_environment
    echo
    echo "======================================================"
    echo "       WOLF PLASMA MULTIMONITOR v${VERSION}"
    echo "======================================================"
    echo
    if [[ -e "$DISABLED_MARKER" ]]; then
        log "Gerenciamento automático: DESATIVADO"
    else
        log "Gerenciamento automático: ATIVADO"
    fi
    echo
    plasma_eval '
        print("Painéis:");
        panels().forEach(function(p) {
            print("  panel" + p.id + " screen=" + p.screen + " location=" + p.location);
            p.widgets().forEach(function(w) {
                if (w.type === "org.kde.plasma.taskmanager" || w.type === "org.kde.plasma.icontasks") {
                    w.currentConfigGroup = ["General"];
                    print("    " + w.type + " showOnlyCurrentScreen=" + w.readConfig("showOnlyCurrentScreen"));
                }
            });
        });
    '
}

stop_watcher() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
}

disable_automatic() {
    mkdir -p "$CONFIG_ROOT"
    : > "$DISABLED_MARKER"
    stop_watcher
    ok "Gerenciamento automático do Plasma desativado; painéis existentes foram preservados."
}

enable_automatic() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    rm -f "$DISABLED_MARKER"
    ensure_baseline_backup
    reconcile_plasma
    nohup "$0" watch >/dev/null 2>&1 &
    ok "Gerenciamento automático do Plasma ativado."
}

restore_latest() {
    check_environment
    disable_automatic >/dev/null
    [[ -f "$STATE_ROOT/latest" ]] || die "Nenhum backup encontrado."
    local dir
    dir="$(cat "$STATE_ROOT/latest")"
    [[ -f "$dir/plasma-org.kde.plasma.desktop-appletsrc" ]] || die "Backup inválido: $dir"
    cp -a "$dir/plasma-org.kde.plasma.desktop-appletsrc" "$PLASMA_CONFIG"
    if systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1; then
        :
    else
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        nohup plasmashell --replace >/dev/null 2>&1 &
    fi
    ok "Layout Plasma restaurado; gerenciamento automático ficou desativado."
}

watch_loop() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    [[ ! -e "$DISABLED_MARKER" ]] || exit 0

    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            exit 0
        fi
    fi
    printf '%s\n' "$$" > "$PID_FILE"
    trap 'rm -f "$PID_FILE"' EXIT INT TERM

    exec >>"$LOG_FILE" 2>&1
    echo "[$(date '+%F %T')] watcher v${VERSION} iniciado"

    sleep 8
    local previous="" current
    while :; do
        [[ ! -e "$DISABLED_MARKER" ]] || exit 0
        current="$(topology_signature)"
        if [[ "$current" != "$previous" ]]; then
            sleep 2
            current="$(topology_signature)"
            ensure_baseline_backup || true
            if reconcile_plasma; then
                echo "[$(date '+%F %T')] topologia reconciliada: $current"
                previous="$current"
            else
                echo "[$(date '+%F %T')] falha na reconciliação; nova tentativa em 3s"
                # Não marque a topologia como processada: no login o plasmashell
                # pode ainda não estar pronto para evaluateScript.
                previous=""
            fi
        fi
        sleep 3
    done
}

apply_now() {
    check_environment
    make_backup
    reconcile_plasma
    ok "Painéis Plasma reconciliados; cada Task Manager mostra apenas a tela atual."
}

usage() {
    cat <<EOF2
Uso: $(basename "$0") {status|apply|reconcile|watch|enable|disable|restore}
EOF2
}

case "${1:-status}" in
    status) show_state ;;
    apply) apply_now ;;
    reconcile) reconcile_plasma ;;
    watch) watch_loop ;;
    enable) enable_automatic ;;
    disable) disable_automatic ;;
    restore) restore_latest ;;
    *) usage; exit 2 ;;
esac
