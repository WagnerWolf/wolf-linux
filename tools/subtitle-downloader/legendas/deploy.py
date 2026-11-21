#!/usr/bin/env python3
"""Integra Wolf Subtitle Downloader 0.3 ao Dolphin no KDE Plasma 6.

Permite restaurar arquivos anteriores; nunca le nem modifica o chaveiro.
"""
from __future__ import annotations
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import sys

SOURCE = Path(__file__).resolve().parent/'fontes'
HOME = Path(os.environ.get('WOLF_SUBTITLE_TEST_HOME', str(Path.home()))).resolve()
APP = HOME/'.local/share/wolf-subtitle-downloader'
BIN = HOME/'.local/bin/wolf-subtitle-downloader'
DESKTOP = HOME/'.local/share/applications/wolf-subtitle-downloader.desktop'
KDE = HOME/'.local/share/kio/servicemenus/wolf-subtitle-downloader-kde.desktop'
STATE = HOME/'.local/state/wolf-subtitle-downloader-installer'
FILES = {file: APP/file for file in ('gui.py','backend.py','helpers.py','credentials.py')}
PATHS = {**FILES, 'launcher': BIN, 'desktop': DESKTOP, 'kde': KDE}


def guard():
    if os.geteuid() == 0 and 'WOLF_SUBTITLE_TEST_HOME' not in os.environ:
        raise RuntimeError('Execute como usuario normal, sem sudo.')
    for p in PATHS.values():
        for ancestor in (p, *p.parents):
            if ancestor == HOME.parent: break
            if ancestor.is_symlink():
                raise RuntimeError(f'Link simbolico no destino: {ancestor}')


def copy_file(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def snapshot():
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    identifier = datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+str(os.getpid())
    folder = STATE/identifier
    folder.mkdir(mode=0o700)
    rec = {'status':'pending','files':{},'created':datetime.now().isoformat()}
    for key,path in PATHS.items():
        existed = path.is_file()
        if path.exists() and not existed:
            raise RuntimeError(f'Destino inesperado (nao arquivo): {path}')
        rec['files'][key]={'path':str(path),'existed':existed}
        if existed:
            copy_file(path,folder/key)
    (folder/'manifest.json').write_text(json.dumps(rec,indent=2,ensure_ascii=False),encoding='utf-8')
    (STATE/'last.json').write_text(json.dumps({'folder':identifier}),encoding='utf-8')
    return folder,rec


def restore(folder,rec):
    for key,item in rec['files'].items():
        p=Path(item['path'])
        if p.is_file(): p.unlink()
        if item['existed']: copy_file(folder/key,p)
    rec['status']='undone'
    (folder/'manifest.json').write_text(json.dumps(rec,indent=2,ensure_ascii=False),encoding='utf-8')
    (STATE/'last.json').unlink(missing_ok=True)


def install():
    guard()
    missing = [f for f in FILES if not (SOURCE/f).is_file()]
    if missing: raise RuntimeError(f'Faltam fontes originais: {missing}')
    python = APP/'.venv/bin/python'
    if not python.is_file():
        raise RuntimeError('Ambiente Subliminal ausente. Execute ./instalar-legendas.sh para prepara-lo.')
    existing=STATE/'last.json'
    if existing.is_file():
        old=STATE/json.loads(existing.read_text())['folder']
        state=json.loads((old/'manifest.json').read_text())
        if state.get('status')=='pending':
            raise RuntimeError('Instalacao anterior interrompida. Execute --undo antes.')
    folder,rec=snapshot()
    try:
        for file,dest in FILES.items(): copy_file(SOURCE/file,dest)
        exe=str(BIN)
        BIN.parent.mkdir(parents=True,exist_ok=True)
        BIN.write_text('''#!/usr/bin/env bash
set -euo pipefail
APPDIR="$HOME/.local/share/wolf-subtitle-downloader"
if [[ "${1:-}" == '--quick' ]]; then
  shift
  [[ $# -eq 1 ]] || { echo 'Uso: wolf-subtitle-downloader --quick ARQUIVO' >&2; exit 2; }
  exec "$APPDIR/.venv/bin/python" "$APPDIR/backend.py" --quick "$1"
fi
exec /usr/bin/python3 "$APPDIR/gui.py" "$@"
''',encoding='utf-8')
        BIN.chmod(0o755)
        DESKTOP.parent.mkdir(parents=True,exist_ok=True)
        DESKTOP.write_text(f'''[Desktop Entry]
Type=Application
Version=1.0
Name=Wolf Subtitle Downloader
Name[pt_BR]=Wolf Subtitle Downloader
Comment=Buscar e baixar legendas para filmes e series
Exec="{exe}" %f
Icon=video-x-generic
Terminal=false
Categories=AudioVideo;Utility;
StartupNotify=true
MimeType=video/*;
''',encoding='utf-8')
        DESKTOP.chmod(0o644)
        KDE.parent.mkdir(parents=True,exist_ok=True)
        KDE.write_text(f'''[Desktop Entry]
Type=Service
MimeType=video/*;application/x-matroska;
Actions=wolfSubtitleSearch;wolfSubtitleQuick;
X-KDE-RequiredNumberOfUrls=1
X-KDE-Protocols=file
X-KDE-Priority=TopLevel

[Desktop Action wolfSubtitleSearch]
Name=Buscar legendas...
Icon=edit-find
Exec="{exe}" %f

[Desktop Action wolfSubtitleQuick]
Name=Baixar melhor legenda PT-BR
Icon=download
Exec="{exe}" --quick %f
''',encoding='utf-8')
        KDE.chmod(0o755) # obrigatorio no KDE 6 para service menus de usuario
    except Exception:
        restore(folder,rec)
        raise
    rec['status']='installed'
    (folder/'manifest.json').write_text(json.dumps(rec,indent=2,ensure_ascii=False),encoding='utf-8')
    print('[OK] Wolf Subtitle Downloader integrado ao Dolphin (KDE Plasma 6).')
    print('[OK] Backup dos arquivos anteriores:',folder)
    print('[OK] Chaveiro OpenSubtitles preservado.')
    print('Feche e reabra o Dolphin e teste com botao direito sobre um .mkv ou .mp4.')


def undo():
    guard()
    p=STATE/'last.json'
    if not p.is_file(): raise RuntimeError('Nenhuma instalacao com backup deste pacote encontrada.')
    folder=STATE/json.loads(p.read_text())['folder']
    rec=json.loads((folder/'manifest.json').read_text())
    restore(folder,rec)
    print('[OK] Arquivos anteriores restaurados. Credenciais no chaveiro preservadas.')


def status():
    guard()
    print('Aplicativo:', 'presente' if (APP/'gui.py').is_file() else 'ausente')
    print('Ambiente Python:', 'presente' if (APP/'.venv/bin/python').is_file() else 'ausente')
    print('Menu Dolphin:', 'presente' if KDE.is_file() else 'ausente')
    print('Backup do instalador:', 'presente' if (STATE/'last.json').is_file() else 'ausente')


def main():
    p=argparse.ArgumentParser()
    g=p.add_mutually_exclusive_group(required=True)
    g.add_argument('--install',action='store_true')
    g.add_argument('--status',action='store_true')
    g.add_argument('--undo',action='store_true')
    args=p.parse_args()
    try:
        if args.install:install()
        elif args.undo:undo()
        else:status()
        return 0
    except (RuntimeError,OSError,ValueError) as exc:
        print('[ERRO]',exc,file=sys.stderr)
        return 1

if __name__=='__main__':
    sys.exit(main())
