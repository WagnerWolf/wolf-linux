#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.2"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/multimonitor"
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
    [[ "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* || "${DESKTOP_SESSION:-}" == *cinnamon* ]] \
        || die "Esta versão do helper é somente para Cinnamon."

    [[ "${XDG_SESSION_TYPE:-x11}" == "x11" ]] \
        || die "Esta versão foi projetada para Cinnamon X11."

    need_cmd gsettings
    need_cmd xrandr
    need_cmd python3
}

monitor_lines() {
    xrandr --listmonitors | tail -n +2
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

# Preferimos copiar uma configuração real já usada pelo usuário.
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

apply_cinnamon() {
    check_environment

    local count ids_file
    count="$(xrandr --listmonitors | awk 'NR==1 {print $2}')"
    [[ "$count" =~ ^[0-9]+$ ]] || die "Não consegui determinar o número de monitores."
    (( count >= 2 )) || die "Apenas $count monitor detectado. Nada a configurar."

    # Instalamos/verificamos o applet ANTES do backup estrutural; se o download falhar,
    # os painéis permanecem intocados.
    ensure_cinnvii_installed
    make_backup
    show_monitors

    ids_file="$(mktemp)"

    # O Python faz as alterações estruturais para evitar parsing frágil de arrays GVariant.
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


# Um CinnVII por painel. Se o menu padrão já ocupa a posição, reutilizamos a
# posição e o instance id para evitar mexer no layout do painel.
for monitor, (panel_id, _position) in sorted(panel_by_monitor.items()):
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

    # O CinnVII passa a ser o menu padrão Wolf; removemos menu@cinnamon deste painel.
    prefix = f"panel{panel_id}:"
    applets[:] = [
        item for item in applets
        if not (
            item.startswith(prefix)
            and (parse_entry(item) or {}).get("uuid") == STOCK_MENU_UUID
        )
    ]

    # Cada monitor precisa de sua própria Grouped Window List para o filtro por tela.
    entries = panel_entries(panel_id)
    has_gwl = any(e and e["uuid"] == "grouped-window-list@cinnamon.org" for _, e in entries)
    if not has_gwl:
        add_applet(panel_id, "left", 99, "grouped-window-list@cinnamon.org")

    # Nos painéis criados pelo Wolf adicionamos relógio, sem duplicar tray/rede/volume.
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

print("Painéis novos:")
for monitor, panel_id in new_panels:
    print(f"  monitor {monitor}: panel{panel_id}")
print("Menus CinnVII preparados:")
for instance_id in new_menu_ids:
    print(f"  instância {instance_id}")
PY

    # Dá tempo ao Cinnamon para criar as estruturas de configuração das novas instâncias.
    sleep 2
    copy_menu_settings_to_new_instances "$ids_file"
    rm -f "$ids_file"

    # Com uma lista de janelas em cada monitor, valor 1 equivale ao comportamento
    # desejado: mostrar janelas de outro monitor somente se ele NÃO possuir lista própria.
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
        print(f"Ajustado: {path.name} -> somente monitor próprio")
PY

    if gsettings writable org.cinnamon alttab-switcher-show-current-monitor 2>/dev/null | grep -qx true; then
        gsettings set org.cinnamon alttab-switcher-show-current-monitor true
    fi
    if gsettings writable org.cinnamon alttab-switcher-enforce-primary-monitor 2>/dev/null | grep -qx true; then
        gsettings set org.cinnamon alttab-switcher-enforce-primary-monitor false
    fi

    echo
    ok "Wolf MultiMonitor v${VERSION} aplicado."
    echo "- Cada monitor possui sua própria Grouped Window List."
    echo "- CinnVIIStarkMenu é o menu de cada painel."
    echo "- Painéis secundários mantêm apenas Menu + apps locais + relógio."
    echo "- Alt+Tab acompanha o monitor ativo."
    echo
    warn "Faça Alt+F2 -> r para garantir que as novas instâncias e configurações sejam recarregadas."
    warn "Teste especialmente se o CinnVII aberto no monitor secundário aparece naquela tela e se os apps lançados por ele nascem nela."
}

restore_latest() {
    check_environment
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

    ok "Configuração restaurada."
    warn "Use Alt+F2 -> r se o Cinnamon não atualizar os painéis imediatamente."
}

usage() {
    cat <<EOF2
Uso:
  $(basename "$0") status
  $(basename "$0") apply
  $(basename "$0") restore

Comandos:
  status   Mostra monitores, painéis, menus e listas de janelas.
  apply    Cria/ajusta painéis independentes e usa CinnVIIStarkMenu em cada tela.
  restore  Restaura o último backup feito antes de apply.
EOF2
}

case "${1:-status}" in
    status)  show_state ;;
    apply)   apply_cinnamon ;;
    restore) restore_latest ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
esac
