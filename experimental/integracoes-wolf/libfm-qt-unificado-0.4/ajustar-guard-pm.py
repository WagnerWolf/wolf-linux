#!/usr/bin/env python3
"""Adaptação experimental do Wolf Package Manager 0.3.7 para reconhecer libfm-qt 4.2.

Mantém a revisão 4.1 reconhecida. Não declara a integração USB homologada.
"""
from pathlib import Path
from datetime import datetime
import argparse
import shutil
import sys

ORIGINAL = "active = installed == WOLF_VERSION"
NEW = "active = installed in (WOLF_VERSION, '2.4.0-4.2')"
VERSION = "WOLF_VERSION = '2.4.0-4.1'"


def transform(s: str):
    if s.count(VERSION) != 1 or s.count(ORIGINAL) != 1:
        raise ValueError('Guard desconhecido ou já alterado: não aplicar automaticamente')
    return s.replace(ORIGINAL, NEW, 1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('mode', choices=['check', 'apply'])
    ap.add_argument('--path', required=True, type=Path)
    a = ap.parse_args()
    p = a.path.expanduser().resolve(strict=True)
    home = Path.home().resolve()
    allowed = [Path('/usr/local/lib/wolf-linux/package-manager/wolfpkg/upgrade_guard.py')]
    # When running sudo, HOME changes; explicitly allow per-user suffix under /home.
    if p not in allowed and not (p.name == 'upgrade_guard.py' and
        p.parent.name == 'wolfpkg' and p.parent.parent.name == 'wolf-package-manager'
        and '.local/share' in str(p)):
        ap.error('Caminho inesperado. Use apenas o upgrade_guard.py instalado do Wolf Package Manager')
    if p.is_symlink() or not p.is_file():
        ap.error('Arquivo inválido ou symlink')
    s = p.read_text(encoding='utf-8')
    if a.mode == 'check':
        if NEW in s:
            print('[OK] Guard já reconhece 2.4.0-4.2 como versão personalizada.')
        elif ORIGINAL in s and VERSION in s:
            print('[PENDENTE] Guard 0.3.7 reconhece somente 2.4.0-4.1.')
        else:
            print('[INCOMPATÍVEL] Guard inesperado: não editar sem revisão.')
            return 2
        return 0
    try:
        new = transform(s)
    except ValueError as exc:
        print('[BLOQUEADO]', exc, file=sys.stderr)
        return 2
    backup = p.with_name(p.name + '.bak-wolf-4.2-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
    shutil.copy2(p, backup)
    p.write_text(new, encoding='utf-8')
    print('[OK] Backup:', backup)
    print('[OK] Guard reconhece 4.1 e 4.2, mantendo exigência do IgnorePkg.')
    print('[ATENÇÃO] Auditoria de integração 4.2 continuará PENDENTE até homologação no hardware.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
