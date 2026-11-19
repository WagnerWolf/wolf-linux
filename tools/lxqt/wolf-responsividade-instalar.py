#!/usr/bin/env python3
"""Wolf LXQt: Alt+Tab residente 0.3 + Window Keeper 0.2 permanentes.

Instalação por usuário, idempotente e reversível. Não modifica os atalhos
Openbox, painéis, Picom, outros programas ou a libfm-qt.
Pode executar em chroot com --no-start na construção de uma nova instalação.
"""
from __future__ import annotations
import argparse
import ast
from datetime import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def atomic(path: Path, b: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.wolf-next5-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(b)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def read_safe(path: Path):
    if path.is_symlink():
        raise ValueError(f'Symlink inesperado, não sobrescrever: {path}')
    if not path.exists():
        return False, b'', 0o644
    if not path.is_file():
        raise ValueError(f'Destino não é arquivo regular: {path}')
    return True, path.read_bytes(), path.stat().st_mode & 0o777


def check_bindings(home: Path):
    """Não substituir o helper de um Openbox que não chama o seletor Wolf."""
    paths = (home/'.config/openbox/lxqt-rc.xml', home/'.config/openbox/rc.xml')
    for p in paths:
        if p.is_file():
            try:
                root = ET.parse(p).getroot()
                ns = '{' + root.tag.split('}')[0].strip('{') + '}' if root.tag.startswith('{') else ''
                for b in root.iter(ns+'keybind'):
                    if b.get('key') in {'A-Tab','A-S-Tab'}:
                        cmd = b.find('.//' + ns + 'command')
                        if cmd is not None and 'wolf-alt-tab-monitor' in (cmd.text or ''):
                            return
            except ET.ParseError as err:
                raise ValueError(f'XML Openbox inválido em {p}: {err}') from err
    raise ValueError('Alt+Tab Wolf não configurado no Openbox; preservado sem alterações')


def desktop_alt(home: Path) -> bytes:
    p = home/'.local/lib/wolf-alt-tab/wolf-alt-tab-daemon.py'
    return (f'[Desktop Entry]\nType=Application\nName=Wolf Alt+Tab Resident\n'
            f'Comment=Seletor por monitor residente, eventos X11\n'
            f'Exec="{sys.executable}" "{p}" --serve\n'
            f'OnlyShowIn=LXQt;\nTerminal=false\nNoDisplay=true\n'
            f'X-GNOME-Autostart-enabled=true\n').encode()


def desktop_keeper(home: Path) -> bytes:
    p = home/'.local/bin/wolf-window-keeper'
    return (f'[Desktop Entry]\nType=Application\nName=Wolf Window Keeper\n'
            f'Comment=Preserva monitor de janelas Chromium, eventos X11\n'
            f'Exec="{sys.executable}" "{p}" --fix\n'
            f'OnlyShowIn=LXQt;\nTerminal=false\nNoDisplay=true\n'
            f'X-GNOME-Autostart-enabled=true\n').encode()


def get_payload(home: Path, source_dir: Path):
    lib = home/'.local/lib/wolf-alt-tab'
    bin_dir = home/'.local/bin'
    desktop_dir = home/'.config/autostart'
    payload = {}
    for dest, name, mode in (
        (bin_dir/'wolf-alt-tab-monitor', 'wolf-alt-tab-monitor', 0o755),
        (lib/'wolf-alt-tab-daemon.py', 'wolf-alt-tab-daemon.py', 0o755),
        (lib/'wolf_alt_common.py', 'wolf_alt_common.py', 0o644),
        (lib/'wolf_alt_core.py', 'wolf_alt_core.py', 0o644),
        (bin_dir/'wolf-window-keeper', 'wolf-window-keeper.py', 0o755),
    ):
        source = source_dir/name
        if not source.is_file() or source.is_symlink():
            raise ValueError(f'Fonte ausente ou inesperada: {source}')
        data = source.read_bytes()
        if name.endswith('.py') or name == 'wolf-alt-tab-monitor':
            ast.parse(data.decode('utf-8'), filename=name)
        payload[dest] = (data, mode)
    payload[desktop_dir/'wolf-alt-tab-daemon.desktop'] = (desktop_alt(home), 0o644)
    payload[desktop_dir/'wolf-window-keeper.desktop'] = (desktop_keeper(home), 0o644)
    return payload


def validate_existing(home: Path, payload):
    alt = home/'.local/bin/wolf-alt-tab-monitor'
    existed, content, _ = read_safe(alt)
    if not existed or b'Wolf LXQt' not in content or b'Alt+Tab' not in content:
        raise ValueError('Helper Alt+Tab Wolf anterior ausente ou não reconhecido')
    previous = {}
    for path in payload:
        previous[path] = read_safe(path)
        existed, data, _ = previous[path]
        if not existed:
            continue
        if path.name == 'wolf-window-keeper' and b'Wolf Window Keeper' not in data:
            raise ValueError(f'Keeper preexistente não reconhecido: {path}')
        if path.name == 'wolf-alt-tab-daemon.desktop' and b'Wolf Alt+Tab Resident' not in data:
            raise ValueError(f'Autostart alheio, não sobrescrever: {path}')
        if path.name == 'wolf-window-keeper.desktop' and b'Wolf Window Keeper' not in data:
            raise ValueError(f'Autostart alheio, não sobrescrever: {path}')
        if path.name == 'wolf-alt-tab-monitor' and (b'Wolf LXQt' not in data or b'Alt+Tab' not in data):
            raise ValueError(f'Seletor Wolf não reconhecido: {path}')
    return previous


def install(home: Path, source_dir: Path, start=False) -> Path | None:
    home = home.resolve()
    source_dir = source_dir.resolve()
    check_bindings(home)
    payload = get_payload(home, source_dir)
    prev = validate_existing(home, payload)
    # Fallback legado original só é criado se ainda não existir.
    old_alt = prev[home/'.local/bin/wolf-alt-tab-monitor'][1]
    legacy = home/'.local/lib/wolf-alt-tab/legacy_alt_tab.py'
    legacy_exists, legacy_data, _ = read_safe(legacy)
    if not legacy_exists:
        if 'lançamento mínimo'.encode('utf-8') in old_alt:
            # Instalação parcial do 0.3: usar fallback Wolf da baseline do DevKit.
            backup_source = source_dir.parent/'alt_tab_visual.py'
            if not backup_source.is_file():
                raise ValueError('Alt+Tab já residente sem fallback e fonte antiga não disponível')
            legacy_content = backup_source.read_bytes()
        else:
            legacy_content = old_alt
        ast.parse(legacy_content.decode('utf-8'), filename='legacy_alt_tab.py')
        payload[legacy] = (legacy_content, 0o644)
        prev[legacy] = (False, b'', 0o644)

    changed = {p: v for p,v in payload.items() if not prev[p][0] or prev[p][1] != v[0] or prev[p][2] != v[1]}
    backup = None
    if changed:
        backups = home/'.local/share/wolf-lxqt-backups/performance'
        backup = backups/f'next-preview5-{datetime.now():%Y%m%d-%H%M%S-%f}-{os.getpid()}'
        backup.mkdir(parents=True, exist_ok=False)
        manifest = {'version':5, 'records':[]}
        for i,(path,(data,mode)) in enumerate(changed.items()):
            existed,old,old_mode = prev[path]
            name = f'original-{i}.bin'
            (backup/name).write_bytes(old)
            manifest['records'].append({'path':str(path),'existed':existed,'mode':old_mode,
                                        'filename':name,'old_sha':sha(old),'new_sha':sha(data)})
        (backup/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
        written=[]
        try:
            for path,(data,mode) in changed.items():
                atomic(path,data,mode)
                written.append(path)
        except Exception:
            for path in reversed(written):
                existed,old,old_mode=prev[path]
                if existed:
                    atomic(path,old,old_mode)
                else:
                    path.unlink(missing_ok=True)
            raise
    if start and os.environ.get('DISPLAY') and os.environ.get('XDG_SESSION_TYPE') != 'wayland':
        for program, args in (
            (home/'.local/lib/wolf-alt-tab/wolf-alt-tab-daemon.py', ['--serve']),
            (home/'.local/bin/wolf-window-keeper', ['--fix']),
        ):
            subprocess.Popen([sys.executable,str(program),*args],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, close_fds=True,
                             start_new_session=True)
    print('[OK] Wolf Alt+Tab 0.3 residente: launcher, daemon e autostart LXQt')
    print('[OK] Wolf Window Keeper 0.2: correção X11 e autostart permanente')
    print('[OK] Sem polling temporal; guarda de instância por DISPLAY')
    if backup:
        print('[BACKUP]',backup)
        print('[RESTAURAR]', f'python3 {Path(__file__).resolve()} --restaurar "{backup}"')
    else:
        print('[OK] Arquivos já atualizados; nenhuma substituição necessária')
    if not start:
        print('[INFO] Componentes iniciarão na próxima sessão LXQt/X11')
    return backup


def stop_alt(home: Path):
    lib=home/'.local/lib/wolf-alt-tab'
    sys.path.insert(0, str(lib))
    try:
        from wolf_alt_common import socket_path
        sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        sock.settimeout(0.25)
        with sock:
            sock.connect(str(socket_path()))
            sock.sendall(b'STOP\n')
    except (OSError, ImportError):
        pass
    finally:
        sys.path.remove(str(lib))


def restore(home: Path, folder: Path):
    home=home.resolve()
    base=(home/'.local/share/wolf-lxqt-backups/performance').resolve()
    folder=folder.expanduser().resolve()
    if not folder.is_relative_to(base) or not folder.name.startswith('next-preview5-'):
        raise ValueError('Backup fora do diretório permitido')
    m=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    if m.get('version')!=5:
        raise ValueError('Backup de versão incompatível')
    records=[]
    for rec in m.get('records',[]):
        path=Path(rec['path'])
        if not path.is_relative_to(home) or path.is_symlink() or not path.is_file():
            raise ValueError(f'Destino de restauração inválido: {path}')
        if sha(path.read_bytes()) != rec['new_sha']:
            raise ValueError(f'Arquivo foi editado após instalação: {path}')
        old=(folder/rec['filename']).read_bytes()
        if sha(old)!=rec['old_sha']:
            raise ValueError(f'Backup corrompido: {rec["filename"]}')
        records.append((path,bool(rec['existed']),old,int(rec['mode'])))
    stop_alt(home)
    for path,existed,old,mode in records:
        if existed:
            atomic(path,old,mode)
        else:
            path.unlink()
    print('[OK] Arquivos originais restaurados. Saia e entre novamente no LXQt.')
    print('[INFO] Keeper que já estiver em execução termina no logout; não foi encerrado à força.')


def status(home: Path):
    alt=home/'.config/autostart/wolf-alt-tab-daemon.desktop'
    keeper=home/'.config/autostart/wolf-window-keeper.desktop'
    for desc,p in [('Alt+Tab',alt),('Window Keeper',keeper)]:
        print(f'[{"OK" if p.is_file() else "AUSENTE"}] Autostart {desc}: {p}')
    # O socket é compatível com o daemon testado na Preview 3.
    if os.environ.get('DISPLAY') and os.environ.get('XDG_SESSION_TYPE') != 'wayland':
        lib=home/'.local/lib/wolf-alt-tab'
        sys.path.insert(0,str(lib))
        try:
            from wolf_alt_common import socket_path
            with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
                s.settimeout(0.25)
                s.connect(str(socket_path()))
                s.sendall(b'PING\n')
                print('[OK] Alt+Tab residente respondendo' if s.recv(20)==b'PONG\n' else '[AVISO] Resposta inesperada do daemon')
        except (OSError,ImportError) as err:
            print('[AVISO] Daemon Alt+Tab não responde:',err)
        finally:
            sys.path.remove(str(lib))
    # A trava fcntl do Keeper é fonte de verdade, sem pgrep nem polling.
    if os.environ.get('DISPLAY') and os.environ.get('XDG_SESSION_TYPE') != 'wayland':
        cache=home/'.cache/wolf-window-keeper'
        token=hashlib.sha256(os.environ['DISPLAY'].encode()).hexdigest()[:12]
        lock=cache/(token+'.lock')
        if not lock.is_file() or lock.is_symlink():
            print('[AVISO] Window Keeper ainda sem trava ativa nesta sessão')
        else:
            fd=os.open(str(lock),os.O_RDONLY | getattr(os,'O_NOFOLLOW',0))
            try:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    print('[AVISO] Window Keeper não está em execução nesta sessão')
                    fcntl.flock(fd,fcntl.LOCK_UN)
                except BlockingIOError:
                    print('[OK] Window Keeper ativo, instância única no DISPLAY atual')
            finally:
                os.close(fd)
    print('[INFO] Logs: ~/.cache/wolf-window-keeper.log e ~/.cache/wolf-alt-tab-daemon.log')


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-start',action='store_true',help='Para instalar a partir do chroot/ISO')
    parser.add_argument('--status',action='store_true')
    parser.add_argument('--restaurar',type=Path)
    args=parser.parse_args(argv)
    if os.geteuid()==0:
        parser.exit(2,'[BLOQUEADO] Execute como usuário LXQt normal, sem sudo\n')
    home=Path.home()
    base=Path(__file__).resolve().parent
    try:
        if args.restaurar:
            restore(home,args.restaurar)
        elif args.status:
            status(home)
        else:
            install(home,base/'responsividade',start=not args.no_start)
    except (ValueError,OSError,SyntaxError,ET.ParseError) as err:
        parser.exit(2,f'[BLOQUEADO] {err}\n')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
