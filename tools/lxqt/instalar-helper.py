#!/usr/bin/env python3
"""Instala backend da extensão NATIVA e desativa ações .desktop antigas.

Não usa sudo, não toca nos arquivos de pacote. Executar após validar e instalar
libfm-qt 2.4.0-4.2; recusa versões anteriores para evitar menus ausentes.
"""
from datetime import datetime
from pathlib import Path
import os
import shutil
import stat
import subprocess
import sys

FILES = (
    'wolf-link-here.desktop',
    'wolf-link-choose.desktop',
    'wolf-paste-link-folder.desktop',
)


def verify_version():
    r = subprocess.run(['pacman', '-Q', 'libfm-qt'], text=True, capture_output=True)
    if r.returncode or r.stdout.strip() != 'libfm-qt 2.4.0-4.2':
        raise RuntimeError('Esta etapa requer libfm-qt 2.4.0-4.2 instalada. Atual: ' +
                           (r.stdout or r.stderr).strip())


def install(root: Path, home: Path):
    root = root.resolve()
    binary = home / '.local/bin/wolf-symlink-actions'
    source = root / 'wolf-symlink-actions.py'
    if not source.is_file() or source.is_symlink():
        raise RuntimeError('Backend não encontrado')
    actions = home / '.local/share/file-manager/actions'
    backup_root = home / '.local/share/wolf-symlinks/backups' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    binary.parent.mkdir(parents=True, exist_ok=True)
    actions.mkdir(parents=True, exist_ok=True)
    entries = [binary, *(actions / name for name in FILES)]
    existing = [f for f in entries if f.exists() or f.is_symlink()]
    for file in existing:
        if file.is_symlink():
            raise RuntimeError(f'Arquivo inesperado é symlink; revisão manual: {file}')
    for file in existing:
        dest = backup_root / file.relative_to(home)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, dest)
    # Ações .desktop antigas causam duplicação nos novos menus nativos.
    for name in FILES:
        old_action = actions / name
        if old_action.exists():
            old_action.unlink()
            print('[OK] Ação antiga removida (backup preservado):', old_action)
    temp = binary.parent / (binary.name + '.wolf-new')
    shutil.copy2(source, temp)
    temp.chmod(temp.stat().st_mode | stat.S_IXUSR)
    temp.replace(binary)
    print('[OK] Backend:', binary)
    if existing:
        print('[OK] Backups:', backup_root)
    print('[INFO] Saia e entre novamente na sessão LXQt para limpar o cache dos menus.')


def main():
    try:
        verify_version()
        install(Path(__file__).resolve().parent, Path.home())
    except (RuntimeError, OSError) as exc:
        print('[BLOQUEADO]', exc, file=sys.stderr)
        return 2
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
