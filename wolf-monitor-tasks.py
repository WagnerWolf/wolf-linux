#!/usr/bin/env python3
# Wolf Linux - MATE Monitor Tasks
# Lista de janelas limitada ao monitor onde a instância do applet está.

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Wnck", "3.0")
gi.require_version("MatePanelApplet", "4.0")

from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, MatePanelApplet, Pango, Wnck

try:
    Wnck.set_client_type(Wnck.ClientType.PAGER)
except Exception:
    pass


class MonitorTasks:
    def __init__(self, applet):
        self.applet = applet
        self.screen = Wnck.Screen.get_default()
        self.box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.box.set_hexpand(True)
        self.applet.add(self.box)

        try:
            self.applet.set_flags(MatePanelApplet.AppletFlags.EXPAND_MAJOR)
        except Exception:
            pass

        self.applet.connect("realize", self._schedule_refresh)
        self.applet.connect("size-allocate", self._schedule_refresh)

        for signal in ("window-opened", "window-closed", "active-window-changed", "active-workspace-changed"):
            try:
                self.screen.connect(signal, self._schedule_refresh)
            except Exception:
                pass

        self._last_signature = None
        GLib.timeout_add(700, self._poll)
        self.applet.show_all()

    def _schedule_refresh(self, *args):
        GLib.idle_add(self.refresh)

    def _monitor_geometry(self):
        gdk_window = self.applet.get_window()
        if gdk_window is None:
            return None
        display = gdk_window.get_display()
        monitor = display.get_monitor_at_window(gdk_window)
        if monitor is None:
            return None
        return monitor.get_geometry()

    @staticmethod
    def _window_center(window):
        x, y, w, h = window.get_geometry()
        return x + max(w, 1) // 2, y + max(h, 1) // 2

    def _is_on_this_monitor(self, window, geom):
        cx, cy = self._window_center(window)
        return geom.x <= cx < geom.x + geom.width and geom.y <= cy < geom.y + geom.height

    def _visible_windows(self):
        self.screen.force_update()
        geom = self._monitor_geometry()
        if geom is None:
            return []

        workspace = self.screen.get_active_workspace()
        windows = []
        for window in self.screen.get_windows_stacked():
            try:
                if window.is_skip_tasklist():
                    continue
                if workspace is not None and not (window.is_pinned() or window.is_on_workspace(workspace)):
                    continue
                if not self._is_on_this_monitor(window, geom):
                    continue
                windows.append(window)
            except Exception:
                continue
        return windows

    @staticmethod
    def _signature(windows):
        items = []
        for w in windows:
            try:
                items.append((w.get_xid(), w.get_name(), w.is_active(), w.is_minimized(), w.get_geometry()))
            except Exception:
                pass
        return tuple(items)

    def _poll(self):
        try:
            windows = self._visible_windows()
            sig = self._signature(windows)
            if sig != self._last_signature:
                self.refresh(windows)
        except Exception:
            pass
        return True

    def _on_clicked(self, button, window):
        timestamp = Gtk.get_current_event_time()
        try:
            if window.is_active() and not window.is_minimized():
                window.minimize()
            else:
                window.unminimize(timestamp)
                window.activate(timestamp)
        except Exception:
            pass

    def _on_button_press(self, button, event, window):
        if event.button == 2:
            try:
                window.close(getattr(event, "time", Gtk.get_current_event_time()))
            except Exception:
                pass
            return True
        return False

    def _make_button(self, window):
        button = Gtk.Button()
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_can_focus(False)

        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        try:
            icon = window.get_mini_icon()
            if icon is not None:
                if icon.get_width() > 20 or icon.get_height() > 20:
                    icon = icon.scale_simple(20, 20, GdkPixbuf.InterpType.BILINEAR)
                content.pack_start(Gtk.Image.new_from_pixbuf(icon), False, False, 0)
        except Exception:
            pass

        title = window.get_name() or "Aplicativo"
        label_text = title if len(title) <= 26 else title[:23] + "…"
        label = Gtk.Label(label=label_text)
        label.set_ellipsize(Pango.EllipsizeMode.END)
        label.set_max_width_chars(26)
        content.pack_start(label, False, False, 0)

        button.add(content)
        button.set_tooltip_text(title)
        button.connect("clicked", self._on_clicked, window)
        button.connect("button-press-event", self._on_button_press, window)
        return button

    def refresh(self, windows=None):
        if windows is None:
            windows = self._visible_windows()
        self._last_signature = self._signature(windows)

        for child in self.box.get_children():
            self.box.remove(child)
            child.destroy()

        for window in windows:
            self.box.pack_start(self._make_button(window), False, False, 0)

        self.box.show_all()
        return False


def applet_factory(applet, iid, data):
    if iid != "WolfMonitorTasksApplet":
        return False
    MonitorTasks(applet)
    return True


MatePanelApplet.Applet.factory_main(
    "WolfMonitorTasksFactory",
    True,
    MatePanelApplet.Applet.__gtype__,
    applet_factory,
    None,
)
