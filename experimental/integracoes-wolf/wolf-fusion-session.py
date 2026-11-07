#!/usr/bin/env python3
"""Aplica Fusion a sessão LXQt com backup/reversão; não modifica GTK ou pacotes."""
from __future__ import annotations
import argparse
import configparser
from datetime import datetime
from pathlib import Path
import json, os, shutil, tempfile

USER_HOME=Path.home()
FILES={'appearance': USER_HOME/'.config/lxqt/lxqt.conf', 'session':USER_HOME/'.config/lxqt/session.conf'}
BACKUPS=USER_HOME/'wolf-backups/qt-fusion'

def ini_read(path):
    config=configparser.RawConfigParser(interpolation=None, strict=False)
    config.optionxform=str
    if path.is_file():config.read(path,encoding='utf-8')
    return config

def check():
    for key,path in FILES.items():
        if path.is_symlink():
            print(f'[AVISO] Link simbólico em {path}; aplicação recusada.')
            continue
        cp=ini_read(path)
        section,attr=('Qt','style') if key=='appearance' else ('Environment','QT_STYLE_OVERRIDE')
        print(f'[QT] {path}: [{section}] {attr}={cp.get(section,attr,fallback="(ausente)")}')
    print('[INFO] Estilo da sessão atual: QT_STYLE_OVERRIDE='+os.environ.get('QT_STYLE_OVERRIDE','(não definido)'))
    print('[INFO] O novo estilo exige encerrar e abrir a sessão; aplicativos abertos não mudam retroativamente.')

def atomic_write(path,content):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix='.wolf-fusion-',dir=str(path.parent))
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        if path.exists():os.chmod(name,path.stat().st_mode & 0o777)
        os.replace(name,path)
    finally:
        if os.path.exists(name):os.unlink(name)

def apply():
    for path in FILES.values():
        if path.is_symlink():raise RuntimeError(f'Link simbólico não permitido: {path}')
    snapshot=BACKUPS/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    snapshot.mkdir(parents=True,exist_ok=False)
    manifest={}
    for key,path in FILES.items():
        was_file=path.is_file()
        manifest[key]={'existed':was_file,'path':str(path)}
        if was_file:shutil.copy2(path,snapshot/(key+'.bak'))
    (snapshot/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    for key,path in FILES.items():
        cp=ini_read(path)
        section,attr=('Qt','style') if key=='appearance' else ('Environment','QT_STYLE_OVERRIDE')
        if not cp.has_section(section):cp.add_section(section)
        cp.set(section,attr,'Fusion')
        import io
        with io.StringIO() as out:
            cp.write(out,space_around_delimiters=False)
            atomic_write(path,out.getvalue())
    print(f'[OK] Qt Fusion salvo. Backup: {snapshot}')
    check()

def restore(snapshot):
    snapshot=snapshot.expanduser().resolve()
    if BACKUPS.resolve() not in snapshot.parents: raise RuntimeError('Backup fora da pasta Wolf.')
    manifest=json.loads((snapshot/'manifest.json').read_text(encoding='utf-8'))
    for key,path in FILES.items():
        if path.is_symlink():raise RuntimeError('Destino é link simbólico: '+str(path))
        if manifest[key]['path']!=str(path): raise RuntimeError('Backup pertence a outro HOME.')
    for key,path in FILES.items():
        if manifest[key]['existed']:
            old=(snapshot/(key+'.bak'))
            if not old.is_file(): raise RuntimeError('Backup incompleto: '+str(old))
            atomic_write(path,old.read_text(encoding='utf-8'))
        elif path.exists():
            path.unlink()
    print('[OK] Configuração anterior restaurada. Reinicie a sessão LXQt.')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    group=p.add_mutually_exclusive_group(required=True)
    group.add_argument('--check',action='store_true')
    group.add_argument('--apply',action='store_true')
    group.add_argument('--restore',type=Path,metavar='PASTA_DE_BACKUP')
    args=p.parse_args()
    if os.geteuid()==0: p.error('Execute como usuário normal, sem sudo.')
    try:
        if args.check:check()
        elif args.apply:apply()
        else:restore(args.restore)
    except (OSError,ValueError,configparser.Error,RuntimeError) as exc:p.exit(1,'[ERRO] '+str(exc)+'\n')

if __name__=='__main__':main()
