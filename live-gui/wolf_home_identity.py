#!/usr/bin/env python3
"""Wolf Linux: read-only identity preflight for a preserved /home.

Never changes ownership, modes or user accounts. The shell installer alone
performs user creation and narrowly scoped reconciliation after a preflight.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import stat
import sys


class IdentityDenied(ValueError):
    pass


def inspect(root: Path, username: str) -> tuple[str, str, str, str]:
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", username):
        raise IdentityDenied("Nome de usuário inválido")
    home = root / 'home'
    target = home / username
    if home.is_symlink() or not home.is_dir():
        raise IdentityDenied("/home do destino não é diretório válido")
    if target.is_symlink():
        raise IdentityDenied("/home do usuário é link simbólico: operação recusada")
    if not target.exists():
        return ('new', '', '', '')
    s = target.lstat()
    if not stat.S_ISDIR(s.st_mode):
        raise IdentityDenied("Entrada do usuário em /home não é diretório")
    uid, gid = s.st_uid, s.st_gid
    passwd = root / 'etc/passwd'
    if not passwd.is_file() or passwd.is_symlink():
        raise IdentityDenied("Banco passwd do novo sistema ausente")
    id_owner: dict[int, str] = {}
    username_uid: int | None = None
    for line in passwd.read_text(encoding='utf-8').splitlines():
        fields = line.split(':')
        if len(fields) != 7:
            continue
        try:
            numeric_uid = int(fields[2])
        except ValueError:
            continue
        id_owner[numeric_uid] = fields[0]
        if fields[0] == username:
            username_uid = numeric_uid
    if username_uid is not None:
        # Retomada: nunca realocar a identidade de um usuário já criado.
        return ('existing', str(uid), str(gid), str(username_uid))
    if uid == 0:
        # Laboratórios podem ter /home/wolf criado por root: confirmação
        # localizada será solicitada depois de criar a conta.
        return ('root-owned', str(uid), str(gid), '')
    if not 1000 <= uid <= 60000:
        raise IdentityDenied(f'UID anterior {uid} fora do intervalo seguro 1000–60000')
    claimed_by = id_owner.get(uid)
    if claimed_by and claimed_by != username:
        raise IdentityDenied(f'UID antigo {uid} já pertence a {claimed_by}; intervenção manual necessária')
    return ('reuse-uid', str(uid), str(gid), str(uid))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['inspect'])
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--user', required=True)
    opts = parser.parse_args()
    try:
        fields = inspect(opts.root, opts.user)
    except (IdentityDenied, OSError) as exc:
        print(f'[ERRO] Preflight da home preservada: {exc}', file=sys.stderr)
        return 2
    for field in fields:
        sys.stdout.buffer.write(field.encode('utf-8') + b'\0')
    return 0


if __name__ == '__main__':
    sys.exit(main())
