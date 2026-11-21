#!/usr/bin/env python3
"""Guard + repair *missing* Wolf assets in a build project, never overwrite differing files.

Source DevKit must have matching independent assets/ and branding-assets/ copies.
No elevated permissions required. No destructive changes. A staged-tree check is
available to ensure the Live installer receives the same files.
"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import sys
import tempfile


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.digest()


def no_symlinks(path: Path, *, label: str) -> None:
    # Catch symlinked parents as well as individual file destinations.
    for p in [path, *path.parents]:
        if p.is_symlink():
            raise ValueError(f'{label}: symlink não permitido: {p}')


def verify_asset(path: Path, digest: bytes, label: str) -> bool:
    no_symlinks(path, label=label)
    if not path.exists():
        return False
    if not path.is_file() or not path.stat().st_size:
        raise ValueError(f'{label}: arquivo inválido: {path}')
    if sha256(path) != digest:
        raise ValueError(f'{label}: conteúdo divergente; não substituído: {path}')
    return True


def restore_missing(source: Path, dest: Path, digest: bytes) -> None:
    no_symlinks(dest, label='restauração')
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.wolf-asset-', dir=dest.parent)
    os.close(fd)
    try:
        shutil.copyfile(source, tmp)
        os.chmod(tmp, 0o644)
        if sha256(Path(tmp)) != digest:
            raise ValueError(f'cópia divergente: {dest}')
        if dest.exists() or dest.is_symlink():
            # A destination appeared during copying; never overwrite.
            raise ValueError(f'destino criado durante cópia: {dest}')
        os.replace(tmp, dest)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path, help='DevKit com assets originais')
    parser.add_argument('--project', required=True, type=Path, help='Projeto de build')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--repair', action='store_true', help='restaura SOMENTE arquivos ausentes')
    mode.add_argument('--check', action='store_true', help='verifica sem modificar')
    mode.add_argument('--staged', type=Path, help='verifica cópia airootfs da Live sem modificar')
    a = parser.parse_args()

    source = a.source.absolute()
    project = a.project.absolute()
    primary_source = source / 'assets'
    backup_source = source / 'branding-assets'
    no_symlinks(primary_source, label='origem')
    no_symlinks(backup_source, label='origem')
    if not primary_source.is_dir() or not backup_source.is_dir():
        raise ValueError('DevKit não contém as duas árvores assets/ e branding-assets/')
    originals = sorted(p.relative_to(primary_source) for p in primary_source.rglob('*') if p.is_file())
    if not originals:
        raise ValueError('DevKit sem assets; interrompendo para evitar ISO incompleta')
    restored = []
    for rel in originals:
        src = primary_source / rel
        reserve = backup_source / rel
        no_symlinks(src, label='asset de origem')
        no_symlinks(reserve, label='asset de reserva')
        if not src.is_file() or not reserve.is_file() or not src.stat().st_size:
            raise ValueError(f'asset original/reserva ausente ou vazio: {rel}')
        digest = sha256(src)
        if sha256(reserve) != digest:
            raise ValueError(f'asset original diverge da reserva: {rel}')
        locations = ([a.staged / rel] if a.staged is not None else
                     [project / 'assets' / rel, project / 'branding-assets' / rel])
        for dst in locations:
            if verify_asset(dst, digest, str(rel)):
                continue
            if a.repair:
                restore_missing(reserve, dst, digest)
                restored.append(str(dst.relative_to(project)))
            else:
                raise ValueError(f'asset obrigatório ausente: {dst}')
    if a.repair:
        for item in restored:
            print(f'[OK] Recuperado asset original: {item}')
    print(f'[OK] {len(originals)} assets Wolf verificados; {len(restored)} arquivo(s) restaurado(s).')


if __name__ == '__main__':
    try:
        run()
    except (OSError, ValueError) as exc:
        print(f'[ERRO] Verificação de assets Wolf: {exc}', file=sys.stderr)
        sys.exit(1)
