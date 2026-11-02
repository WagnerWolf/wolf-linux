#!/usr/bin/env python3
"""Proteção de upgrade automático da libfm-qt Wolf no pacman.conf.

Não é uma trava de instalações explícitas (-S/-U). Nunca altera outros IgnorePkg.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
from datetime import datetime

BEGIN = '# WOLF_LIBFM_GUARD_BEGIN'
END = '# WOLF_LIBFM_GUARD_END'
MARK = BEGIN + '\nIgnorePkg = libfm-qt\n' + END + '\n'


def _section(text: str) -> re.Match:
    match = re.search(r'(?m)^\s*\[options\]\s*$', text)
    if match is None:
        raise ValueError('[options] não encontrado no pacman.conf; nenhuma alteração realizada.')
    return match


def parse(text: str) -> tuple[bool, bool]:
    """Retorna (proteção Wolf presente, IgnorePkg efetivo em [options])."""
    _section(text)
    # Não assumir que [options] é primeira seção: analisar sequencialmente.
    inside = False
    protected = False
    ignored = False
    for line in text.splitlines():
        match = re.match(r'^\s*\[([^]]+)\]\s*$', line)
        if match:
            inside = match.group(1).lower() == 'options'
            continue
        if not inside:
            continue
        if line.strip() == BEGIN:
            protected = True
        uncommented = line.split('#', 1)[0]
        m = re.match(r'^\s*IgnorePkg\s*=\s*(.*)$', uncommented, re.I)
        if m and 'libfm-qt' in m.group(1).split():
            ignored = True
    return protected and BEGIN in text and END in text, ignored


def update(text: str, action: str) -> str:
    protected, _ = parse(text)
    if action == 'install':
        if protected:
            return text
        match = _section(text)
        # Cabeçalho e linhas existentes preservados; seção [options] é a correta.
        at = match.end()
        if at < len(text) and text[at] == '\n':
            at += 1
        return text[:at] + MARK + text[at:]
    if action == 'remove':
        if not protected:
            return text
        if text.count(BEGIN) != 1 or text.count(END) != 1 or MARK not in text:
            raise ValueError('Bloco Wolf modificado manualmente; revisão necessária.')
        return text.replace(MARK, '', 1)
    raise ValueError('Ação inválida')


def apply(path: Path, action: str) -> tuple[bool, str]:
    if path.is_symlink() or not path.is_file():
        raise ValueError('pacman.conf ausente ou link simbólico')
    data = path.read_text(encoding='utf-8')
    new = update(data, action)
    if data == new:
        return False, 'Sem mudanças; configuração já corresponde ao solicitado.'
    backup = path.with_name(path.name + '.wolf-backup-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    shutil.copy2(path, backup, follow_symlinks=False)
    fd, temp = tempfile.mkstemp(prefix='.wolf-libfm-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(new)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, stat.S_IMODE(path.stat().st_mode))
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return True, f'Configuração atualizada; backup: {backup}'


def main():
    p = argparse.ArgumentParser(description='Proteção Wolf do libfm-qt (IgnorePkg)')
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument('--check', action='store_true')
    group.add_argument('--install', action='store_true')
    group.add_argument('--remove', action='store_true')
    p.add_argument('--config', type=Path, default=Path('/etc/pacman.conf'))
    args = p.parse_args()
    try:
        path = args.config
        if path.is_symlink():
            raise ValueError('Não operar em symlink')
        if args.check:
            marker, ignored = parse(path.read_text(encoding='utf-8'))
            print(f'[WOLF] Marcador: {"sim" if marker else "não"}; IgnorePkg libfm-qt: {"sim" if ignored else "não"}')
            return 0 if marker and ignored else 3
        changed, msg = apply(path, 'install' if args.install else 'remove')
        print('[OK]' if changed else '[INFO]', msg)
        return 0
    except (OSError, UnicodeError, ValueError) as exc:
        print('[ERRO]', exc)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
