#!/usr/bin/env python3
"""Wolf Window Keeper 0.2-preview2 (LXQt/Openbox/X11), dirigido por eventos.

Monitor passivo ou corretor opt-in para janelas normais do Chromium/Thorium.
Nao intercepta teclado/mouse, nao executa sudo, nao toca em configuracoes.
"""
from __future__ import annotations

import argparse
import os
import fcntl
import hashlib
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import re
import subprocess
import sys
import time
import select

DEFAULT_CLASSES = ('thorium', 'chromium', 'google-chrome', 'chrome')
LOG = Path.home() / '.cache/wolf-window-keeper.log'


@dataclass(frozen=True)
class Rectangle:
    x: int
    y: int
    w: int
    h: int


@dataclass(frozen=True)
class Client:
    wid: int
    wmclass: str
    rect: Rectangle
    fullscreen: bool
    max_vert: bool
    max_horz: bool


@dataclass
class Tracked:
    last: Client
    monitor: int | None
    restore_rect: Rectangle | None
    restore_monitor: int | None
    pending_kind: str = ''
    due_at: float = 0
    initial_target: int | None = None
    initial_pointer: tuple[int, int] | None = None


def parse_monitors(output: str) -> list[Rectangle]:
    mons = []
    for line in output.splitlines():
        match = re.search(r'(\d+)/\d+x(\d+)/\d+\+(-?\d+)\+(-?\d+)', line)
        if match:
            w, h, x, y = map(int, match.groups())
            if w > 0 and h > 0:
                mons.append(Rectangle(x, y, w, h))
    return mons


def overlap(a: Rectangle, b: Rectangle) -> int:
    return (max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x))
            * max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y)))


def best_monitor(rect: Rectangle, monitors: list[Rectangle]) -> int | None:
    if not monitors or rect.w <= 0 or rect.h <= 0:
        return None
    areas = [overlap(rect, m) for m in monitors]
    area = max(areas)
    return areas.index(area) if area > 0 else None


def pointer_monitor(x: int, y: int, monitors: list[Rectangle]) -> int | None:
    for i, m in enumerate(monitors):
        if m.x <= x < m.x + m.w and m.y <= y < m.y + m.h:
            return i
    return None


def inside_rect(x: int, y: int, w: int, h: int, m: Rectangle) -> tuple[int, int]:
    """Limita o canto de uma janela à tela destino (sem redimensionar)."""
    return (max(m.x, min(x, m.x + max(0, m.w - w))),
            max(m.y, min(y, m.y + max(0, m.h - h))))


def class_matches(wmclass: str, patterns: tuple[str, ...]) -> bool:
    return any(pattern.casefold() in wmclass.casefold() for pattern in patterns)


def log(message: str):
    msg = f'[{datetime.now().isoformat(timespec="seconds")}] {message}'
    print(msg, flush=True)
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        if LOG.exists() and LOG.stat().st_size > 400_000:
            LOG.replace(LOG.with_suffix('.log.old'))
        with LOG.open('a', encoding='utf-8') as fp:
            fp.write(msg + '\n')
    except OSError:
        pass


def move(reader, client: Client, target: Rectangle,
         original: Rectangle | None = None) -> bool:
    """Envia pedidos EWMH sem subprocessos nem esperas ativas.

    A correção de janelas maximizadas é enviada na ordem: retirar estado,
    mover, restaurar estado. O Openbox processa os pedidos assincronamente.
    """
    from Xlib import X, protocol

    restore = original or client.rect
    x, y = inside_rect(restore.x, restore.y, restore.w, restore.h, target)
    wid = client.wid
    flags = [name for enabled, name in (
        (client.max_vert, '_NET_WM_STATE_MAXIMIZED_VERT'),
        (client.max_horz, '_NET_WM_STATE_MAXIMIZED_HORZ')) if enabled]
    root = reader.root
    dpy = reader.dpy
    try:
        win = dpy.create_resource_object('window', wid)
        if flags:
            parts = [reader.atoms[v] for v in flags] + [0, 0]
            ev = protocol.event.ClientMessage(window=win, client_type=reader.atoms['_NET_WM_STATE'],
                                              data=(32, [0, parts[0], parts[1], 2, 0]))
            root.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
        # StaticGravity=10, x/y presentes (bits 8,9), origem pager=2 (bit 12).
        flags_xy = 10 | (3 << 8) | (2 << 12)
        ev = protocol.event.ClientMessage(window=win, client_type=reader.atoms['_NET_MOVERESIZE_WINDOW'],
                                          data=(32, [flags_xy, x, y, 0, 0]))
        root.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
        if flags:
            ev = protocol.event.ClientMessage(window=win, client_type=reader.atoms['_NET_WM_STATE'],
                                              data=(32, [1, parts[0], parts[1], 2, 0]))
            root.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
        dpy.flush()
        return True
    except (reader.error.XError, ValueError, TypeError) as exc:
        log(f'0x{wid:x}: erro EWMH {type(exc).__name__}')
        return False

class XReader:
    def __init__(self):
        try:
            from Xlib import display, Xatom, error
        except ImportError as exc:
            raise RuntimeError('Falta python-xlib: sudo pacman -S --needed python-xlib') from exc
        self.Xatom = Xatom
        self.error = error
        self.dpy = display.Display()
        self.root = self.dpy.screen().root
        names = ('_NET_CLIENT_LIST', '_NET_WM_STATE', '_NET_WM_STATE_FULLSCREEN',
                 '_NET_WM_STATE_MAXIMIZED_VERT', '_NET_WM_STATE_MAXIMIZED_HORZ',
                 '_NET_WM_WINDOW_TYPE', '_NET_WM_WINDOW_TYPE_NORMAL',
                 '_NET_MOVERESIZE_WINDOW', 'WM_CLASS')
        self.atoms = {n: self.dpy.intern_atom(n) for n in names}

    def prop(self, win, name: str, typ):
        return win.get_full_property(self.atoms[name], typ)

    def pointer(self) -> tuple[int, int]:
        info = self.root.query_pointer()
        return info.root_x, info.root_y

    def client_ids(self) -> set[int]:
        prop = self.prop(self.root, '_NET_CLIENT_LIST', self.Xatom.WINDOW)
        return set(map(int, prop.value)) if prop else set()

    def watch_window(self, wid: int):
        from Xlib import X
        win = self.dpy.create_resource_object('window', wid)
        win.change_attributes(event_mask=X.PropertyChangeMask | X.StructureNotifyMask)
        self.dpy.flush()

    def watch(self) -> None:
        from Xlib import X
        self.randr_event_base = None
        self.root.change_attributes(event_mask=X.PropertyChangeMask | X.StructureNotifyMask)
        # Eventos XRandR reagem a hotplug e troca de resolução sem timer.
        try:
            from Xlib.ext import randr
            if self.dpy.has_extension('RANDR'):
                self.randr_event_base = self.dpy.query_extension('RANDR').first_event
                randr.select_input(self.root, randr.RRScreenChangeNotifyMask |
                                   randr.RROutputChangeNotifyMask |
                                   randr.RRCrtcChangeNotifyMask)
        except (ImportError, self.error.XError):
            log('Aviso: XRandR Notify indisponível; usando eventos de geometria raiz')
        self.dpy.flush()

    def read_client(self, wid: int, patterns: tuple[str, ...]) -> Client | None:
        try:
            win = self.dpy.create_resource_object('window', int(wid))
            wmclass = win.get_wm_class()
            if not wmclass:
                return None
            cl = '.'.join(str(v) for v in wmclass if v)
            if not class_matches(cl, patterns) or win.get_wm_transient_for():
                return None
            types = self.prop(win, '_NET_WM_WINDOW_TYPE', self.Xatom.ATOM)
            if types and self.atoms['_NET_WM_WINDOW_TYPE_NORMAL'] not in types.value:
                return None
            geo = win.get_geometry()
            if geo.width <= 80 or geo.height <= 80:
                return None
            coords = self.root.translate_coords(win, 0, 0)
            states = self.prop(win, '_NET_WM_STATE', self.Xatom.ATOM)
            state_set = set(states.value) if states else set()
            return Client(int(wid), cl, Rectangle(coords.x, coords.y, geo.width, geo.height),
                          self.atoms['_NET_WM_STATE_FULLSCREEN'] in state_set,
                          self.atoms['_NET_WM_STATE_MAXIMIZED_VERT'] in state_set,
                          self.atoms['_NET_WM_STATE_MAXIMIZED_HORZ'] in state_set)
        except (self.error.XError, ValueError, TypeError, AttributeError):
            return None

    def snapshot(self, patterns: tuple[str, ...]) -> dict[int, Client]:
        return {w.wid: w for wid in self.client_ids()
                if (w := self.read_client(wid, patterns)) is not None}


def get_monitors() -> list[Rectangle]:
    try:
        return parse_monitors(subprocess.check_output(
            ['xrandr', '--listmonitors'], text=True, stderr=subprocess.DEVNULL, timeout=3))
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return []


def next_timeout(tracked: dict[int, Tracked], started: float, duration: float,
                 now: float) -> float | None:
    """Timer sob demanda: acordar somente quando existir ação agendada."""
    due = [s.due_at for s in tracked.values() if s.pending_kind]
    if duration > 0:
        due.append(started + duration)
    return max(0.0, min(due) - now) if due else None


def keeper_lock():
    """Uma instância por DISPLAY, inclusive quando iniciado manualmente.

    flock não consulta janelas e não cria polling; o descritor fica aberto
    durante toda a execução do observador X11.
    """
    folder = Path.home() / '.cache' / 'wolf-window-keeper'
    if folder.is_symlink():
        raise RuntimeError('Diretório de lock inesperado (symlink)')
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    if folder.stat().st_uid != os.getuid() or (folder.stat().st_mode & 0o077):
        raise RuntimeError(f'Permissões inseguras do diretório: {folder}')
    token = hashlib.sha256(os.environ.get('DISPLAY', ':0').encode()).hexdigest()[:12]
    lockfile = folder / (token + '.lock')
    flags = os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(lockfile, flags, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return None
    return fd


def run(args) -> int:
    if not os.environ.get('DISPLAY') or os.environ.get('XDG_SESSION_TYPE') == 'wayland':
        print('[BLOQUEADO] Requer uma sessão LXQt/Openbox X11 com DISPLAY.', file=sys.stderr)
        return 2
    if not shutil.which('xrandr'):
        print('[BLOQUEADO] Falta xrandr.', file=sys.stderr)
        return 2
    try:
        reader = XReader()
    except Exception as exc:
        print(f'[BLOQUEADO] Conexão X11 indisponível: {exc}', file=sys.stderr)
        return 2
    monitors = get_monitors()
    if len(monitors) < 2:
        log('Uma tela detectada no login; aguardando XRandR para segundo monitor (sem polling).')
    patterns = tuple(x.strip() for x in args.classes.split(',') if x.strip())
    if not patterns:
        print('[BLOQUEADO] --classes não pode estar vazio.', file=sys.stderr)
        return 2
    try:
        lockfd = keeper_lock()
    except (RuntimeError, OSError) as exc:
        print(f'[BLOQUEADO] {exc}', file=sys.stderr)
        reader.dpy.close()
        return 2
    if lockfd is None:
        reader.dpy.close()
        log('Instância do Window Keeper já ativa neste DISPLAY; ignorando duplicata.')
        return 0
    from Xlib import X
    reader.watch()
    ids = reader.client_ids()
    # Monitorar metadados também de clientes cujo WM_CLASS ainda não está pronto.
    newly_mapped: set[int] = set()
    tracked: dict[int, Tracked] = {}
    for wid in ids:
        try:
            reader.watch_window(wid)
        except reader.error.XError:
            pass
    for wid, w in reader.snapshot(patterns).items():
        mon = best_monitor(w.rect, monitors)
        tracked[wid] = Tracked(w, mon, None if w.fullscreen else w.rect,
                               None if w.fullscreen else mon)
        try:
            reader.watch_window(wid)
        except reader.error.XError:
            pass
    reader.dpy.flush()
    now = started = time.monotonic()
    log(f'iniciado modo={"correção" if args.fix else "observação"}; classes={patterns}; '
        f'monitores={monitors}; janelas existentes={len(tracked)}; eventos X11; '
        f'retorno={args.restore_ms}ms')

    def on_window(wid: int, is_new=False) -> None:
        w = reader.read_client(wid, patterns)
        if w is None:
            if wid in tracked:
                tracked.pop(wid, None)
            return
        mon = best_monitor(w.rect, monitors)
        state = tracked.get(wid)
        now = time.monotonic()
        if state is None:
            newly_mapped.discard(wid)
            state = Tracked(w, mon, None if w.fullscreen else w.rect,
                            None if w.fullscreen else mon)
            tracked[wid] = state
            try:
                reader.watch_window(wid)
            except reader.error.XError:
                pass
            if is_new and not w.fullscreen:
                px, py = reader.pointer()
                target = pointer_monitor(px, py, monitors)
                if target is not None and mon is not None and mon != target:
                    state.initial_target = target
                    state.initial_pointer = (px, py)
                    state.pending_kind = 'abertura'
                    state.due_at = now + args.new_window_ms / 1000
                    log(f'0x{wid:x} {w.wmclass}: abertura na tela {mon+1}, '
                        f'cursor na {target+1}; validação agendada')
            return
        if not state.last.fullscreen and w.fullscreen:
            state.restore_monitor = state.monitor
            state.restore_rect = state.last.rect
            state.pending_kind = ''
            log(f'0x{wid:x} {w.wmclass}: entrou em tela cheia na tela '
                f'{state.restore_monitor+1 if state.restore_monitor is not None else "?"}')
        elif state.last.fullscreen and not w.fullscreen:
            if state.restore_monitor is not None and state.restore_rect:
                state.pending_kind = 'retorno'
                state.due_at = now + args.restore_ms / 1000
                log(f'0x{wid:x} {w.wmclass}: saiu da tela cheia; '
                    f'alvo tela {state.restore_monitor+1}')
        elif not w.fullscreen and not state.pending_kind:
            # Sem ação pendente, movimentações manuais continuam permitidas.
            state.restore_rect = w.rect
            state.restore_monitor = mon
            state.monitor = mon
        state.last = w

    def do_due() -> None:
        now = time.monotonic()
        for wid, state in list(tracked.items()):
            if not state.pending_kind or now < state.due_at:
                continue
            pending = state.pending_kind
            state.pending_kind = ''  # Não reagendar automaticamente nem repetir.
            w = reader.read_client(wid, patterns)
            if w is None or w.fullscreen or len(monitors) < 2:
                continue
            mon = best_monitor(w.rect, monitors)
            if pending == 'retorno':
                target = state.restore_monitor
                original = state.restore_rect
                if target is None or target >= len(monitors) or original is None:
                    continue
                if mon != target:
                    log(f'0x{wid:x}: {"restaurando" if args.fix else "restauraria"} '
                        f'tela {target+1} (atual {None if mon is None else mon+1})')
                    if args.fix and move(reader, w, monitors[target], original):
                        log(f'0x{wid:x}: pedido de restauração enviado (EWMH)')
            elif pending == 'abertura':
                target = state.initial_target
                pointer = reader.pointer()
                if target is not None and mon is not None and mon != target and \
                        pointer_monitor(*pointer, monitors) == target:
                    log(f'0x{wid:x}: {"movendo" if args.fix else "moveria"} '
                        f'janela recém-aberta para tela {target+1}')
                    dest_rect = Rectangle(monitors[target].x + 80, monitors[target].y + 70,
                                          w.rect.w, w.rect.h)
                    if args.fix and move(reader, w, monitors[target], dest_rect):
                        log(f'0x{wid:x}: pedido de reposicionamento enviado (EWMH)')
            state.last = w
            # A posição definitiva será capturada pelo próximo ConfigureNotify.
            if not args.fix:
                state.monitor = mon
                state.restore_monitor = mon
                state.restore_rect = w.rect

    def refresh_clients() -> None:
        nonlocal ids
        current = reader.client_ids()
        for wid in ids - current:
            tracked.pop(wid, None)
            newly_mapped.discard(wid)
        for wid in current - ids:
            newly_mapped.add(wid)
            try:
                reader.watch_window(wid)
            except reader.error.XError:
                pass
            on_window(wid, is_new=True)
        ids = current

    def refresh_monitors() -> None:
        nonlocal monitors, ids
        latest = get_monitors()
        if latest != monitors:
            log('geometria dos monitores alterada; descartando alvos antigos')
            monitors = latest
            ids = reader.client_ids()
            newly_mapped.clear()
            tracked.clear()
            for wid in ids:
                try:
                    reader.watch_window(wid)
                except reader.error.XError:
                    pass
                on_window(wid, is_new=False)

    try:
        while True:
            now = time.monotonic()
            if args.duration > 0 and now - started >= args.duration:
                break
            do_due()
            # Sem timers: bloqueia até o X11 enviar um evento. Zero polling.
            timeout = next_timeout(tracked, started, args.duration, time.monotonic())
            if reader.dpy.pending_events() == 0:
                readable, _, _ = select.select([reader.dpy], [], [], timeout)
                if not readable:
                    continue
            while reader.dpy.pending_events():
                event = reader.dpy.next_event()
                if event.type == X.PropertyNotify:
                    if event.window.id == reader.root.id and \
                            event.atom == reader.atoms['_NET_CLIENT_LIST']:
                        refresh_clients()
                    elif event.window.id in ids and \
                            event.atom in (reader.atoms['_NET_WM_STATE'],
                                           reader.atoms['WM_CLASS'],
                                           reader.atoms['_NET_WM_WINDOW_TYPE']):
                        on_window(event.window.id, is_new=event.window.id in newly_mapped)
                elif event.type == X.ConfigureNotify:
                    if event.window.id == reader.root.id:
                        refresh_monitors()
                    elif event.window.id in ids:
                        on_window(event.window.id, is_new=event.window.id in newly_mapped)
                elif event.type in (X.DestroyNotify, X.UnmapNotify):
                    wid = event.window.id
                    if wid in ids:
                        # Não remover imediatamente em Unmap: Chromium pode recriar
                        # a janela durante a transição. A lista EWMH é autoritativa.
                        if event.type == X.DestroyNotify:
                            tracked.pop(wid, None)
                elif (reader.randr_event_base is not None and
                      reader.randr_event_base <= event.type <= reader.randr_event_base + 1):
                    # Notificação XRandR; sem sondagens periódicas.
                    refresh_monitors()
    except KeyboardInterrupt:
        log('interrompido pelo usuário')
    finally:
        reader.dpy.close()
        os.close(lockfd)
    log('encerrado')
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--observe', action='store_true', help='Somente registra movimentos (padrão).')
    group.add_argument('--fix', action='store_true', help='Corrige abertura e saída de fullscreen (opt-in).')
    parser.add_argument('--classes', default=','.join(DEFAULT_CLASSES),
                        help='Classes X11 filtradas por substring, separadas por vírgula.')
    parser.add_argument('--duration', type=float, default=0, help='Encerra após N segundos (0 = contínuo).')
    parser.add_argument('--restore-ms', type=int, default=35, help='Atraso pontual após fullscreen (0 a 300 ms).')
    parser.add_argument('--new-window-ms', type=int, default=300, help='Acomodação pontual de nova janela (100 a 1000 ms).')
    try:
        args = parser.parse_args(argv)
        if not (0 <= args.restore_ms <= 300 and 100 <= args.new_window_ms <= 1000):
            parser.error('intervalos fora das faixas permitidas')
        return run(args)
    except KeyboardInterrupt:
        log("interrompido pelo usuário")
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
