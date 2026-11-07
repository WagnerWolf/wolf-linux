#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.3.2"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/plasma-multimonitor"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux"
DISABLED_MARKER="$CONFIG_ROOT/plasma-multimonitor.disabled"
PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

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

plasma_eval() {
    local script="$1"
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script"
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
    wait_plasma_ready || die "Plasma ainda não ficou pronto para configurar os painéis."

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

// Existing Kickoff widgets keep their current icon and entire configuration.
// Newly created panels inherit an existing Kickoff icon, or the Wolf SVG.
function findExistingKickoffIcon(existingPanels) {
    for (var i = 0; i < existingPanels.length; i++) {
        var widgets = existingPanels[i].widgets();
        for (var j = 0; j < widgets.length; j++) {
            var w = widgets[j];
            if (w.type !== "org.kde.plasma.kickoff") continue;
            w.currentConfigGroup = ["General"];
            var icon = w.readConfig("icon");
            if (icon) return icon;
        }
    }
    return "/usr/share/icons/hicolor/scalable/apps/wolf-linux-kickoff.svg";
}

// Screen IDs and panel.screen may not agree at the very first login.
// Never treat an unassigned default panel as permission to add another one.
var screens = uniqueScreens();
var allPanels = panels();
if (screens.length === 0) {
    print("WOLF_MM_ERROR: nenhuma tela ativa identificada; tente novamente após o Plasma inicializar");
} else {
    var pendingPanels = allPanels.filter(function(p) {
        return p.screen < 0 || screens.indexOf(p.screen) === -1;
    });
    if (screens.length > 1 && pendingPanels.length > 0) {
        // Deferred assignment is normal during startup; don't mutate that layout.
        print("WOLF_MM_ERROR: painéis ainda sem associação estável às telas; tente novamente em alguns segundos");
    } else {
        var newPanelKickoffIcon = findExistingKickoffIcon(allPanels);
        var panelForScreen = {};
        var created = 0;

        allPanels.forEach(function(p) {
            if (screens.indexOf(p.screen) !== -1 && panelForScreen[p.screen] === undefined) {
                panelForScreen[p.screen] = p;
            }
            makeTasksLocal(p);
        });

        // Single display: an existing panel ALWAYS covers the desktop, even if
        // Plasma temporarily reports p.screen=-1 (or a different numeric ID).
        // Never delete panels: existing duplicates must be handled with restore.
        if (screens.length === 1 && allPanels.length > 0) {
            if (allPanels.length > 1) {
                print("WOLF_MM_WARN: vários painéis existentes em uma tela; nenhum será removido automaticamente");
            }
            print("WOLF_MM_OK: tela única com painel existente; nenhuma criação necessária");
        } else {
            screens.forEach(function(screen) {
                if (panelForScreen[screen] !== undefined) return;

                var panel = new Panel;
                panel.screen = screen;
                panel.location = "bottom";
                panel.height = Math.round(gridUnit * 2.2);

                var kickoff = panel.addWidget("org.kde.plasma.kickoff");
                kickoff.currentConfigGroup = ["General"];
                kickoff.writeConfig("icon", newPanelKickoffIcon);
                kickoff.reloadConfig();

                var tasks = panel.addWidget("org.kde.plasma.icontasks");
                tasks.currentConfigGroup = ["General"];
                tasks.writeConfig("showOnlyCurrentScreen", true);
                tasks.writeConfig("showOnlyCurrentActivity", true);
                tasks.reloadConfig();

                panel.addWidget("org.kde.plasma.panelspacer");
                panel.addWidget("org.kde.plasma.digitalclock");
                panel.addWidget("org.kde.plasma.showdesktop");
                created++;
            });
            print("WOLF_MM_OK: telas=" + screens.length + " painéis novos=" + created);
        }
        panels().forEach(function(p) { makeTasksLocal(p); });
    }
}
JS
    local result
    result="$(plasma_eval "$js")" || die "Falha na comunicação com Plasma Shell."
    if [[ "$result" == *WOLF_MM_ERROR:* ]]; then
        die "$result"
    fi
    [[ "$result" == *WOLF_MM_OK:* ]] || die "Plasma não confirmou a reconciliação: $result"
    log "$result"
}

show_state() {
    check_environment
    echo
    echo "======================================================"
    echo "       WOLF PLASMA MULTIMONITOR v${VERSION}"
    echo "======================================================"
    echo
    if [[ -e "$DISABLED_MARKER" ]]; then
        log "Política de reconciliação Wolf: DESATIVADA"
    else
        log "Política de reconciliação Wolf: HABILITADA"
    fi
    log "Autostart Wolf: somente configuração inicial, se ainda pendente"
    log "Watcher permanente: NÃO (Plasma/KScreen gerencia hotplug nativamente)"
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

disable_automatic() {
    mkdir -p "$CONFIG_ROOT"
    : > "$DISABLED_MARKER"
    ok "Política Wolf desativada; painéis existentes foram preservados."
}

enable_automatic() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    rm -f "$DISABLED_MARKER"
    ensure_baseline_backup
    reconcile_plasma
    ok "Política Wolf habilitada; reconciliação executada sem watcher permanente."
}

restore_latest() {
    check_environment
    [[ -f "$STATE_ROOT/latest" ]] || die "Nenhum backup encontrado."
    local dir
    dir="$(cat "$STATE_ROOT/latest")"
    [[ -f "$dir/plasma-org.kde.plasma.desktop-appletsrc" ]] || die "Backup inválido: $dir"
    disable_automatic >/dev/null
    cp -a "$dir/plasma-org.kde.plasma.desktop-appletsrc" "$PLASMA_CONFIG"
    if systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1; then
        :
    else
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        nohup plasmashell --replace >/dev/null 2>&1 &
    fi
    ok "Layout Plasma restaurado; política Wolf ficou desativada."
}

apply_now() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    if [[ -e "$DISABLED_MARKER" ]]; then
        warn "Reconciliação automática desativada após restore; utilize 'reconcile' para execução manual, ou 'enable' para reativar."
        return 3
    fi
    ensure_baseline_backup
    reconcile_plasma
    ok "Painéis Plasma reconciliados; sem watcher/polling permanente."
}

reconcile_manual() {
    check_environment
    mkdir -p "$STATE_ROOT"
    make_backup
    reconcile_plasma
    ok "Reconciliação manual concluída; política automática não foi alterada."
}

watch_compat() {
    warn "O modo watch foi removido na v${VERSION} para eliminar polling periódico."
    warn "Executando uma reconciliação única; hotplug fica a cargo do Plasma/KScreen."
    apply_now
}

usage() {
    cat <<EOF2
Uso: $(basename "$0") {status|apply|reconcile|watch|enable|disable|restore}
EOF2
}

case "${1:-status}" in
    status) show_state ;;
    apply) apply_now ;;
    reconcile) reconcile_manual ;;
    watch) watch_compat ;;
    enable) enable_automatic ;;
    disable) disable_automatic ;;
    restore) restore_latest ;;
    *) usage; exit 2 ;;
esac
