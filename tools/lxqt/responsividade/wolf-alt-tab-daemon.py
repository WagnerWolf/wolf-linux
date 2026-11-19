#!/usr/bin/env python3
"""Wolf LXQt Alt+Tab 0.3: um Tk residente, cache EWMH dirigido por eventos.

Sem polling periódico de monitores/janelas. O atalho Openbox envia NEXT/PREV
por socket local; XGrabKeyboard recebe Tab e AltRelease durante o seletor.
"""
from __future__ import annotations
import argparse
import fcntl
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import threading
import tkinter as tk
from Xlib import X, XK, Xatom, display, protocol

from wolf_alt_common import lock_path, socket_path
from wolf_alt_core import choose_candidates, excluded_by_metadata, load_window_icon, monitors, record_pointer_clicks

LOG = Path.home() / '.cache/wolf-alt-tab-daemon.log'


def log(msg):
    try:
        LOG.parent.mkdir(exist_ok=True, parents=True)
        with LOG.open('a', encoding='utf-8') as f:
            f.write(msg + '\n')
    except OSError:
        pass


def activate_x11(dpy, root, wid, atom):
    """Pedido EWMH direto ao Openbox, sem criar subprocesso wmctrl."""
    ev = protocol.event.ClientMessage(
        window=wid, client_type=atom,
        data=(32, [2, X.CurrentTime, 0, 0, 0]))
    root.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
    dpy.flush()


class Catalog:
    """Cache atualizado por notificações EWMH/ConfigureNotify, não por timer."""
    def __init__(self, dpy):
        self.dpy = dpy
        self.root = dpy.screen().root
        keys = ('_NET_CLIENT_LIST_STACKING', '_NET_CLIENT_LIST', '_NET_ACTIVE_WINDOW',
                '_NET_CURRENT_DESKTOP', '_NET_WM_DESKTOP', '_NET_WM_WINDOW_TYPE',
                '_NET_WM_STATE', '_NET_WM_STATE_SKIP_TASKBAR', '_NET_WM_NAME',
                '_NET_WM_WINDOW_TYPE_DESKTOP', '_NET_WM_WINDOW_TYPE_DOCK',
                '_NET_WM_WINDOW_TYPE_TOOLTIP', '_NET_WM_WINDOW_TYPE_NOTIFICATION',
                'UTF8_STRING')
        self.a = {k: dpy.intern_atom(k) for k in keys}
        self.blocked = {self.a[k] for k in (
            '_NET_WM_WINDOW_TYPE_DESKTOP', '_NET_WM_WINDOW_TYPE_DOCK',
            '_NET_WM_WINDOW_TYPE_TOOLTIP', '_NET_WM_WINDOW_TYPE_NOTIFICATION')}
        self.clients = {}
        self.stack = []
        self.active = 0
        self.desktop = 0
        self.monitor_list = []
        self._read_monitors()
        self.root.change_attributes(event_mask=X.PropertyChangeMask)
        self.refresh_all()
        self.randr_event_base = None
        if dpy.has_extension('RANDR'):
            try:
                from Xlib.ext import randr
                randr.select_input(self.root, randr.RRScreenChangeNotifyMask |
                                   randr.RROutputChangeNotifyMask |
                                   randr.RRCrtcChangeNotifyMask)
                self.randr_event_base = dpy.query_extension('RANDR').first_event
            except Exception as err:
                log('RandR sem notificação: ' + str(err))

    def _read_monitors(self):
        try:
            text = subprocess.check_output(['xrandr', '--listmonitors'],
                                           text=True, timeout=2, stderr=subprocess.DEVNULL)
            self.monitor_list = monitors(text)
        except (OSError, subprocess.SubprocessError):
            geo = self.root.get_geometry()
            self.monitor_list = [(0, 0, geo.width, geo.height)]

    def number(self, name, typ, default=0):
        prop = self.root.get_full_property(self.a[name], typ)
        return int(prop.value[0]) if prop is not None and len(prop.value) else default

    def read_one(self, wid):
        try:
            win = self.dpy.create_resource_object('window', wid)
            wmclass = win.get_wm_class()
            if not wmclass:
                return None
            cls = '.'.join(str(x) for x in wmclass if x)
            typ = win.get_full_property(self.a['_NET_WM_WINDOW_TYPE'], Xatom.ATOM)
            state = win.get_full_property(self.a['_NET_WM_STATE'], Xatom.ATOM)
            if typ is not None and self.blocked.intersection(map(int, typ.value)):
                return None
            if state is not None and self.a['_NET_WM_STATE_SKIP_TASKBAR'] in state.value:
                return None
            geom = win.get_geometry()
            if geom.width <= 0 or geom.height <= 0:
                return None
            pos = self.root.translate_coords(win, 0, 0)
            dp = win.get_full_property(self.a['_NET_WM_DESKTOP'], Xatom.CARDINAL)
            desk = int(dp.value[0]) if dp is not None and len(dp.value) else self.desktop
            if desk == 0xffffffff:
                desk = -1
            titlep = win.get_full_property(self.a['_NET_WM_NAME'], self.a['UTF8_STRING'])
            if titlep is None:
                title = win.get_wm_name() or cls
            else:
                v = titlep.value
                title = v.decode('utf-8', 'replace') if isinstance(v, bytes) else bytes(v).decode('utf-8', 'replace')
            info = dict(id=wid, desktop=desk, x=pos.x, y=pos.y,
                        w=geom.width, h=geom.height, wmclass=cls,
                        icon=cls.split('.')[0], title=str(title).strip())
            return info if not excluded_by_metadata(info) else None
        except Exception:
            return None  # janela fechada enquanto era consultada

    def refresh_all(self):
        self.desktop = self.number('_NET_CURRENT_DESKTOP', Xatom.CARDINAL)
        self.active = self.number('_NET_ACTIVE_WINDOW', Xatom.WINDOW)
        prop = self.root.get_full_property(self.a['_NET_CLIENT_LIST_STACKING'], Xatom.WINDOW)
        if prop is None:
            prop = self.root.get_full_property(self.a['_NET_CLIENT_LIST'], Xatom.WINDOW)
        stack = [int(i) for i in prop.value] if prop is not None else []
        self.stack = stack
        old = self.clients
        new = {}
        for wid in stack:
            if wid in old:
                # Empilhamento mudou, mas metadados e geometria já estão em cache.
                new[wid] = old[wid]
                continue
            try:
                win = self.dpy.create_resource_object('window', wid)
                win.change_attributes(event_mask=X.PropertyChangeMask | X.StructureNotifyMask)
            except Exception:
                continue
            info = self.read_one(wid)
            if info is not None:
                new[wid] = info
        self.clients = new

    def refresh_one(self, wid):
        if wid not in self.stack:
            return
        info = self.read_one(wid)
        if info is None:
            self.clients.pop(wid, None)
        else:
            self.clients[wid] = info

    def get_choices(self):
        ptr = self.root.query_pointer()
        x, y = int(ptr.root_x), int(ptr.root_y)
        idx, entries = choose_candidates(
            self.monitor_list, (x, y), list(self.clients.values()),
            self.desktop, self.active, self.stack)
        # Copy entry data; client cache may update while popup is open.
        return idx, [dict(w) for w in entries]


class Popup:
    """Uma única instância Tk com interface visual idêntica à Preview 2."""
    def __init__(self, gui, dpy, cat):
        self.gui, self.dpy, self.cat = gui, dpy, cat
        self.active = False
        self.grabbed = False
        self.choices = []
        self.buttons = []
        self.icons = {}
        self.selected = 0
        self.epoch = 0
        self.bounds = (0, 0, 0, 0)
        self.keys = {}
        for name, names in dict(
                alt=['Alt_L', 'Alt_R'], tab=['Tab'], escape=['Escape'],
                enter=['Return', 'KP_Enter'], down=['Down'], up=['Up']).items():
            self.keys[name] = {dpy.keysym_to_keycode(XK.string_to_keysym(n)) for n in names}
        gui.overrideredirect(True)
        gui.wm_attributes('-topmost', True)
        gui.configure(bg='#5aa0df')
        gui.withdraw()
        self.panel = tk.Frame(gui, bg='#121c29', padx=12, pady=12)
        self.panel.pack(fill='both', expand=True, padx=2, pady=2)
        self.heading = tk.Label(self.panel, text='JANELAS · MONITOR 1', bg='#121c29',
                                fg='#a9c7e8', font=('Noto Sans', 10, 'bold'), anchor='w')
        self.heading.pack(fill='x', padx=8, pady=(0, 9))
        frame = tk.Frame(self.panel, bg='#121c29')
        frame.pack(fill='both', expand=True)
        self.canvas = tk.Canvas(frame, bg='#121c29', borderwidth=0, highlightthickness=0)
        self.canvas.pack(fill='both', expand=True)
        self.listing = tk.Frame(self.canvas, bg='#121c29')
        self.canvas.create_window((0, 0), window=self.listing, anchor='nw', tags='listing')
        self.listing.bind('<Configure>', lambda _e: self.canvas.configure(scrollregion=self.canvas.bbox('all')))
        self.canvas.bind('<Configure>', lambda e: self.canvas.itemconfigure('listing', width=e.width))
        tk.Label(self.panel, text='Alt + Tab: avançar   ·   Soltar Alt: selecionar   ·   Esc: cancelar',
                 bg='#121c29', fg='#88a3bd', font=('Noto Sans', 9)).pack(fill='x', pady=(8, 0))

        def scroll_list(ev):
            if not self.active:
                return
            num = getattr(ev, 'num', None)
            delta = getattr(ev, 'delta', 0)
            step = -1 if num == 4 or delta > 0 else 1
            self.canvas.yview_scroll(step, 'units')
            return 'break'
        gui.bind_all('<MouseWheel>', scroll_list)
        gui.bind_all('<Button-4>', scroll_list)
        gui.bind_all('<Button-5>', scroll_list)
        gui.bind('<Escape>', lambda _e: self.finish(False))

    def key_down(self, k):
        if not k:
            return False
        data = self.dpy.query_keymap()
        return bool(data[k // 8] & (1 << (k % 8)))

    def alt_down(self):
        return any(self.key_down(k) for k in self.keys['alt'])

    def request(self, reverse=False):
        if self.active:
            self.advance(-1 if reverse else 1)
            return
        idx, choices = self.cat.get_choices()
        if idx is None or not choices:
            return
        # Alt+Tab rápido: a tecla já foi solta antes da entrega do IPC.
        # Alterna diretamente, sem criar popup desnecessário nem atrasar o foco.
        if not self.alt_down():
            if len(choices) > 1:
                target = choices[-1] if reverse else choices[0]
                activate_x11(self.dpy, self.cat.root, target['id'], self.cat.a['_NET_ACTIVE_WINDOW'])
            return
        self.choices = choices
        self.selected = len(choices) - 1 if reverse and len(choices) > 1 else 0
        self.epoch += 1
        epoch = self.epoch
        mon = self.cat.monitor_list[idx]
        x, y, mw, mh = mon
        width = min(620, max(340, mw - 80))
        height = min(mh - 40, 90 + min(8, len(choices)) * 59 + 18)
        posx, posy = x + (mw - width) // 2, y + (mh - height) // 2
        self.bounds = (posx, posy, width, height)
        self.gui.geometry(f'{width}x{height}{posx:+d}{posy:+d}')
        self.heading.configure(text=f'JANELAS · MONITOR {idx + 1}')
        for child in self.listing.winfo_children():
            child.destroy()
        self.buttons.clear()
        for i, w in enumerate(choices):
            cls = w['wmclass'].split('.')[0]
            label = f"  {w['title'][:62] or cls}     ·     {cls[:20]}"
            b = tk.Button(self.listing, text=label, image='', compound='left',
                          justify='left', anchor='w', relief='flat', bd=0,
                          bg='#1b2b3d', fg='#e6f0fc', activebackground='#4076a9',
                          activeforeground='#ffffff', cursor='hand2',
                          font=('Noto Sans', 11), pady=12,
                          command=lambda n=i: self.click(n))
            b.pack(fill='x', pady=3)
            if w['id'] in self.icons and self.icons[w['id']] is not None:
                b.configure(image=self.icons[w['id']])
            self.buttons.append(b)
        self.active = True
        self.gui.deiconify()
        self.gui.lift()
        self.redraw()
        # Captura antes de carregar ícones novos.
        grab = self.cat.root.grab_keyboard(False, X.GrabModeAsync, X.GrabModeAsync, X.CurrentTime)
        self.grabbed = (getattr(grab, 'status', grab) == X.GrabSuccess)
        if not self.grabbed:
            log('XGrabKeyboard não disponível: cancelar popup para não deixá-lo preso')
            self.finish(False)
            return
        # Consultar apenas UMA vez caso Alt já tenha sido solto durante a montagem.
        self.gui.after_idle(lambda: self.quick_release(epoch))
        self.gui.after_idle(lambda: self.fill_icon(epoch, 0))

    def quick_release(self, epoch):
        if self.active and epoch == self.epoch and not self.alt_down():
            self.finish(True)

    def fill_icon(self, epoch, index):
        if not self.active or self.epoch != epoch or index >= len(self.choices):
            return
        w = self.choices[index]
        if w['id'] not in self.icons:
            self.icons[w['id']] = load_window_icon(tk, self.dpy, w, self.icons)
        img = self.icons.get(w['id'])
        if img is not None and index < len(self.buttons):
            self.buttons[index].configure(image=img)
        if index + 1 < len(self.choices):
            self.gui.after(5, lambda: self.fill_icon(epoch, index + 1))

    def redraw(self):
        if not self.buttons:
            return
        for i, b in enumerate(self.buttons):
            selected = i == self.selected
            b.configure(bg='#32608a' if selected else '#1b2b3d',
                        activebackground='#4076a9', fg='#ffffff' if selected else '#e6f0fc')
        self.gui.update_idletasks()
        scroll = self.canvas.bbox('all') or (0, 0, 0, 0)
        height = max(1, scroll[3] - scroll[1])
        top = self.buttons[self.selected].winfo_y()
        bottom = top + self.buttons[self.selected].winfo_height()
        visible = self.canvas.canvasy(0)
        viewport = max(1, self.canvas.winfo_height())
        if top < visible:
            self.canvas.yview_moveto(max(0, top / height))
        elif bottom > visible + viewport:
            self.canvas.yview_moveto(min(1, max(0, bottom - viewport) / height))

    def advance(self, step):
        if self.active and self.choices:
            self.selected = (self.selected + step) % len(self.choices)
            self.redraw()

    def click(self, idx):
        if self.active and 0 <= idx < len(self.choices):
            self.selected = idx
            self.finish(True)

    def finish(self, confirm):
        if not self.active:
            return
        wid = self.choices[self.selected]['id'] if confirm else None
        self.active = False
        self.epoch += 1
        if self.grabbed:
            try:
                self.dpy.ungrab_keyboard(X.CurrentTime)
                self.dpy.flush()
            except Exception:
                pass
        self.grabbed = False
        self.gui.withdraw()
        if wid is not None:
            try:
                activate_x11(self.dpy, self.cat.root, wid, self.cat.a['_NET_ACTIVE_WINDOW'])
            except Exception as exc:
                log('Falha EWMH: ' + str(exc))

    def key_event(self, ev):
        if not self.active:
            return
        if ev.type == X.KeyPress:
            if ev.detail in self.keys['tab'] or ev.detail in self.keys['up'] or ev.detail in self.keys['down']:
                back = ev.detail in self.keys['up'] or (ev.detail in self.keys['tab'] and bool(ev.state & X.ShiftMask))
                self.advance(-1 if back else 1)
            elif ev.detail in self.keys['escape']:
                self.finish(False)
            elif ev.detail in self.keys['enter']:
                self.finish(True)
        elif ev.type == X.KeyRelease and ev.detail in self.keys['alt']:
            if not self.alt_down():
                self.finish(True)

    def pointer_click(self, px, py):
        if not self.active:
            return
        x, y, w, h = self.bounds
        if not (x <= px < x + w and y <= py < y + h):
            self.finish(False)


class Service:
    def __init__(self, sock):
        self.sock = sock
        self.gui = tk.Tk()
        self.dpy = display.Display()
        self.cat = Catalog(self.dpy)
        self.popup = Popup(self.gui, self.dpy, self.cat)
        self.pending_all = False
        self.pending_clients = set()
        self.pending_monitors = False
        self.refresh_pending = False
        self.incoming = {}  # fd -> (conexão, buffer); nunca bloquear esperando IPC
        self.gui.tk.createfilehandler(self.sock.fileno(), tk.READABLE, self.on_socket)
        self.gui.tk.createfilehandler(self.dpy.fileno(), tk.READABLE, self.on_x11)
        self.click_r, self.click_w = os.pipe()
        os.set_blocking(self.click_r, False)
        os.set_blocking(self.click_w, False)
        self.click_data = b''
        self.gui.tk.createfilehandler(self.click_r, tk.READABLE, self.on_click)
        self.click_watcher = self.begin_click_watcher()

    def begin_click_watcher(self):
        # Um único contexto RECORD para toda a vida da sessão, não um por popup.
        popup = self.popup
        fd = self.click_w
        class Sink:
            def put_nowait(self, coords):
                if not popup.active:
                    return
                try:
                    os.write(fd, struct.pack('!ii', *coords))
                except (OSError, BlockingIOError):
                    pass
        def worker():
            try:
                record_pointer_clicks(Sink(), threading.Event())
            except Exception as exc:
                log('XRecord indisponível: ' + str(exc))
        thread = threading.Thread(target=worker, daemon=True, name='wolf-alt-tab-clicks')
        thread.start()
        return thread

    def on_socket(self, _fd, _mask):
        # Aceita somente quando o socket está pronto; não pressupõe que o
        # cliente já tenha enviado bytes (evita perder Alt+Tab por corrida).
        while True:
            try:
                conn, _addr = self.sock.accept()
                conn.setblocking(False)
            except BlockingIOError:
                return
            except OSError:
                return
            fd = conn.fileno()
            self.incoming[fd] = (conn, bytearray())
            self.gui.tk.createfilehandler(fd, tk.READABLE, self.on_client)

    def on_client(self, fd, _mask):
        entry = self.incoming.get(fd)
        if entry is None:
            return
        conn, buffer = entry
        try:
            part = conn.recv(64)
        except BlockingIOError:
            return
        except OSError:
            part = b''
        if not part:
            self.close_client(fd)
            return
        buffer.extend(part)
        if b'\n' not in buffer and len(buffer) < 64:
            return
        data = bytes(buffer.split(b'\n', 1)[0]).strip()
        # Desregistrar antes de encerrar/alterar a UI: um comando por conexão.
        if data == b'PING':
            try:
                conn.sendall(b'PONG\n')
            except OSError:
                pass
        self.close_client(fd)
        if data in (b'NEXT', b'PREV') and self.refresh_pending:
            self.do_refresh()  # aplica notificações recebidas antes de escolher
        if data == b'NEXT':
            self.popup.request(False)
        elif data == b'PREV':
            self.popup.request(True)
        elif data == b'STOP':
            self.popup.finish(False)
            self.gui.quit()

    def close_client(self, fd):
        entry = self.incoming.pop(fd, None)
        if entry is None:
            return
        conn, _buf = entry
        try:
            self.gui.tk.deletefilehandler(fd)
        except Exception:
            pass
        conn.close()

    def mark_refresh(self, all_clients=False, wid=None, monitors_changed=False):
        self.pending_all |= all_clients
        self.pending_monitors |= monitors_changed
        if wid is not None:
            self.pending_clients.add(wid)
        if not self.refresh_pending:
            self.refresh_pending = True
            self.gui.after_idle(self.do_refresh)

    def do_refresh(self):
        self.refresh_pending = False
        try:
            if self.pending_monitors:
                self.cat._read_monitors()
            if self.pending_all:
                self.cat.refresh_all()
            else:
                self.cat.desktop = self.cat.number('_NET_CURRENT_DESKTOP', Xatom.CARDINAL)
                self.cat.active = self.cat.number('_NET_ACTIVE_WINDOW', Xatom.WINDOW)
            for wid in self.pending_clients:
                self.cat.refresh_one(wid)
        except Exception as err:
            log('Atualização catálogo: ' + str(err))
        self.pending_all = False
        self.pending_clients.clear()
        self.pending_monitors = False

    def on_x11(self, _fd, _mask):
        root = self.cat.root
        processed = 0
        while self.dpy.pending_events() and processed < 256:
            processed += 1
            ev = self.dpy.next_event()
            if ev.type in (X.KeyPress, X.KeyRelease):
                self.popup.key_event(ev)
            elif ev.type == X.PropertyNotify:
                if ev.window.id == root.id:
                    if ev.atom in (self.cat.a['_NET_CLIENT_LIST_STACKING'], self.cat.a['_NET_CLIENT_LIST']):
                        self.mark_refresh(all_clients=True)
                    elif ev.atom in (self.cat.a['_NET_ACTIVE_WINDOW'], self.cat.a['_NET_CURRENT_DESKTOP']):
                        self.mark_refresh()
                else:
                    self.mark_refresh(wid=ev.window.id)
            elif ev.type in (X.ConfigureNotify, X.UnmapNotify, X.DestroyNotify):
                if ev.window.id in self.cat.stack:
                    self.mark_refresh(wid=ev.window.id)
            elif self.cat.randr_event_base is not None and (self.cat.randr_event_base <= ev.type < self.cat.randr_event_base + 2):
                self.mark_refresh(all_clients=True, monitors_changed=True)
        if self.dpy.pending_events():
            # Continuar este lote por evento agendado (sem loop de polling).
            self.gui.after_idle(lambda: self.on_x11(None, None))

    def on_click(self, _fd, _mask):
        try:
            data = os.read(self.click_r, 8192)
            self.click_data += data
            while len(self.click_data) >= 8:
                x, y = struct.unpack('!ii', self.click_data[:8])
                self.click_data = self.click_data[8:]
                self.popup.pointer_click(x, y)
        except (OSError, BlockingIOError):
            pass

    def run(self):
        try:
            self.gui.mainloop()  # event driven: X11 FD, UNIX FD, Tk FD
        finally:
            self.popup.finish(False)
            for fd in list(self.incoming):
                self.close_client(fd)
            for fd in (self.sock.fileno(), self.dpy.fileno(), self.click_r):
                try:
                    self.gui.tk.deletefilehandler(fd)
                except Exception:
                    pass
            os.close(self.click_r)
            os.close(self.click_w)
            self.dpy.close()
            self.gui.destroy()


def send_stop():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(0.2)
    try:
        sock.connect(str(socket_path()))
        sock.sendall(b'STOP\n')
        return True
    except OSError:
        return False
    finally:
        sock.close()


def serve():
    if os.environ.get('XDG_SESSION_TYPE') not in (None, '', 'x11'):
        return 2
    fd = os.open(lock_path(), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        path = socket_path()
        try:
            path.unlink(missing_ok=True)  # apenas socket privado após adquirir lock
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server.bind(str(path))
            os.chmod(path, 0o600)
            server.listen(12)
            server.setblocking(False)
        except OSError as exc:
            log('Falha socket: ' + str(exc))
            return 1
        try:
            app = Service(server)
            log('Iniciado (um daemon por DISPLAY); EWMH + XRecord, sem polling')
            app.run()
        except Exception as exc:
            log('Fatal: ' + str(exc))
            return 1
        finally:
            server.close()
            path.unlink(missing_ok=True)
        return 0
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serve', action='store_true')
    parser.add_argument('--stop', action='store_true')
    args = parser.parse_args()
    if args.stop:
        return 0 if send_stop() else 1
    return serve()


if __name__ == '__main__':
    sys.exit(main())
