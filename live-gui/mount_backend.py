#!/usr/bin/env python3
"""Wolf Live Mount backend — strictly read-only, local, explicit mounting.

No partition table, activation of LVM, formatting, repair, or auto-mounts.
GUI calls inventory without privileges and mount/unmount via sudo -n.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path('/run/media/wolf')
PREFIX = 'wolf-ro-'
SUPPORTED = {
    'ext2': ('ext2', 'ro,nosuid,nodev,noexec'),
    'ext3': ('ext3', 'ro,noload,nosuid,nodev,noexec'),
    'ext4': ('ext4', 'ro,noload,nosuid,nodev,noexec'),
    'xfs': ('xfs', 'ro,norecovery,nosuid,nodev,noexec'),
    'btrfs': ('btrfs', 'ro,nosuid,nodev,noexec'),
    'vfat': ('vfat', 'ro,nosuid,nodev,noexec,umask=022'),
    'exfat': ('exfat', 'ro,nosuid,nodev,noexec,umask=022'),
    'ntfs': ('ntfs3', 'ro,nosuid,nodev,noexec'),
    'ntfs3': ('ntfs3', 'ro,nosuid,nodev,noexec'),
}


def _run(cmd: list[str], timeout: int = 20) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=False, timeout=timeout)


def flatten(nodes: list[dict]) -> list[dict]:
    out = []
    for node in nodes:
        node = dict(node)
        children = node.pop('children', []) or []
        out.append(node)
        out.extend(flatten(children))
    return out


def disk_inventory(raw: str | None = None) -> list[dict]:
    if raw is None:
        found = _run(['lsblk', '-J', '-b', '-o',
                      'PATH,NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS,LABEL,PKNAME,RO'], 10)
        if found.returncode:
            raise RuntimeError(found.stderr.strip() or 'lsblk falhou')
        raw = found.stdout
    nodes = flatten(json.loads(raw)['blockdevices'])
    result = []
    for n in nodes:
        path = str(n.get('path') or '')
        if not path.startswith('/dev/'):
            continue
        fs = str(n.get('fstype') or '').lower()
        mps = [x for x in (n.get('mountpoints') or []) if x]
        result.append({
            'path': path, 'name': str(n.get('name') or ''), 'type': str(n.get('type') or ''),
            'fstype': fs, 'label': str(n.get('label') or ''),
            'size': int(n.get('size') or 0), 'mountpoints': mps,
            'supported': fs in SUPPORTED and n.get('type') in ('part', 'lvm'),
            'readonly': str(n.get('ro') or '0').lower() in ('1', 'true'),
        })
    return result


def permitted_path(path: str, volumes: list[dict]) -> dict:
    if not re.fullmatch(r'/dev/[A-Za-z0-9_+./-]{1,180}', path) or '..' in path.split('/'):
        raise ValueError('Caminho de dispositivo inválido')
    candidates = [v for v in volumes if v['path'] == path]
    if len(candidates) != 1 or not candidates[0]['supported']:
        raise ValueError('Selecione uma partição ou volume lógico com sistema de arquivos suportado')
    return candidates[0]


def managed_path(volume: dict) -> Path:
    # Path derived only from a kernel-assigned devpath; never from filesystem label.
    name = Path(volume['path']).name
    if not re.fullmatch(r'[A-Za-z0-9_.+-]{1,80}', name):
        raise ValueError('Identificador do volume não suportado')
    return ROOT / (PREFIX + name)


def ensure_live_root() -> None:
    if os.geteuid() != 0:
        raise PermissionError('Operação exige privilégios de administrador')
    if not Path('/etc/wolf-linux-live-build').is_file():
        raise PermissionError('Montagens Wolf autorizadas somente na Live')


def existing_mounts(path: str) -> list[str]:
    result = _run(['findmnt', '-r', '-n', '-o', 'TARGET', '--source', path])
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.strip() or 'Erro consultando montagens')
    return result.stdout.splitlines()


def mount_readonly(path: str) -> str:
    ensure_live_root()
    volumes = disk_inventory()
    item = permitted_path(path, volumes)
    if item['mountpoints'] or existing_mounts(path):
        raise RuntimeError('Volume já montado. Verifique o ponto de montagem existente.')
    if not Path(path).exists() or not Path(path).is_block_device():
        raise RuntimeError('Dispositivo não é um bloco válido')
    destination = managed_path(item)
    # Never reuse a pre-existing symlink or directory created by another process.
    ROOT.mkdir(mode=0o755, parents=True, exist_ok=True)
    if ROOT.is_symlink():
        raise RuntimeError('Diretório de montagem inseguro')
    if destination.exists() or destination.is_symlink():
        raise RuntimeError('Ponto de montagem já existe. Use Desmontar ou peça diagnóstico.')
    destination.mkdir(mode=0o755)
    fs, opts = SUPPORTED[item['fstype']]
    try:
        status = _run(['mount', '-t', fs, '-o', opts, '--', path, str(destination)], 40)
        if status.returncode and item['fstype'] in ('ntfs', 'ntfs3'):
            status = _run(['mount', '-t', 'ntfs-3g', '-o', 'ro,nosuid,nodev,noexec',
                           '--', path, str(destination)], 40)
        if status.returncode:
            raise RuntimeError(status.stderr.strip() or 'Não foi possível montar em leitura')
        # Re-check the actual kernel mount flags instead of trusting mount's exit status.
        check = _run(['findmnt', '-n', '-o', 'OPTIONS', '--target', str(destination)])
        options = check.stdout.strip().split(',')
        if check.returncode or 'ro' not in options or 'rw' in options:
            _run(['umount', '--', str(destination)])
            raise RuntimeError('Montagem sem garantia de somente leitura; operação revertida')
        return str(destination)
    except Exception:
        if destination.is_dir():
            try:
                destination.rmdir()
            except OSError:
                pass
        raise


def unmount_managed(path: str) -> str:
    ensure_live_root()
    item = permitted_path(path, disk_inventory())
    dest = managed_path(item)
    if dest.is_symlink() or not dest.is_dir():
        raise RuntimeError('O volume não está montado pelo Wolf Mount Manager')
    mounted = _run(['findmnt', '-n', '-o', 'SOURCE', '--mountpoint', str(dest)])
    if mounted.returncode:
        raise RuntimeError('Ponto de montagem não está ativo; nenhuma ação realizada')
    source = mounted.stdout.strip().split('[', 1)[0]
    if os.path.realpath(source) != os.path.realpath(path):
        raise RuntimeError('Origem montada não corresponde ao dispositivo selecionado')
    outcome = _run(['umount', '--', str(dest)], 30)
    if outcome.returncode:
        raise RuntimeError(outcome.stderr.strip() or 'Volume ocupado: feche arquivos abertos e tente novamente')
    dest.rmdir()
    return str(dest)


def main() -> int:
    try:
        if len(sys.argv) == 2 and sys.argv[1] == 'list':
            print(json.dumps(disk_inventory(), ensure_ascii=False))
            return 0
        if len(sys.argv) != 3 or sys.argv[1] not in ('mount', 'unmount'):
            print('Uso: wolf-live-mount-backend list | mount DISPOSITIVO | unmount DISPOSITIVO', file=sys.stderr)
            return 2
        target = (mount_readonly if sys.argv[1] == 'mount' else unmount_managed)(sys.argv[2])
        print(target)
        return 0
    except (ValueError, OSError, RuntimeError, PermissionError, subprocess.TimeoutExpired) as exc:
        print(f'[ERRO] {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
