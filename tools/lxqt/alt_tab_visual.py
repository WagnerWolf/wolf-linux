#!/usr/bin/env python3
"""Wolf LXQt — alternador X11 por monitor (Alt+Tab padrão).

Alt+Tab abre a janela; Tab/Shift+Tab percorrem; soltar Alt confirma.
Um clique no item confirma imediatamente. Esc ou clique fora cancelam.
Super+Tab permanece como alternativa nativa do Openbox.

Requer: python-xlib, tkinter (pacote tk), wmctrl, xrandr, xdotool.
Fallback Rofi opcional com --rofi ou se tkinter/Xlib não estiverem disponíveis.
"""
import os
import re
import queue
import threading
import subprocess
import sys
from pathlib import Path

LOG = Path.home() / '.cache/wolf-lxqt-alt-tab.log'


def log(message):
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open('a', encoding='utf-8') as f:
            f.write(message + '\n')
    except OSError:
        pass


def run(*cmd):
    return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)


def monitors(text):
    result = []
    for line in text.splitlines():
        m = re.search(r'(\d+)/\d+x(\d+)/\d+\+(-?\d+)\+(-?\d+)', line)
        if m:
            w, h, x, y = map(int, m.groups())
            result.append((x, y, w, h))
    return result


def parse_windows(text):
    out = []
    for line in text.splitlines():
        parts = line.split(None, 8)
        if len(parts) < 8:
            continue
        try:
            wid = int(parts[0], 16)
            desk = int(parts[1]); x, y, w, h = map(int, parts[2:6])
        except ValueError:
            continue
        if w <= 0 or h <= 0:
            continue
        wmclass = parts[6]
        title = parts[8] if len(parts) > 8 else wmclass
        out.append(dict(id=wid, desktop=desk, x=x, y=y, w=w, h=h,
                        wmclass=wmclass, icon=wmclass.split('.')[0], title=title.strip()))
    return out


def excluded_by_metadata(w, metadata=''):
    """Descarta áreas de trabalho, docks e janelas fora da lista de tarefas.

    Filtro textual defensivo: alguns ambientes não exportam EWMH completo.
    """
    title = w.get('title', '').strip().lower()
    classname = w.get('wmclass', '').lower()
    if title.startswith('pcmanfm-desktop') or title in {'lxqt panel', 'lxqt-panel'}:
        return True
    if 'lxqt-panel' in classname or 'lxqt.panel' in classname:
        return True
    if 'pcmanfm-qt' in classname and ('desktop' in title or title == ''):
        return True
    metadata = metadata.upper()
    return any(flag in metadata for flag in (
        '_NET_WM_WINDOW_TYPE_DESKTOP', '_NET_WM_WINDOW_TYPE_DOCK',
        '_NET_WM_WINDOW_TYPE_TOOLTIP', '_NET_WM_WINDOW_TYPE_NOTIFICATION',
        '_NET_WM_STATE_SKIP_TASKBAR'))


def remove_nonapps(windows, metadata_getter=None):
    result = []
    for w in windows:
        metadata = metadata_getter(w['id']) if metadata_getter else ''
        if not excluded_by_metadata(w, metadata):
            result.append(w)
    return result


def overlap(win, mon):
    mx, my, mw, mh = mon
    return max(0, min(win['x']+win['w'], mx+mw) - max(win['x'], mx)) * max(0, min(win['y']+win['h'], my+mh) - max(win['y'], my))


def choose_candidates(mons, mouse, wins, desktop, active, stack):
    idx = next((i for i, (x, y, w, h) in enumerate(mons)
                if x <= mouse[0] < x+w and y <= mouse[1] < y+h), None)
    if idx is None:
        return None, []
    mon = mons[idx]
    choices = [w for w in wins if w['desktop'] in (-1, desktop) and overlap(w, mon) > 0
               and overlap(w, mon)*2 >= w['w']*w['h']]
    if not choices:
        choices = [w for w in wins if w['desktop'] in (-1, desktop) and overlap(w, mon) > 0]
    pos = {wid: i for i, wid in enumerate(stack)}
    choices.sort(key=lambda w: pos.get(w['id'], -1), reverse=True)
    # Deixe a janela ativa no fim para o primeiro Tab selecionar outra.
    if len(choices) > 1:
        choices.sort(key=lambda w: w['id'] == active)
    return idx, choices


def read_session():
    mons = monitors(run('xrandr', '--listmonitors'))
    coords = dict(line.split('=', 1) for line in run('xdotool', 'getmouselocation', '--shell').splitlines() if '=' in line)
    pointer = int(coords['X']), int(coords['Y'])
    wins = parse_windows(run('wmctrl', '-lxG'))
    def metadata(wid):
        try:
            return subprocess.run(
                ['xprop', '-id', hex(wid), '_NET_WM_WINDOW_TYPE', '_NET_WM_STATE'],
                capture_output=True, text=True, timeout=1).stdout
        except (OSError, subprocess.TimeoutExpired):
            return ''
    wins = remove_nonapps(wins, metadata)
    desktop = int(run('xdotool', 'get_desktop').strip())
    active = int(run('xdotool', 'getactivewindow').strip())
    try:
        stack = [int(x, 16) for x in re.findall(r'0x[0-9a-fA-F]+',
                 run('xprop', '-root', '_NET_CLIENT_LIST_STACKING'))]
    except (OSError, subprocess.CalledProcessError):
        stack = []
    monitor, choices = choose_candidates(mons, pointer, wins, desktop, active, stack)
    return mons, pointer, monitor, choices


def activate(win):
    subprocess.run(['wmctrl', '-ia', hex(win['id'])], check=True, timeout=4)


def fallback_rofi(choices, monitor):
    if not choices:
        return 0
    from shutil import which
    if not which('rofi'):
        log('Nenhum seletor disponível: faltam tkinter e rofi')
        return 2
    rows = []
    for w in choices:
        title = w['title'].replace('\n', ' ').replace('\r', ' ').replace('\0', ' ')
        rows.append(f"{title[:110]}\0icon\x1f{w['icon']}")
    theme = ('* { text-color: #f0f6ff; background-color: #111923; selected-normal-background: #335f89; '
             'selected-normal-foreground: #ffffff; } '
             'window { width: 40%; padding: 14px; border: 2px; border-color: #5aa0df; border-radius: 10px; } '
             'listview { lines: 8; spacing: 5px; } '
             'element { padding: 10px; border-radius: 6px; } '
             'element selected.normal { background-color: #335f89; text-color: #ffffff; } '
             'element-text { text-color: inherit; } '
             'inputbar { padding: 10px; }')
    cmd = ['rofi', '-dmenu', '-no-custom', '-show-icons', '-format', 'i', '-monitor', '-5',
           '-p', f'Janelas · monitor {monitor+1}', '-hover-select',
           '-me-select-entry', '', '-me-accept-entry', 'MousePrimary', '-theme-str', theme]
    p = subprocess.run(cmd, input='\n'.join(rows)+'\n', text=True, capture_output=True)
    if p.returncode == 0:
        n = int(p.stdout.strip())
        if 0 <= n < len(choices):
            activate(choices[n])
    return 0


def outside_popup(px, py, bounds):
    """Geometria X11: identifica clique estritamente fora do alternador."""
    x, y, width, height = bounds
    return not (x <= px < x + width and y <= py < y + height)


def record_pointer_clicks(target_queue, stop_event):
    """Observa ButtonPress via XRecord sem capturar nem bloquear o mouse.

    Usa conexão própria: chamadas Tk só acontecem na thread principal, pelo poll().
    Se a extensão RECORD estiver indisponível, o Alt+Tab segue funcionando.
    """
    from Xlib import X, display
    from Xlib.ext import record
    from Xlib.protocol import rq

    rdisplay = display.Display()
    if not rdisplay.has_extension('RECORD'):
        log('Aviso: X11 RECORD indisponível; fechamento ao clicar fora desativado')
        rdisplay.close()
        return

    def callback(reply):
        if stop_event.is_set() or reply.category != record.FromServer or reply.client_swapped:
            return
        if not reply.data or reply.data[0] < 2:
            return
        data = reply.data
        while data:
            try:
                event, data = rq.EventField(None).parse_binary_value(
                    data, rdisplay.display, None, None)
            except Exception as exc:
                log('Aviso: leitura de clique XRecord: ' + str(exc))
                return
            if event.type == X.ButtonPress:
                try:
                    target_queue.put_nowait((event.root_x, event.root_y))
                except queue.Full:
                    pass

    context = rdisplay.record_create_context(0, [record.AllClients], [{
        'core_requests': (0, 0), 'core_replies': (0, 0),
        'ext_requests': (0, 0, 0, 0), 'ext_replies': (0, 0, 0, 0),
        'delivered_events': (0, 0),
        'device_events': (X.ButtonPress, X.ButtonPress),
        'errors': (0, 0), 'client_started': False, 'client_died': False
    }])
    try:
        rdisplay.record_enable_context(context, callback)
    finally:
        try:
            rdisplay.record_free_context(context)
        except Exception:
            pass
        rdisplay.close()



# Os ícones reais vêm primeiro da janela X11 (_NET_WM_ICON). Se um cliente
# não exportar a propriedade, procuramos a entrada .desktop/tema de ícones.
# Nenhuma dependência Pillow é necessária: Tk 8.6 lê PNG diretamente.
def encode_argb_png(pixels, width, height, target=32):
    """Converte o ARGB de EWMH para PNG RGBA, redimensionado (nearest)."""
    import struct
    import zlib

    if not 0 < width <= 256 or not 0 < height <= 256:
        raise ValueError('Ícone X11 com dimensões inesperadas')
    if len(pixels) != width * height:
        raise ValueError('Tamanho inválido do ícone X11')
    out_w, out_h = target, target
    rows = bytearray()
    for y in range(out_h):
        sy = min(height - 1, y * height // out_h)
        rows.append(0)  # filtro PNG por linha
        for x in range(out_w):
            sx = min(width - 1, x * width // out_w)
            argb = int(pixels[sy * width + sx]) & 0xffffffff
            rows.extend(((argb >> 16) & 255, (argb >> 8) & 255,
                         argb & 255, (argb >> 24) & 255))

    def chunk(name, payload):
        return (struct.pack('!I', len(payload)) + name + payload +
                struct.pack('!I', zlib.crc32(name + payload) & 0xffffffff))

    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('!2I5B', out_w, out_h, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(bytes(rows), level=4)) +
            chunk(b'IEND', b''))


def icon_from_x11(dpy, window_id, target=32):
    """Extrai _NET_WM_ICON. Clientes X11 podem oferecer vários tamanhos."""
    from Xlib import X

    try:
        atom = dpy.intern_atom('_NET_WM_ICON', only_if_exists=True)
        if not atom:
            return None
        obj = dpy.create_resource_object('window', window_id)
        prop = obj.get_full_property(atom, X.AnyPropertyType)
        if not prop or prop.format != 32 or len(prop.value) > 800000:
            return None
        values = prop.value
        pos, valid = 0, []
        while pos + 2 <= len(values):
            width, height = int(values[pos]), int(values[pos + 1])
            pos += 2
            n = width * height
            if n <= 0 or pos + n > len(values):
                break
            if width <= 256 and height <= 256:
                valid.append((width, height, pos, n))
            pos += n
        if not valid:
            return None
        width, height, start, n = min(valid, key=lambda it: (
            abs(max(it[0], it[1]) - target),
            0 if min(it[0], it[1]) >= target else 1))
        return encode_argb_png(values[start:start + n], width, height, target)
    except Exception as exc:
        log(f'Ícone X11 não disponível para {hex(window_id)}: {exc}')
        return None


def icon_names_for_window(w):
    """Obtém Icon= de arquivos desktop e mapeia nomes de classes conhecidos."""
    import configparser

    wmclass = w.get('wmclass', '')
    parts = [x.lower() for x in wmclass.split('.') if x]
    defaults = {
        'google-chrome': 'google-chrome', 'google-chrome-stable': 'google-chrome',
        'chrome': 'google-chrome', 'chromium': 'chromium',
        'pcmanfm-qt': 'system-file-manager', 'konsole': 'utilities-terminal',
        'kate': 'accessories-text-editor', 'okular': 'org.kde.okular',
        'firefox': 'firefox', 'steam': 'steam', 'discord': 'discord',
        'code': 'visual-studio-code', 'ark': 'ark', 'spectacle': 'spectacle',
    }
    names = []
    for part in parts:
        names.extend([defaults.get(part, part), part])
    dirs = [Path.home() / '.local/share/applications', Path('/usr/share/applications')]
    for directory in dirs:
        if not directory.is_dir():
            continue
        for desktop in directory.glob('*.desktop'):
            name = desktop.stem.lower()
            if not any(part in name or name in part for part in parts):
                continue
            try:
                cfg = configparser.ConfigParser(interpolation=None)
                cfg.optionxform = str
                cfg.read(desktop, encoding='utf-8')
                section = cfg['Desktop Entry']
                matching_class = section.get('StartupWMClass', '').lower()
                if (any(part in name or name in part for part in parts)
                        or matching_class in parts):
                    icon = section.get('Icon')
                    if icon:
                        names.insert(0, icon)
            except (OSError, configparser.Error, KeyError):
                continue
    return list(dict.fromkeys(x for x in names if x))


def icon_file_for_window(w):
    """Procura arquivos PNG/SVG no tema, sem depender de bindings GTK."""
    import shutil

    bases = [Path.home() / '.local/share/icons', Path.home() / '.icons',
             Path('/usr/share/icons')]
    themes = ['Papirus-Dark', 'Papirus', 'breeze-dark', 'breeze', 'hicolor']
    sizes = ['32x32', '48x48', '64x64', 'scalable']
    converters = shutil.which('rsvg-convert')
    for name in icon_names_for_window(w):
        direct = Path(name)
        if direct.is_file():
            yield direct, converters
        for base in bases:
            for theme in themes:
                for size in sizes:
                    for category in ('apps', 'applications'):
                        for suffix in ('.png', '.svg'):
                            path = base / theme / size / category / (name + suffix)
                            if path.is_file() and (suffix == '.png' or converters):
                                yield path, converters
        for suffix in ('.png', '.svg'):
            path = Path('/usr/share/pixmaps') / (name + suffix)
            if path.is_file() and (suffix == '.png' or converters):
                yield path, converters


def load_window_icon(tk, dpy, win, cache, size=32):
    """Retorna PhotoImage real e mantém cache por janela durante a exibição."""
    import base64

    wid = win['id']
    if wid in cache:
        return cache[wid]
    png = icon_from_x11(dpy, wid, size)
    if png:
        try:
            img = tk.PhotoImage(data=base64.b64encode(png).decode('ascii'), format='png')
            cache[wid] = img
            return img
        except Exception as exc:
            log(f'Não foi possível renderizar ícone X11 {hex(wid)}: {exc}')
    for path, converter in icon_file_for_window(win):
        try:
            if path.suffix.lower() == '.svg':
                png = subprocess.check_output([converter, '-w', str(size), '-h', str(size), str(path)], timeout=2)
                img = tk.PhotoImage(data=base64.b64encode(png).decode('ascii'), format='png')
            else:
                img = tk.PhotoImage(file=str(path))
                # PhotoImage.subsample apenas para ícones excepcionalmente grandes.
                ratio = max(1, (max(img.width(), img.height()) + size - 1) // size)
                if ratio > 1:
                    img = img.subsample(ratio, ratio)
            cache[wid] = img
            return img
        except Exception as exc:
            log(f'Ícone {path}: {exc}')
    cache[wid] = None
    return None


def switcher_tk(mons, monitor, choices, reverse=False, preview=False):
    import tkinter as tk
    from Xlib import X, XK, display

    dpy = display.Display()
    root_x = dpy.screen().root
    watched = [dpy.keysym_to_keycode(XK.string_to_keysym(s)) for s in ('Alt_L', 'Alt_R')]
    tabs = {dpy.keysym_to_keycode(XK.string_to_keysym('Tab'))}
    escapes = {dpy.keysym_to_keycode(XK.string_to_keysym('Escape'))}
    enters = {dpy.keysym_to_keycode(XK.string_to_keysym(s)) for s in ('Return', 'KP_Enter')}
    downs = {dpy.keysym_to_keycode(XK.string_to_keysym('Down'))}
    ups = {dpy.keysym_to_keycode(XK.string_to_keysym('Up'))}
    shift = {dpy.keysym_to_keycode(XK.string_to_keysym(s)) for s in ('Shift_L', 'Shift_R')}

    def down(keycode):
        if not keycode:
            return False
        data = dpy.query_keymap()
        return bool(data[keycode // 8] & (1 << (keycode % 8)))

    def alt_pressed():
        return any(down(k) for k in watched)

    tkroot = tk.Tk()
    tkroot.overrideredirect(True)
    tkroot.wm_attributes('-topmost', True)
    tkroot.configure(bg='#5aa0df')
    tkroot.withdraw()
    x, y, mw, mh = mons[monitor]
    width = min(620, max(340, mw - 80))
    show_rows = min(8, len(choices))
    height = min(mh - 40, 90 + show_rows * 59 + 18)
    posx = x + (mw-width)//2
    posy = y + (mh-height)//2
    tkroot.geometry(f'{width}x{height}{posx:+d}{posy:+d}')

    panel = tk.Frame(tkroot, bg='#121c29', padx=12, pady=12)
    panel.pack(fill='both', expand=True, padx=2, pady=2)
    tk.Label(panel, text=f'JANELAS · MONITOR {monitor+1}', bg='#121c29', fg='#a9c7e8',
             font=('Noto Sans', 10, 'bold'), anchor='w').pack(fill='x', padx=8, pady=(0, 9))
    frame = tk.Frame(panel, bg='#121c29')
    frame.pack(fill='both', expand=True)
    canvas = tk.Canvas(frame, bg='#121c29', borderwidth=0, highlightthickness=0)
    # Barra visual removida: o Canvas continua rolável internamente.
    # O item selecionado permanece visível mesmo com mais de oito janelas.
    canvas.pack(fill='both', expand=True)
    listing = tk.Frame(canvas, bg='#121c29')
    canvas.create_window((0, 0), window=listing, anchor='nw', tags='listing')
    listing.bind('<Configure>', lambda e: canvas.configure(scrollregion=canvas.bbox('all')))
    canvas.bind('<Configure>', lambda e: canvas.itemconfigure('listing', width=e.width))

    def scroll_list(event):
        if getattr(event, 'num', None) == 4:
            step = -1
        elif getattr(event, 'num', None) == 5:
            step = 1
        else:
            delta = getattr(event, 'delta', 0)
            if not delta:
                return
            step = -1 if delta > 0 else 1
        canvas.yview_scroll(step, 'units')
        return 'break'

    # O Canvas continua rolando mesmo sem mostrar o controle de scrollbar.
    tkroot.bind_all('<MouseWheel>', scroll_list)
    tkroot.bind_all('<Button-4>', scroll_list)
    tkroot.bind_all('<Button-5>', scroll_list)
    tk.Label(panel, text='Alt + Tab: avançar   ·   Soltar Alt: selecionar   ·   Esc: cancelar',
             bg='#121c29', fg='#88a3bd', font=('Noto Sans', 9)).pack(fill='x', pady=(8, 0))
    buttons=[]
    selected = [len(choices)-1 if reverse and len(choices)>1 else 0]
    closed = [False]
    grabbed = [False]
    outside_clicks = queue.Queue(maxsize=16)
    stop_pointer_watch = threading.Event()
    bounds = (posx, posy, width, height)

    def finish(confirm):
        if closed[0]:
            return
        closed[0] = True
        stop_pointer_watch.set()
        try:
            if grabbed[0]:
                dpy.ungrab_keyboard(X.CurrentTime)
                dpy.sync()
        except Exception:
            pass
        try:
            tkroot.destroy()
        finally:
            dpy.close()
        if confirm:
            try:
                activate(choices[selected[0]])
            except Exception as exc:
                log('Falha ao ativar janela: '+str(exc))

    def redraw():
        for i, item in enumerate(buttons):
            chosen = (i == selected[0])
            item.configure(bg='#32608a' if chosen else '#1b2b3d',
                           activebackground='#4076a9', fg='#ffffff' if chosen else '#e6f0fc')
        tkroot.update_idletasks()
        # Sem scrollbar visível: manter a seleção dentro da área mostrada.
        scrollregion = canvas.bbox('all') or (0, 0, 0, 0)
        content_h = max(1, scrollregion[3] - scrollregion[1])
        viewport_h = max(1, canvas.winfo_height())
        item = buttons[selected[0]]
        item_top = item.winfo_y()
        item_bottom = item_top + item.winfo_height()
        visible_top = canvas.canvasy(0)
        visible_bottom = visible_top + viewport_h
        if item_top < visible_top:
            canvas.yview_moveto(max(0, item_top / content_h))
        elif item_bottom > visible_bottom:
            canvas.yview_moveto(min(1, max(0, item_bottom - viewport_h) / content_h))

    icon_cache = {}
    for idx,w in enumerate(choices):
        cls=w['wmclass'].split('.')[0]
        text=f"  {w['title'][:62] or cls}     ·     {cls[:20]}"
        icon = load_window_icon(tk, dpy, w, icon_cache)
        b=tk.Button(listing, text=text, image=icon or '', compound='left',
                    justify='left', anchor='w', relief='flat', bd=0,
                    bg='#1b2b3d', fg='#e6f0fc', activebackground='#4076a9',
                    activeforeground='#ffffff', cursor='hand2',
                    font=('Noto Sans', 11), pady=12,
                    command=lambda i=idx: (selected.__setitem__(0,i),finish(True)))
        b.pack(fill='x', pady=3)
        buttons.append(b)
    tkroot.deiconify()
    tkroot.update_idletasks()
    tkroot.lift()
    redraw()
    if not preview:
        reply = root_x.grab_keyboard(False, X.GrabModeAsync, X.GrabModeAsync, X.CurrentTime)
        grabbed[0] = ((reply.status if hasattr(reply, 'status') else reply) == X.GrabSuccess)
        if not grabbed[0]:
            log('Aviso: XGrabKeyboard indisponível; seletor no modo clique/Enter')

    def pointer_watcher():
        try:
            record_pointer_clicks(outside_clicks, stop_pointer_watch)
        except Exception as exc:
            log('Aviso: observador de clique fora não inicializado: ' + str(exc))

    threading.Thread(target=pointer_watcher, daemon=True, name='wolf-click-outside').start()
    initial = __import__('time').monotonic()

    def poll():
        if closed[0]:
            return
        try:
            # Processar cancelamento antes de KeyRelease: clique fora jamais
            # confirma a janela escolhida no nosso alternador.
            while not outside_clicks.empty():
                px, py = outside_clicks.get_nowait()
                if outside_popup(px, py, bounds):
                    log(f'Clique fora em {px},{py}: alternância cancelada')
                    finish(False)
                    return
            while dpy.pending_events():
                ev=dpy.next_event()
                if ev.type == X.KeyPress:
                    if ev.detail in tabs or ev.detail in downs or ev.detail in ups:
                        backward = ev.detail in ups or (ev.detail in tabs and (ev.state & X.ShiftMask))
                        selected[0] = (selected[0] + (-1 if backward else 1)) % len(choices)
                        redraw()
                    elif ev.detail in escapes:
                        finish(False);return
                    elif ev.detail in enters:
                        finish(True);return
                elif ev.type == X.KeyRelease and ev.detail in watched:
                    if not alt_pressed():
                        finish(True);return
            # Se a pessoa já soltou Alt antes do helper capturar o teclado,
            # completar rapidamente o primeiro ciclo (comportamento Alt+Tab normal).
            if not preview and grabbed[0] and __import__('time').monotonic()-initial>0.18 and not alt_pressed():
                finish(True);return
        except Exception as exc:
            log('Erro lendo teclado X11: '+str(exc))
            finish(False);return
        tkroot.after(20, poll)

    def preview_key(event):
        if event.keysym in ('Escape',): finish(False)
        elif event.keysym in ('Return','KP_Enter'): finish(True)
        elif event.keysym in ('Tab','Down','Up'):
            selected[0]=(selected[0] + (-1 if event.keysym=='Up' else 1))%len(choices)
            redraw()
            return 'break'

    tkroot.bind_all('<KeyPress>', preview_key)
    tkroot.after(20, poll)
    tkroot.mainloop()
    return 0


def main():
    if os.environ.get('XDG_SESSION_TYPE') != 'x11':
        print('Use o seletor somente em sessão X11.', file=sys.stderr)
        return 2
    try:
        mons,pointer,monitor,choices=read_session()
        if '--debug' in sys.argv:
            print('Monitores:',mons,'Cursor:',pointer,'Monitor:',monitor)
            print('Janelas elegíveis:',[(hex(w['id']),w['title'],w['wmclass']) for w in choices])
        if monitor is None or not choices:
            return 0
        if '--rofi' in sys.argv:
            return fallback_rofi(choices, monitor)
        try:
            import tkinter  # noqa: F401
            from Xlib import X  # noqa: F401
        except ImportError:
            log('tkinter/python-xlib ausente: fallback Rofi')
            return fallback_rofi(choices, monitor)
        return switcher_tk(mons,monitor,choices,
                           reverse='--reverse' in sys.argv,
                           preview='--preview' in sys.argv or '--debug' in sys.argv)
    except (OSError,ValueError,KeyError,subprocess.CalledProcessError,subprocess.TimeoutExpired) as exc:
        log('Falha: '+str(exc))
        print('Wolf Alt+Tab: '+str(exc),file=sys.stderr)
        return 1

if __name__=='__main__':
    sys.exit(main())
