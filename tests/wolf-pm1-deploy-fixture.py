#!/usr/bin/env python3
"""Promocao reversivel do Wolf Package Manager no prefixo do sistema.

Nao executa pacman/yay. Para testes isolados, WOLF_PM_DEPLOY_ROOT=/tmp/... permite
instalacao de arquivos num prefixo ficticio, sem root.
"""
from __future__ import annotations
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

SOURCE = Path(__file__).resolve().parent / 'fontes'
V = '1.0.0'
DESTINATIONS = {
    'app': '/usr/local/lib/wolf-linux/package-manager',
    'launcher': '/usr/local/bin/wolf-package-manager',
    'desktop': '/usr/share/applications/wolf-package-manager.desktop',
    'autostart': '/etc/xdg/autostart/wolf-package-manager.desktop',
    'icon': '/usr/share/icons/hicolor/256x256/apps/wolf-package-manager.png',
}
BASE = '/var/lib/wolf-linux/package-manager-backups'


def root_path(root: Path, absolute: str) -> Path:
    return root / absolute.lstrip('/')


def remove(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def clone(source: Path, dest: Path) -> None:
    if source.is_dir():
        shutil.copytree(source, dest, symlinks=True)
    else:
        shutil.copy2(source, dest, follow_symlinks=False)


def valid_source():
    required = [SOURCE/'main.py', SOURCE/'wolfpkg/app.py',
                SOURCE/'wolfpkg/backend.py', SOURCE/'wolfpkg/assets/wolf-logo.png']
    for file in required:
        if not file.is_file() or file.is_symlink():
            raise RuntimeError(f'Fonte ausente ou insegura: {file}')
    if f"VERSION = '{V}'" not in (SOURCE/'wolfpkg/app.py').read_text():
        raise RuntimeError('Versao declarada diferente da release 1.0.0.')


def validate_destinations(root):
    # Nao seguir links simbolicos nos objetos gerenciados nem em ancestrais.
    for pathstr in DESTINATIONS.values():
        p = root_path(root, pathstr)
        for x in (p, *p.parents):
            if x.is_symlink():
                raise RuntimeError(f'Link simbolico em caminho gerenciado: {x}')


def backup(root: Path, backup_dir: Path):
    backup_dir.mkdir(mode=0o700, parents=True)
    (backup_dir/'data').mkdir(mode=0o700)
    state = {'version': V, 'status': 'preparing', 'entries': {},
             'created': datetime.now().isoformat(timespec='seconds')}
    for key, absolute in DESTINATIONS.items():
        path = root_path(root, absolute)
        existed = path.exists()
        state['entries'][key] = {'path': absolute, 'existed': existed}
        if existed:
            clone(path, backup_dir/'data'/key)
    write_state(backup_dir, state)
    return state


def write_state(directory, state):
    p = directory/'manifest.json'
    tmp = directory/'manifest.json.new'
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
    tmp.replace(p)


def restore(root: Path, directory: Path, state: dict):
    for key, entry in state['entries'].items():
        path = root_path(root, entry['path'])
        remove(path)
        if entry['existed']:
            original = directory/'data'/key
            if not original.exists():
                raise RuntimeError(f'Backup original ausente: {original}')
            path.parent.mkdir(parents=True, exist_ok=True)
            clone(original, path)


def install_files(root):
    app = root_path(root, DESTINATIONS['app'])
    app.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.wolf-pm-1.0.0-', dir=app.parent))
    try:
        shutil.copy2(SOURCE/'main.py', stage/'main.py')
        shutil.copytree(SOURCE/'wolfpkg', stage/'wolfpkg',
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        (stage/'wolfpkg/askpass.sh').chmod(0o755)
        stage.chmod(0o755)  # instalado pelo root, mas executado por usuario normal
        remove(app)
        stage.replace(app)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    data = {
        'launcher': ('#!/bin/sh\nexec /usr/bin/python3 /usr/local/lib/wolf-linux/package-manager/main.py "$@"\n', 0o755),
        'desktop': ('[Desktop Entry]\nType=Application\nName=Wolf Package Manager\nGenericName=Gerenciador de pacotes\nComment=Gerenciar pacotes Arch, Chaotic-AUR e AUR (yay)\nExec=/usr/local/bin/wolf-package-manager\nTryExec=/usr/local/bin/wolf-package-manager\nIcon=wolf-package-manager\nCategories=System;PackageManager;Qt;\nTerminal=false\nStartupNotify=true\n', 0o644),
        'autostart': ('[Desktop Entry]\nType=Application\nName=Wolf Package Manager (Monitor)\nComment=Monitor de atualizacoes do Wolf Linux\nExec=/usr/local/bin/wolf-package-manager --tray\nTryExec=/usr/local/bin/wolf-package-manager\nIcon=wolf-package-manager\nOnlyShowIn=KDE;\nTerminal=false\n', 0o644),
    }
    for key, (content, mode) in data.items():
        p = root_path(root, DESTINATIONS[key])
        p.parent.mkdir(parents=True, exist_ok=True)
        remove(p)
        p.write_text(content, encoding='utf-8')
        p.chmod(mode)
    icon = root_path(root, DESTINATIONS['icon'])
    icon.parent.mkdir(parents=True, exist_ok=True)
    remove(icon)
    shutil.copy2(SOURCE/'wolfpkg/assets/wolf-logo.png', icon)
    icon.chmod(0o644)


def run_install(root: Path, base: Path):
    valid_source()
    validate_destinations(root)
    pointer = base/'last.json'
    if pointer.exists():
        last = json.loads(pointer.read_text(encoding='utf-8'))
        prior = base/last['directory']
        if prior.exists():
            prior_state = json.loads((prior/'manifest.json').read_text(encoding='utf-8'))
            if prior_state.get('status') == 'preparing':
                raise RuntimeError('Uma instalacao foi interrompida; execute --undo antes.')
    backupname = datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid())
    directory = base/backupname
    state = backup(root, directory)
    base.mkdir(mode=0o700, parents=True, exist_ok=True)
    pointer.write_text(json.dumps({'directory': backupname}), encoding='utf-8')
    try:
        install_files(root)
        assert f"VERSION = '{V}'" in root_path(root,DESTINATIONS['app']).joinpath('wolfpkg/app.py').read_text()
    except Exception:
        print('[ERRO] Instalacao falhou; restaurando backup...', file=sys.stderr)
        restore(root, directory, state)
        state['status'] = 'rolled_back'
        write_state(directory, state)
        pointer.unlink(missing_ok=True)
        raise
    state['status'] = 'installed'
    write_state(directory, state)
    print('[OK] Wolf Package Manager 1.0.0 instalado em /usr/local/lib/wolf-linux/package-manager')
    print('[OK] Backup anterior:', directory)
    print('[OK] Preferencias do usuario e pacotes nao foram alterados.')
    print('Saia/entre na sessao KDE, ou inicie /usr/local/bin/wolf-package-manager.')


def run_undo(root: Path, base: Path):
    pointer = base/'last.json'
    if not pointer.exists():
        raise RuntimeError('Nao ha instalacao do pacote com backup para desfazer.')
    entry = json.loads(pointer.read_text(encoding='utf-8'))
    directory = base/entry['directory']
    state = json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
    validate_destinations(root)
    restore(root, directory, state)
    state['status'] = 'rolled_back'
    write_state(directory, state)
    pointer.unlink()
    print('[OK] Arquivos anteriores restaurados:', directory)


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--install', action='store_true')
    group.add_argument('--undo', action='store_true')
    group.add_argument('--status', action='store_true')
    args = parser.parse_args()
    root = Path(os.environ.get('WOLF_PM_DEPLOY_ROOT', '/')).resolve()
    if root == Path('/') and os.geteuid() != 0 and not args.status:
        parser.error('Instalacao de sistema exige sudo. Utilize instalar-gerenciador.sh.')
    base = root_path(root, BASE)
    try:
        if args.install:
            run_install(root, base)
        elif args.undo:
            run_undo(root, base)
        else:
            app = root_path(root, DESTINATIONS['app'])/'wolfpkg/app.py'
            if app.is_file():
                import re
                m = re.search(r"^VERSION = '([^']+)'", app.read_text(), re.M)
                print('Versao instalada:', m.group(1) if m else 'nao identificada')
            else:
                print('Gerenciador de sistema nao encontrado.')
            print('Backup do ultimo upgrade:', 'sim' if (base/'last.json').exists() else 'nao')
    except (RuntimeError, OSError, ValueError, AssertionError) as exc:
        print('[ERRO]', exc, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
