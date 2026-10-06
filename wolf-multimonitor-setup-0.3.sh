#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.3"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/multimonitor"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux"
DISABLED_MARKER="$CONFIG_ROOT/multimonitor.disabled"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/wolf-multimonitor-${UID}.pid"
LOG_FILE="$BACKUP_ROOT/watch.log"
CINNAMON_CONFIG_DIR="$HOME/.cinnamon/configs"
CINNAMON_SPICES_CONFIG_DIR="$HOME/.config/cinnamon/spices"
APPLETS_DIR="$HOME/.local/share/cinnamon/applets"
MENU_UUID="CinnVIIStarkMenu@NikoKrause"
MENU_DIR="$APPLETS_DIR/$MENU_UUID"
MENU_URL="https://cinnamon-spices.linuxmint.com/files/applets/CinnVIIStarkMenu%40NikoKrause.zip"

log()  { printf '\033[1;34m[Wolf MultiMonitor]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

check_environment() {
    [[ "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* || "${XDG_SESSION_DESKTOP:-}" == *cinnamon* ]] \
        || die "Esta versão do helper é somente para Cinnamon."

    [[ "${XDG_SESSION_TYPE:-x11}" == "x11" ]] \
        || die "Esta versão foi projetada para Cinnamon X11."

    need_cmd gsettings
    need_cmd xrandr
    need_cmd python3
}

monitor_count() {
    xrandr --listmonitors 2>/dev/null | awk 'NR==1 {print $2+0}'
}

monitor_lines() {
    xrandr --listmonitors 2>/dev/null | tail -n +2
}

topology_signature() {
    # O nome do conector + geometria detecta hotplug, resolução e mudanças de posição.
    monitor_lines \
        | sed -E 's/^[[:space:]]*[0-9]+:[[:space:]]*//' \
        | tr '\n' '|'
}

show_monitors() {
    log "Monitores detectados pelo XRandR:"
    monitor_lines | sed 's/^/  /'
}

show_state() {
    check_environment
    echo
    echo "======================================================"
    echo "          WOLF MULTIMONITOR v${VERSION}"
    echo "======================================================"
    echo
    show_monitors
    echo
    if [[ -e "$DISABLED_MARKER" ]]; then
        log "Gerenciamento automático: DESATIVADO"
    else
        log "Gerenciamento automático: ATIVADO"
    fi
    echo
    log "Painéis Cinnamon:"
    gsettings get org.cinnamon panels-enabled
    echo
    log "Alt+Tab somente no monitor atual:"
    gsettings get org.cinnamon alttab-switcher-show-current-monitor 2>/dev/null || true
    echo
    log "Menus por painel:"
    python3 - <<'PY'
import ast, subprocess
raw = subprocess.check_output(["gsettings", "get", "org.cinnamon", "enabled-applets"], text=True).strip()
for item in ast.literal_eval(raw):
    if "menu@cinnamon.org" in item or "CinnVIIStarkMenu@NikoKrause" in item:
        print("  " + item)
PY
    echo
    log "Instâncias de Grouped Window List:"
    python3 - <<'PY'
import ast, subprocess
raw = subprocess.check_output(["gsettings", "get", "org.cinnamon", "enabled-applets"], text=True).strip()
for item in ast.literal_eval(raw):
    if "grouped-window-list@cinnamon.org" in item:
        print("  " + item)
PY
    echo
    if [[ -d "$CINNAMON_CONFIG_DIR/grouped-window-list@cinnamon.org" ]]; then
        log "Configurações de monitor das listas de janelas:"
        python3 - "$CINNAMON_CONFIG_DIR/grouped-window-list@cinnamon.org" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for path in sorted(root.glob("*.json")):
    try:
        data = json.loads(path.read_text())
    except Exception:
        continue
    item = data.get("window-display-settings", {})
    print(f"  instância {path.stem}: window-display-settings={item.get('value', item.get('default', '?'))}")
PY
    fi
}

make_backup() {
    local stamp dir
    stamp="$(date +%Y%m%d-%H%M%S)"
    dir="$BACKUP_ROOT/$stamp"
    mkdir -p "$dir"

    gsettings get org.cinnamon panels-enabled > "$dir/panels-enabled.txt"
    gsettings get org.cinnamon enabled-applets > "$dir/enabled-applets.txt"
    gsettings get org.cinnamon next-applet-id > "$dir/next-applet-id.txt"
    gsettings get org.cinnamon alttab-switcher-show-current-monitor > "$dir/alttab-current-monitor.txt" 2>/dev/null || true
    gsettings get org.cinnamon alttab-switcher-enforce-primary-monitor > "$dir/alttab-primary-monitor.txt" 2>/dev/null || true

    if [[ -d "$CINNAMON_CONFIG_DIR" ]]; then
        cp -a "$CINNAMON_CONFIG_DIR" "$dir/configs"
    fi
    if [[ -d "$CINNAMON_SPICES_CONFIG_DIR" ]]; then
        cp -a "$CINNAMON_SPICES_CONFIG_DIR" "$dir/spices"
    fi

    printf '%s\n' "$dir" > "$BACKUP_ROOT/latest"
    ok "Backup salvo em $dir"
}

ensure_baseline_backup() {
    local marker="$BACKUP_ROOT/automatic-baseline"
    [[ -f "$marker" ]] && return 0

    mkdir -p "$BACKUP_ROOT"
    make_backup
    cp "$BACKUP_ROOT/latest" "$marker"
}

ensure_cinnvii_installed() {
    [[ -d "$MENU_DIR" ]] && return 0

    need_cmd curl
    need_cmd unzip

    log "CinnVIIStarkMenu não está instalado; baixando do Cinnamon Spices oficial..."
    local tmpdir archive
    tmpdir="$(mktemp -d)"
    archive="$tmpdir/cinnvii.zip"

    if ! curl -fL --retry 3 --connect-timeout 10 "$MENU_URL" -o "$archive"; then
        rm -rf "$tmpdir"
        die "Falha ao baixar CinnVIIStarkMenu. Nenhuma configuração de painel foi alterada."
    fi

    mkdir -p "$APPLETS_DIR"
    unzip -q -o "$archive" -d "$APPLETS_DIR"
    rm -rf "$tmpdir"

    [[ -d "$MENU_DIR" ]] || die "CinnVIIStarkMenu foi baixado, mas não apareceu em $MENU_DIR"
    ok "CinnVIIStarkMenu instalado."
}

copy_menu_settings_to_new_instances() {
    local ids_file="$1"
    local root="$CINNAMON_SPICES_CONFIG_DIR/$MENU_UUID"
    [[ -s "$ids_file" ]] || return 0

    mkdir -p "$root"

    python3 - "$root" "$ids_file" <<'PY'
import json
import pathlib
import shutil
import sys

root = pathlib.Path(sys.argv[1])
ids_file = pathlib.Path(sys.argv[2])
new_ids = [x.strip() for x in ids_file.read_text().splitlines() if x.strip().isdigit()]
if not new_ids:
    raise SystemExit(0)

source = None
for path in sorted(root.glob("*.json")):
    try:
        json.loads(path.read_text())
    except Exception:
        continue
    source = path
    break

if source is None:
    print("Nenhuma configuração CinnVII existente para clonar; novas instâncias usarão os padrões do applet.")
    raise SystemExit(0)

for instance_id in new_ids:
    target = root / f"{instance_id}.json"
    if target.exists():
        continue
    shutil.copy2(source, target)
    print(f"Configuração CinnVII clonada: {source.name} -> {target.name}")
PY
}

reconcile_cinnamon() {
    check_environment

    local count ids_file
    count="$(monitor_count)"
    [[ "$count" =~ ^[0-9]+$ ]] || die "Não consegui determinar o número de monitores."
    (( count >= 1 )) || die "Nenhum monitor ativo detectado."

    # Na ISO o CinnVII já vem instalado. No helper manual, tentamos obtê-lo se faltar.
    ensure_cinnvii_installed

    ids_file="$(mktemp)"

    python3 - "$ids_file" <<'PY'
import ast
import subprocess
import sys

MENU_UUID = "CinnVIIStarkMenu@NikoKrause"
STOCK_MENU_UUID = "menu@cinnamon.org"
NEW_IDS_FILE = sys.argv[1]


def gget(schema, key):
    return subprocess.check_output(["gsettings", "get", schema, key], text=True).strip()


def gset(schema, key, value):
    subprocess.run(["gsettings", "set", schema, key, value], check=True)


def parse_entry(item):
    parts = item.split(":")
    if len(parts) < 5 or not parts[0].startswith("panel"):
        return None
    try:
        panel_id = int(parts[0][5:])
        pos = int(parts[2])
        instance_id = int(parts[-1])
    except ValueError:
        return None
    return {
        "panel_id": panel_id,
        "zone": parts[1],
        "pos": pos,
        "uuid": ":".join(parts[3:-1]),
        "instance_id": instance_id,
    }


out = subprocess.check_output(["xrandr", "--listmonitors"], text=True).splitlines()[1:]
monitors = []
for line in out:
    idx = int(line.strip().split(":", 1)[0])
    monitors.append(idx)

panels = ast.literal_eval(gget("org.cinnamon", "panels-enabled"))
applets = ast.literal_eval(gget("org.cinnamon", "enabled-applets"))
next_applet = int(gget("org.cinnamon", "next-applet-id"))

panel_by_monitor = {}
max_panel_id = 0
for definition in panels:
    try:
        panel_id_s, monitor_s, position = definition.split(":", 2)
        panel_id = int(panel_id_s)
        monitor = int(monitor_s)
    except ValueError:
        continue
    max_panel_id = max(max_panel_id, panel_id)
    if monitor not in panel_by_monitor or position == "bottom":
        panel_by_monitor[monitor] = (panel_id, position)

new_panels = []
for monitor in monitors:
    if monitor in panel_by_monitor:
        continue
    max_panel_id += 1
    panels.append(f"{max_panel_id}:{monitor}:bottom")
    panel_by_monitor[monitor] = (max_panel_id, "bottom")
    new_panels.append((monitor, max_panel_id))

new_menu_ids = []


def panel_entries(panel_id):
    prefix = f"panel{panel_id}:"
    return [(i, parse_entry(item)) for i, item in enumerate(applets) if item.startswith(prefix)]


def add_applet(panel_id, zone, pos, uuid):
    global next_applet
    applets.append(f"panel{panel_id}:{zone}:{pos}:{uuid}:{next_applet}")
    created = next_applet
    next_applet += 1
    return created


# A reconciliação é aditiva: nunca removemos painéis de monitores ausentes.
# Isso preserva personalizações quando uma tela é desligada temporariamente.
for monitor in monitors:
    panel_id, _position = panel_by_monitor[monitor]
    entries = panel_entries(panel_id)
    has_cinnvii = any(e and e["uuid"] == MENU_UUID for _, e in entries)

    if not has_cinnvii:
        stock = [(idx, e) for idx, e in entries if e and e["uuid"] == STOCK_MENU_UUID]
        if stock:
            idx, e = stock[0]
            applets[idx] = f"panel{panel_id}:{e['zone']}:{e['pos']}:{MENU_UUID}:{e['instance_id']}"
            new_menu_ids.append(e["instance_id"])
        else:
            new_id = add_applet(panel_id, "left", 0, MENU_UUID)
            new_menu_ids.append(new_id)

    # CinnVII é o menu padrão Wolf nos painéis gerenciados/ativos.
    prefix = f"panel{panel_id}:"
    applets[:] = [
        item for item in applets
        if not (
            item.startswith(prefix)
            and (parse_entry(item) or {}).get("uuid") == STOCK_MENU_UUID
        )
    ]

    entries = panel_entries(panel_id)
    has_gwl = any(e and e["uuid"] == "grouped-window-list@cinnamon.org" for _, e in entries)
    if not has_gwl:
        add_applet(panel_id, "left", 99, "grouped-window-list@cinnamon.org")

    # Painéis criados pelo Wolf recebem relógio. Em painéis já existentes,
    # preservamos integralmente a composição escolhida pelo usuário.
    if any(pid == panel_id for _mon, pid in new_panels):
        entries = panel_entries(panel_id)
        has_calendar = any(e and e["uuid"] == "calendar@cinnamon.org" for _, e in entries)
        if not has_calendar:
            add_applet(panel_id, "right", 0, "calendar@cinnamon.org")


def gv_array(items):
    def esc(s):
        return s.replace("\\", "\\\\").replace("'", "\\'")
    return "[" + ", ".join("'" + esc(x) + "'" for x in items) + "]"


gset("org.cinnamon", "panels-enabled", gv_array(panels))
gset("org.cinnamon", "enabled-applets", gv_array(applets))
gset("org.cinnamon", "next-applet-id", str(next_applet))

with open(NEW_IDS_FILE, "w", encoding="utf-8") as f:
    for instance_id in new_menu_ids:
        f.write(f"{instance_id}\n")

for monitor, panel_id in new_panels:
    print(f"Wolf MultiMonitor: painel criado no monitor {monitor}: panel{panel_id}")
PY

    # Cinnamon cria o JSON da nova instância de forma assíncrona.
    sleep 1
    copy_menu_settings_to_new_instances "$ids_file"
    rm -f "$ids_file"

    # Valor 1 = janelas de outros monitores somente se eles não tiverem lista própria.
    # Como o Wolf garante uma lista em cada monitor ativo, cada painel fica local.
    python3 - "$CINNAMON_CONFIG_DIR/grouped-window-list@cinnamon.org" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
if not root.exists():
    raise SystemExit(0)
for path in root.glob("*.json"):
    try:
        data = json.loads(path.read_text())
    except Exception:
        continue
    entry = data.get("window-display-settings")
    if isinstance(entry, dict) and entry.get("value") != 1:
        entry["value"] = 1
        path.write_text(json.dumps(data, ensure_ascii=False, indent=4) + "\n")
        print(f"Wolf MultiMonitor: {path.name} -> lista local ao monitor")
PY

    if gsettings writable org.cinnamon alttab-switcher-show-current-monitor 2>/dev/null | grep -qx true; then
        gsettings set org.cinnamon alttab-switcher-show-current-monitor true
    fi
    if gsettings writable org.cinnamon alttab-switcher-enforce-primary-monitor 2>/dev/null | grep -qx true; then
        gsettings set org.cinnamon alttab-switcher-enforce-primary-monitor false
    fi
}

apply_cinnamon() {
    check_environment
    ensure_cinnvii_installed
    make_backup
    reconcile_cinnamon
    echo
    ok "Wolf MultiMonitor v${VERSION} aplicado."
    echo "- Um painel funcional é garantido em cada monitor ativo."
    echo "- CinnVIIStarkMenu é o menu de cada painel."
    echo "- Grouped Window List fica limitada ao próprio monitor."
    echo "- Alt+Tab acompanha o monitor ativo."
    echo
    warn "Se o Cinnamon não redesenhar imediatamente, use Alt+F2 -> r."
}

restore_latest() {
    check_environment
    disable_automatic true

    [[ -f "$BACKUP_ROOT/latest" ]] || die "Nenhum backup criado pelo Wolf MultiMonitor foi encontrado."
    local dir
    dir="$(cat "$BACKUP_ROOT/latest")"
    [[ -d "$dir" ]] || die "Backup não encontrado: $dir"

    log "Restaurando $dir"
    gsettings set org.cinnamon panels-enabled "$(cat "$dir/panels-enabled.txt")"
    gsettings set org.cinnamon enabled-applets "$(cat "$dir/enabled-applets.txt")"
    gsettings set org.cinnamon next-applet-id "$(cat "$dir/next-applet-id.txt")"

    if [[ -s "$dir/alttab-current-monitor.txt" ]]; then
        gsettings set org.cinnamon alttab-switcher-show-current-monitor "$(cat "$dir/alttab-current-monitor.txt")"
    fi
    if [[ -s "$dir/alttab-primary-monitor.txt" ]]; then
        gsettings set org.cinnamon alttab-switcher-enforce-primary-monitor "$(cat "$dir/alttab-primary-monitor.txt")"
    fi

    if [[ -d "$dir/configs" ]]; then
        rm -rf "$CINNAMON_CONFIG_DIR"
        mkdir -p "$(dirname "$CINNAMON_CONFIG_DIR")"
        cp -a "$dir/configs" "$CINNAMON_CONFIG_DIR"
    fi
    if [[ -d "$dir/spices" ]]; then
        rm -rf "$CINNAMON_SPICES_CONFIG_DIR"
        mkdir -p "$(dirname "$CINNAMON_SPICES_CONFIG_DIR")"
        cp -a "$dir/spices" "$CINNAMON_SPICES_CONFIG_DIR"
    fi

    ok "Configuração restaurada; gerenciamento automático foi desativado."
    warn "Use Alt+F2 -> r se o Cinnamon não atualizar os painéis imediatamente."
    echo "Para reativar depois: $(basename "$0") enable"
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
    local quiet="${1:-false}"
    mkdir -p "$CONFIG_ROOT"
    : > "$DISABLED_MARKER"
    stop_watcher
    [[ "$quiet" == true ]] || ok "Wolf MultiMonitor automático desativado. Painéis atuais foram preservados."
}

enable_automatic() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$BACKUP_ROOT"
    rm -f "$DISABLED_MARKER"
    ensure_baseline_backup
    reconcile_cinnamon

    if [[ -n "${DISPLAY:-}" ]]; then
        nohup "$0" watch >/dev/null 2>&1 &
    fi

    ok "Wolf MultiMonitor automático ativado."
}

watch_loop() {
    check_environment
    mkdir -p "$BACKUP_ROOT" "$CONFIG_ROOT"

    [[ ! -e "$DISABLED_MARKER" ]] || exit 0

    # Uma única instância por sessão.
    if [[ -f "$PID_FILE" ]]; then
        old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            exit 0
        fi
    fi
    printf '%s\n' "$$" > "$PID_FILE"
    trap 'rm -f "$PID_FILE"' EXIT INT TERM

    # Evita crescimento ilimitado do log.
    if [[ -f "$LOG_FILE" ]] && (( $(wc -c < "$LOG_FILE") > 524288 )); then
        tail -c 262144 "$LOG_FILE" > "$LOG_FILE.tmp" || true
        mv -f "$LOG_FILE.tmp" "$LOG_FILE"
    fi

    exec >>"$LOG_FILE" 2>&1
    echo "[$(date '+%F %T')] watcher v${VERSION} iniciado"

    # Cinnamon/painéis precisam terminar a inicialização da sessão primeiro.
    sleep 8
    [[ ! -e "$DISABLED_MARKER" ]] || exit 0

    local previous current count
    previous=""

    while :; do
        [[ ! -e "$DISABLED_MARKER" ]] || exit 0

        current="$(topology_signature)"
        if [[ -n "$current" && "$current" != "$previous" ]]; then
            # RandR pode emitir várias mudanças durante um único hotplug.
            sleep 2
            current="$(topology_signature)"
            count="$(monitor_count)"

            echo "[$(date '+%F %T')] topologia alterada: ${count} monitor(es): $current"

            if [[ "$count" =~ ^[0-9]+$ ]] && (( count >= 2 )); then
                ensure_baseline_backup || true
            fi

            if reconcile_cinnamon; then
                echo "[$(date '+%F %T')] reconciliação concluída"
            else
                echo "[$(date '+%F %T')] reconciliação falhou; nova tentativa ocorrerá na próxima mudança/login"
            fi
            previous="$current"
        fi

        sleep 3
    done
}

usage() {
    cat <<EOF2
Uso:
  $(basename "$0") status
  $(basename "$0") apply
  $(basename "$0") reconcile
  $(basename "$0") watch
  $(basename "$0") enable
  $(basename "$0") disable
  $(basename "$0") restore

Comandos:
  status     Mostra monitores, painéis, menus e listas de janelas.
  apply      Faz backup e aplica/repara a configuração multi-monitor agora.
  reconcile  Repara de forma idempotente sem criar novo backup.
  watch      Monitora mudanças de topologia e configura monitores adicionados.
  enable     Ativa o gerenciamento automático e inicia o watcher nesta sessão.
  disable    Desativa o watcher sem apagar os painéis existentes.
  restore    Restaura o último backup e desativa o gerenciamento automático.
EOF2
}

case "${1:-status}" in
    status)    show_state ;;
    apply)     apply_cinnamon ;;
    reconcile) reconcile_cinnamon ;;
    watch)     watch_loop ;;
    enable)    enable_automatic ;;
    disable)   disable_automatic ;;
    restore)   restore_latest ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
esac
