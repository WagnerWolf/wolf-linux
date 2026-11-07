#!/usr/bin/env python3
"""Wolf LXQt: tecla Super isolada alterna Fancy Menu usando XRecord + DBus.

Sem grab de teclado, Super+E etc. continuam no Openbox.
Dependencia: python-xlib. Somente para sessão LXQt X11.
"""
import os
import subprocess
import sys
import time
from pathlib import Path

LOG = Path.home()/'.cache/wolf-lxqt-super-menu.log'


def log(msg):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open('a',encoding='utf-8') as f:
        f.write(f'{time.strftime("%Y-%m-%d %H:%M:%S")} {msg}\n')


def discover_action():
    """Descobre o caminho verdadeiro (menu1/menu2/fancymenu) na conexão LXQt.

    O identificador do plugin é configurável em panel.conf. Não presumir que
    se chame literalmente 'fancymenu'.
    """
    import re
    cmd=['busctl','--user','--no-pager','--no-legend','list']
    result=subprocess.run(cmd,capture_output=True,text=True,timeout=3)
    if result.returncode:
        raise RuntimeError('busctl list: '+result.stderr.strip()[:200])
    for line in result.stdout.splitlines():
        if 'lxqt-panel' not in line: continue
        bus=line.split()[0]
        tree=subprocess.run(['busctl','--user','--no-pager','tree',bus],
                            capture_output=True,text=True,timeout=3)
        if tree.returncode: continue
        paths=re.findall(r'/global_key_shortcuts/panel/[a-zA-Z0-9_-]+/show_hide',tree.stdout)
        paths=sorted(set(paths),key=lambda x:(not x.endswith('/menu1/show_hide'),x))
        if paths:
            return bus,paths[0]
    return None


def toggle():
    """Aciona show_hide no objeto real. Se indisponível, Alt+F1 para recuperar menu."""
    try:
        action=discover_action()
        if action:
            bus,path=action
            r=subprocess.run(['busctl','--user','call',bus,path,
                              'org.lxqt.global_key_shortcuts.client','activated'],
                             capture_output=True,text=True,timeout=3)
            if r.returncode==0:
                log('Menu alternado via '+path)
                return 0
            log('ERRO busctl '+path+': '+r.stderr.strip()[:260])
        else:
            log('Nenhum objeto de menu disponível no busctl. Verifique atalho do menu no LXQt.')
    except (OSError,subprocess.TimeoutExpired,RuntimeError) as e:
        log('ERRO no D-Bus: '+str(e))
    # Se o Fancy Menu não publicou a ação, o teclado padrão deve continuar útil.
    # Fallback só abre em algumas versões; nunca substituir o atalho normal.
    try:
        r=subprocess.run(['xdotool','key','--clearmodifiers','Alt+F1'],
                         capture_output=True,text=True,timeout=3)
        log('Fallback Alt+F1: '+('ok' if r.returncode==0 else r.stderr.strip()[:160]))
        return r.returncode
    except (OSError,subprocess.TimeoutExpired) as e:
        log('ERRO no fallback: '+str(e))
        return 1


def main():
    if os.environ.get('XDG_SESSION_TYPE') != 'x11' or 'LXQT' not in os.environ.get('XDG_CURRENT_DESKTOP','').upper():
        return 0
    try:
        from Xlib import X, XK, display
        from Xlib.ext import record
        from Xlib.protocol import rq
    except ImportError:
        log('ERRO: python-xlib ausente. Instale o pacote oficial python-xlib.')
        return 2
    dpy=display.Display(); rdpy=display.Display()
    if not rdpy.has_extension('RECORD'):
        log('ERRO: extensão X11 RECORD não disponível.')
        return 3
    code=dpy.keysym_to_keycode(XK.string_to_keysym('Super_L'))
    if not code:
        log('ERRO: keycode Super_L não encontrado no teclado.')
        return 4
    state={'pressed':False,'other':False,'last':0.0}
    def callback(reply):
        if reply.category != record.FromServer or reply.client_swapped or not reply.data:
            return
        data=reply.data
        if data[0]<2:return
        while data:
            try: event,data=rq.EventField(None).parse_binary_value(data,rdpy.display,None,None)
            except Exception as e:
                log('XRecord parse: '+str(e));return
            if event.type==X.KeyPress:
                if event.detail==code:
                    if not state['pressed']:
                        state['pressed']=True;state['other']=False
                elif state['pressed']:
                    state['other']=True
            elif event.type==X.KeyRelease and event.detail==code:
                if state['pressed'] and not state['other'] and time.monotonic()-state['last']>0.18:
                    state['last']=time.monotonic()
                    # DBus não bloqueia a thread de monitoramento de teclas.
                    subprocess.Popen([sys.executable,__file__,'--toggle'],
                                     stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,
                                     start_new_session=True)
                state['pressed']=False;state['other']=False
    ctx=rdpy.record_create_context(0,[record.AllClients],[{
      'core_requests':(0,0),'core_replies':(0,0),
      'ext_requests':(0,0,0,0),'ext_replies':(0,0,0,0),
      'delivered_events':(0,0),'device_events':(X.KeyPress,X.KeyRelease),
      'errors':(0,0),'client_started':False,'client_died':False}])
    log(f'Monitor Super iniciado (keycode={code})')
    try:rdpy.record_enable_context(ctx,callback)
    finally:rdpy.record_free_context(ctx)
    return 0

if __name__=='__main__':
    if '--toggle' in sys.argv:sys.exit(toggle())
    sys.exit(main())
