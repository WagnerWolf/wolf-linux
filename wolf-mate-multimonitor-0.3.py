#!/usr/bin/env python3
# Wolf Linux - MATE MultiMonitor
# Experimental until validated on real multi-monitor MATE hardware.

import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gio, Gdk

VERSION = "0.3"
STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "wolf-linux" / "mate-multimonitor"
CONFIG_ROOT = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wolf-linux"
ENABLED_MARKER = CONFIG_ROOT / "mate-multimonitor.enabled"
PID_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / f"wolf-mate-multimonitor-{os.getuid()}.pid"
APPLET_DESCRIPTOR = Path("/usr/share/mate-panel/applets/org.wolflinux.panel.WolfMonitorTasks.mate-panel-applet")


def die(msg):
    print(f"[ERRO] {msg}", file=sys.stderr)
    raise SystemExit(1)


def check_env():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", os.environ.get("XDG_SESSION_DESKTOP", ""))
    if "MATE" not in desktop.upper():
        die("Este helper é somente para MATE.")
    if os.environ.get("XDG_SESSION_TYPE", "x11") != "x11":
        die("O Wolf MultiMonitor para MATE foi projetado para X11.")
    if Gdk.Display.get_default() is None:
        die("Não foi possível acessar o display GTK/GDK atual.")
    if not APPLET_DESCRIPTOR.exists():
        die("Wolf Monitor Tasks não está instalado.")


def gdk_monitor_records():
    """Return monitors exactly as GTK/MATE sees them.

    mate-panel places panels by GDK/Xinerama monitor index.  RandR 1.5
    logical monitors created with `xrandr --setmonitor` are not necessarily
    exposed as distinct GdkMonitor objects, so using xrandr here can create
    unusable/overlapping panels.
    """
    display = Gdk.Display.get_default()
    if display is None:
        return []

    records = []
    for idx in range(display.get_n_monitors()):
        mon = display.get_monitor(idx)
        geo = mon.get_geometry()
        records.append({
            "index": idx,
            "x": geo.x,
            "y": geo.y,
            "width": geo.width,
            "height": geo.height,
            "scale": mon.get_scale_factor(),
            "manufacturer": mon.get_manufacturer() or "",
            "model": mon.get_model() or "",
        })
    return records


def gdk_monitors():
    return [m["index"] for m in gdk_monitor_records()]


def topology_signature():
    rows = []
    for m in gdk_monitor_records():
        rows.append(
            f"{m['index']}:{m['width']}x{m['height']}+{m['x']}+{m['y']}"
            f":scale={m['scale']}:{m['manufacturer']}:{m['model']}"
        )
    return "\n".join(rows)


def general_settings():
    return Gio.Settings.new("org.mate.panel")


def toplevel_settings(tid):
    return Gio.Settings.new_with_path("org.mate.panel.toplevel", f"/org/mate/panel/toplevels/{tid}/")


def object_settings(oid):
    return Gio.Settings.new_with_path("org.mate.panel.object", f"/org/mate/panel/objects/{oid}/")


def make_backup():
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = STATE_ROOT / stamp
    dest.mkdir(parents=True, exist_ok=True)
    with (dest / "mate-panel.dconf").open("w") as f:
        subprocess.run(["dconf", "dump", "/org/mate/panel/"], stdout=f, check=True)
    (STATE_ROOT / "latest").write_text(str(dest) + "\n")
    print(f"[OK] Backup salvo em {dest}")
    return dest


def ensure_baseline_backup():
    marker = STATE_ROOT / "automatic-baseline"
    if marker.exists():
        return
    dest = make_backup()
    marker.write_text(str(dest) + "\n")


def set_applet_object(oid, panel_id, iid, pack="start", index=0, position=0):
    s = object_settings(oid)
    # MATE 1.28 (Arch atual) ainda usa position/panel-right-stick.
    # MATE mais novo adicionou pack-type/pack-index. Detectamos as chaves
    # em runtime para o helper funcionar nas duas gerações do schema.
    keys = set(s.list_keys())

    s.set_string("object-type", "applet")
    s.set_string("applet-iid", iid)
    s.set_string("toplevel-id", panel_id)

    if "pack-type" in keys:
        s.set_string("pack-type", pack)
    if "pack-index" in keys:
        s.set_int("pack-index", index)
    if "position" in keys:
        s.set_int("position", position)
    if "panel-right-stick" in keys:
        s.set_boolean("panel-right-stick", pack == "end")
    if "locked" in keys:
        s.set_boolean("locked", True)


def reconcile():
    check_env()
    monitors = gdk_monitors()
    if not monitors:
        die("Nenhum monitor ativo detectado.")

    general = general_settings()
    toplevel_ids = list(general.get_strv("toplevel-id-list"))
    object_ids = list(general.get_strv("object-id-list"))

    panel_by_monitor = {}
    for tid in toplevel_ids:
        try:
            s = toplevel_settings(tid)
            mon = s.get_int("monitor")
            if mon not in panel_by_monitor:
                panel_by_monitor[mon] = tid
        except Exception:
            continue

    created_panels = []
    for mon in monitors:
        if mon in panel_by_monitor:
            continue
        tid = f"wolf-monitor-{mon}"
        suffix = 1
        while tid in toplevel_ids:
            suffix += 1
            tid = f"wolf-monitor-{mon}-{suffix}"
        s = toplevel_settings(tid)
        s.set_string("name", f"Wolf Monitor {mon}")
        s.set_int("screen", 0)
        s.set_int("monitor", mon)
        s.set_boolean("expand", True)
        s.set_string("orientation", "bottom")
        s.set_int("size", 28)
        s.set_boolean("auto-hide", False)
        toplevel_ids.append(tid)
        panel_by_monitor[mon] = tid
        created_panels.append((mon, tid))

    # Remove Window List nativa apenas dos painéis em monitores ativos e
    # substitua pelo applet Wolf, preservando as configurações antigas no dconf.
    active_panels = {panel_by_monitor[m] for m in monitors}
    filtered_objects = []
    for oid in object_ids:
        try:
            s = object_settings(oid)
            iid = s.get_string("applet-iid")
            panel_id = s.get_string("toplevel-id")
        except Exception:
            filtered_objects.append(oid)
            continue
        if panel_id in active_panels and iid == "WnckletFactory::WindowListApplet":
            continue
        filtered_objects.append(oid)
    object_ids = filtered_objects

    def has_iid(panel_id, iid):
        for oid in object_ids:
            try:
                s = object_settings(oid)
                if s.get_string("toplevel-id") == panel_id and s.get_string("applet-iid") == iid:
                    return True
            except Exception:
                pass
        return False

    def add_unique(base):
        oid = base
        n = 1
        while oid in object_ids:
            n += 1
            oid = f"{base}-{n}"
        object_ids.append(oid)
        return oid

    for mon in monitors:
        panel = panel_by_monitor[mon]

        if not has_iid(panel, "BriskMenuFactory::BriskMenu"):
            oid = add_unique(f"wolf-brisk-m{mon}")
            set_applet_object(oid, panel, "BriskMenuFactory::BriskMenu", "start", 0, 0)

        if not has_iid(panel, "WolfMonitorTasksFactory::WolfMonitorTasksApplet"):
            oid = add_unique(f"wolf-tasks-m{mon}")
            set_applet_object(oid, panel, "WolfMonitorTasksFactory::WolfMonitorTasksApplet", "start", 1, 42)

        if not has_iid(panel, "ClockAppletFactory::ClockApplet"):
            oid = add_unique(f"wolf-clock-m{mon}")
            set_applet_object(oid, panel, "ClockAppletFactory::ClockApplet", "end", 0, 42)

        if not has_iid(panel, "WnckletFactory::ShowDesktopApplet"):
            oid = add_unique(f"wolf-showdesktop-m{mon}")
            set_applet_object(oid, panel, "WnckletFactory::ShowDesktopApplet", "end", 1, 0)

    general.set_strv("toplevel-id-list", toplevel_ids)
    general.set_strv("object-id-list", object_ids)
    Gio.Settings.sync()

    for mon, tid in created_panels:
        print(f"Wolf MATE MultiMonitor: painel criado no monitor {mon}: {tid}")


def show_status():
    check_env()
    print(f"Wolf MATE MultiMonitor v{VERSION}")
    print(f"Experimental habilitado: {'sim' if ENABLED_MARKER.exists() else 'não'}")
    records = gdk_monitor_records()
    print("Monitores GTK/GDK:", [m["index"] for m in records])
    for m in records:
        print(f"  GDK {m['index']}: {m['width']}x{m['height']}+{m['x']}+{m['y']} modelo={m['model'] or '?'}")
    g = general_settings()
    for tid in g.get_strv("toplevel-id-list"):
        s = toplevel_settings(tid)
        print(f"  painel {tid}: monitor={s.get_int('monitor')} orientação={s.get_string('orientation')}")
    print("Wolf Monitor Tasks:")
    for oid in g.get_strv("object-id-list"):
        s = object_settings(oid)
        if s.get_string("applet-iid") == "WolfMonitorTasksFactory::WolfMonitorTasksApplet":
            print(f"  {oid} -> {s.get_string('toplevel-id')}")


def stop_watch():
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, signal.SIGTERM)
        except Exception:
            pass
        PID_FILE.unlink(missing_ok=True)


def enable():
    check_env()
    CONFIG_ROOT.mkdir(parents=True, exist_ok=True)
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    ENABLED_MARKER.touch()
    ensure_baseline_backup()
    reconcile()
    subprocess.Popen([sys.argv[0], "watch"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print("[OK] Wolf MultiMonitor experimental para MATE habilitado.")


def disable():
    ENABLED_MARKER.unlink(missing_ok=True)
    stop_watch()
    print("[OK] Wolf MultiMonitor para MATE desativado; painéis existentes foram preservados.")


def restore():
    disable()
    latest = STATE_ROOT / "latest"
    if not latest.exists():
        die("Nenhum backup encontrado.")
    src = Path(latest.read_text().strip()) / "mate-panel.dconf"
    if not src.exists():
        die("Backup inválido.")
    subprocess.run(["dconf", "reset", "-f", "/org/mate/panel/"], check=True)
    with src.open() as f:
        subprocess.run(["dconf", "load", "/org/mate/panel/"], stdin=f, check=True)
    subprocess.Popen(["mate-panel", "--replace"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print("[OK] Configuração MATE restaurada e automação desativada.")


def watch():
    check_env()
    if not ENABLED_MARKER.exists():
        return
    if PID_FILE.exists():
        try:
            old = int(PID_FILE.read_text().strip())
            os.kill(old, 0)
            return
        except Exception:
            pass
    PID_FILE.write_text(str(os.getpid()) + "\n")

    def cleanup(*_):
        PID_FILE.unlink(missing_ok=True)
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)
    time.sleep(8)
    previous = ""
    while ENABLED_MARKER.exists():
        current = topology_signature()
        if current and current != previous:
            time.sleep(2)
            ensure_baseline_backup()
            try:
                reconcile()
            except Exception as exc:
                print(f"Wolf MATE MultiMonitor: {exc}", file=sys.stderr)
            previous = current
        time.sleep(3)
    cleanup()


def apply():
    check_env()
    make_backup()
    reconcile()
    print("[OK] Configuração multi-monitor MATE aplicada.")


def usage():
    print(f"Uso: {Path(sys.argv[0]).name} status|apply|reconcile|enable|disable|restore|watch")


cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
if cmd == "status":
    show_status()
elif cmd == "apply":
    apply()
elif cmd == "reconcile":
    reconcile()
elif cmd == "enable":
    enable()
elif cmd == "disable":
    disable()
elif cmd == "restore":
    restore()
elif cmd == "watch":
    watch()
else:
    usage()
    raise SystemExit(2)
