#!/usr/bin/env python3
"""Limpeza simples de dotfiles na raiz do usuário (alpha50).

scan/check: montagem ext4 ro,noload. apply: SOMENTE após autorização do
executor Bash físico, com dispositivo montado/verificado em /mnt/home.
Nunca segue links simbólicos; nunca formata filesystem ou toca nos PVs.
"""
from __future__ import annotations

import json
import stat
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

MAX_ITEMS = 600
MAX_SELECTION = 150
SAFE_ITEM = re.compile(r'^\.[A-Za-z0-9_.-]+$|^\.local/(?:bin|state|share/[^/]+)$')
RESERVED = {'.', '..', '.wolf-linux-backups', '.local', '.local/share', '.local/state'}
PRESERVE_DEFAULT = {'.ssh', '.gnupg', '.steam', '.mozilla', '.local/bin'}


class CleanupDenied(ValueError):
    pass


def valid_item(name: str) -> bool:
    return (isinstance(name, str) and len(name) <= 220 and bool(SAFE_ITEM.fullmatch(name))
            and name not in RESERVED and not any(x in ('.', '..') for x in name.split('/')))


def validate_spec(raw: object) -> dict:
    if raw is None:
        return {'items': [], 'backup': False}
    if isinstance(raw, dict) and set(raw) == {'enabled', 'backup'}:
        if type(raw['enabled']) is not bool or type(raw['backup']) is not bool:
            raise CleanupDenied('Limpeza de /home e backup precisam ser opções booleanas.')
        if raw['backup'] and not raw['enabled']:
            raise CleanupDenied('Backup exige que a limpeza esteja ativada.')
        return {'enabled': raw['enabled'], 'backup': raw['backup']}
    # Compatibilidade estrita com planos alpha49 já emitidos (não utilizados pela nova GUI).
    if not isinstance(raw, dict) or set(raw) != {'items', 'backup'}:
        raise CleanupDenied('Contrato de seleção de /home inválido.')
    items, backup = raw['items'], raw['backup']
    if type(backup) is not bool or not isinstance(items, list) or len(items) > MAX_SELECTION:
        raise CleanupDenied('Seleção/backup inválidos.')
    if any(not valid_item(item) for item in items) or len(items) != len(set(items)):
        raise CleanupDenied('Caminho de limpeza não permitido ou repetido.')
    if any(a != b and b.startswith(a + '/') for a in items for b in items):
        raise CleanupDenied('Seleção contém caminhos pai/filho sobrepostos.')
    if backup and not items:
        raise CleanupDenied('Backup sem nenhum item selecionado.')
    return {'items': sorted(items), 'backup': backup}


def _list_candidates(userdir: Path) -> list[str]:
    if userdir.is_symlink() or not userdir.is_dir():
        raise CleanupDenied('Diretório pessoal ausente ou simbólico.')
    candidates = []
    for item in userdir.iterdir():
        if item.name.startswith('.') and valid_item(item.name) and item.name != '.local' and not item.is_symlink():
            candidates.append(item.name)
    local = userdir / '.local'
    if local.is_dir() and not local.is_symlink():
        for kind in ('bin', 'state'):
            item = local / kind
            if item.exists() and not item.is_symlink():
                candidates.append(f'.local/{kind}')
        share = local / 'share'
        if share.is_dir() and not share.is_symlink():
            for item in share.iterdir():
                rel = '.local/share/' + item.name
                if valid_item(rel) and not item.is_symlink():
                    candidates.append(rel)
    if len(candidates) > MAX_ITEMS:
        raise CleanupDenied(f'Muitos diretórios ocultos ({len(candidates)}); reduza manualmente antes de continuar.')
    return sorted(set(candidates))


def root_dotfiles(base: Path, username: str) -> list[str]:
    """Somente entradas imediatas: inclusive .local, .steam e links simbólicos.

    NÃO descemos recursivamente na coleta de nomes; isso impede as
    seleções duplicadas ou sobrepostas da interface alpha49.
    """
    home = _userdir(base, username)
    if home.is_symlink() or not home.is_dir():
        raise CleanupDenied('Pasta pessoal ausente ou simbólica.')
    names = [p.name for p in home.iterdir() if p.name.startswith('.') and p.name not in ('.', '..')]
    return sorted(names)


def root_dotfile_info(base: Path, username: str) -> list[dict]:
    home = _userdir(base, username)
    return [{'path': name, 'bytes': _size(home / name),
             'sensitive': name in {'.steam', '.local', '.ssh', '.gnupg', '.mozilla'}}
            for name in root_dotfiles(base, username)]


def _write_manifest(path: Path, names: list[str]) -> None:
    if path.is_symlink():
        raise CleanupDenied('Manifesto não pode ser link simbólico.')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(names, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        raise


def _read_manifest(path: Path) -> list[str]:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_uid != 0 or st.st_mode & 0o077:
        raise CleanupDenied('Manifesto de confirmação inválido ou não protegido.')
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, list) or any(not isinstance(v, str) for v in value) or value != sorted(set(value)):
        raise CleanupDenied('Manifesto de limpeza malformado.')
    return value


def _userdir(base: Path, username: str) -> Path:
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', username):
        raise CleanupDenied('Nome de usuário inválido.')
    return base / username


def _size(path: Path) -> int:
    # du -x não segue symlinks e não cruza dispositivos montados.
    cp = subprocess.run(['du', '-skx', '--', str(path)], capture_output=True,
                        text=True, timeout=180, check=False)
    if cp.returncode:
        raise CleanupDenied(f'Falha ao medir tamanho de {path.name}: {cp.stderr[:150]}')
    return int(cp.stdout.split()[0]) * 1024


def candidate_info(base: Path, username: str) -> list[dict]:
    userdir = _userdir(base, username)
    result = []
    for rel in _list_candidates(userdir):
        path = userdir / rel
        result.append({'path': rel, 'bytes': _size(path),
                       'recommended': rel in ('.config', '.cache'),
                       'sensitive': rel in PRESERVE_DEFAULT or 'Steam' in rel or rel.startswith('.local/share/')})
    return result


def selected_info(base: Path, username: str, spec: dict) -> list[dict]:
    spec = validate_spec(spec)
    candidates = set(_list_candidates(_userdir(base, username)))
    if not set(spec['items']).issubset(candidates):
        raise CleanupDenied('Itens selecionados mudaram/desapareceram; gere uma nova prévia.')
    return [{'path': rel, 'bytes': _size(_userdir(base, username) / rel)} for rel in spec['items']]


def _mount_ro(device: str) -> Path:
    if not device.startswith('/dev/') or not Path(device).exists():
        raise CleanupDenied('Dispositivo /home inválido.')
    probe = Path(tempfile.mkdtemp(prefix='wolf49-home-ro-'))
    cp = subprocess.run(['mount', '-t', 'ext4', '-o', 'ro,noload', '--', device, str(probe)],
                        capture_output=True, text=True, check=False, timeout=25)
    if cp.returncode:
        probe.rmdir()
        raise CleanupDenied('Não foi possível montar /home em leitura: ' + cp.stderr[:150])
    return probe


def _unmount(probe: Path) -> None:
    cp = subprocess.run(['umount', '--', str(probe)], capture_output=True, check=False, timeout=25)
    if cp.returncode:
        raise CleanupDenied('Não foi possível desmontar a prévia: operação abortada.')
    probe.rmdir()


def _mount_guard(base: Path, device: str) -> None:
    cp = subprocess.run(['findmnt', '-rn', '-o', 'SOURCE', '--mountpoint', str(base)],
                        capture_output=True, text=True, check=False)
    if cp.returncode or os.path.realpath(cp.stdout.strip()) != os.path.realpath(device):
        raise CleanupDenied('/home não está montada a partir do dispositivo validado.')


def _no_nested_mounts(targets: list[Path]) -> None:
    cp = subprocess.run(['findmnt', '-rn', '-o', 'TARGET'], capture_output=True, text=True, check=False)
    if cp.returncode:
        raise CleanupDenied('Não foi possível conferir submontagens.')
    mountpoints = cp.stdout.splitlines()
    for target in targets:
        for mp in mountpoints:
            if mp == str(target) or mp.startswith(str(target) + '/'):
                raise CleanupDenied('Montagem detectada dentro de uma pasta selecionada: ' + str(target))


def perform_root(base: Path, device: str, username: str, spec: dict, manifest: Path) -> tuple[int, str]:
    """Apaga somente dotfiles IMEDIATOS após comparar com a prévia autorizada."""
    spec = validate_spec(spec)
    if not spec['enabled']:
        return 0, ''
    _mount_guard(base, device)
    userdir = _userdir(base, username)
    if userdir.is_symlink() or not userdir.is_dir():
        raise CleanupDenied('Pasta pessoal inválida ou simbólica.')
    names = root_dotfiles(base, username)
    if names != _read_manifest(manifest):
        raise CleanupDenied('Entradas ocultas mudaram após a confirmação: nada apagado.')
    paths = [userdir / name for name in names]
    _no_nested_mounts(paths)
    # Proteção contra mudanças entre prévia e execução: recusa caminhos que
    # desapareceram. Para symlinks no topo, apaga só o link, não seu destino.
    for path in paths:
        if not (path.exists() or path.is_symlink()):
            raise CleanupDenied('Entrada oculta desapareceu após a prévia.')
    backup_dir = None
    if spec['backup'] and paths:
        sizes = [_size(path) for path in paths]
        if shutil.disk_usage(base).free < sum(sizes) + 1024**3:
            raise CleanupDenied('Espaço insuficiente para cópia e margem de 1 GiB.')
        backup_base = base / '.wolf-linux-backups'
        if backup_base.is_symlink():
            raise CleanupDenied('Diretório de backups simbólico não permitido.')
        backup_base.mkdir(mode=0o700, exist_ok=True)
        os.chmod(backup_base, 0o700)
        backup_dir = backup_base / ('alpha50-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + str(os.getpid()))
        backup_dir.mkdir(mode=0o700)
        target = backup_dir / username
        target.mkdir(mode=0o700)
        for source in paths:
            cp = subprocess.run(['cp', '-a', '--', str(source), str(target / source.name)],
                                capture_output=True, text=True, timeout=3600, check=False)
            if cp.returncode:
                raise CleanupDenied('Backup incompleto; NADA apagado: ' + cp.stderr[:200])
    for path in paths:
        if path.is_symlink() or not path.is_dir():
            path.unlink()
        else:
            shutil.rmtree(path)
    return len(paths), str(backup_dir) if backup_dir else ''


def perform(base: Path, device: str, username: str, spec: dict) -> tuple[int, str]:
    """Chamado somente na etapa 22, após confirmação física pré-mkfs."""
    spec = validate_spec(spec)
    if not spec['items']:
        return 0, ''
    _mount_guard(base, device)
    items = selected_info(base, username, spec)
    userdir = _userdir(base, username)
    paths = [userdir / item['path'] for item in items]
    _no_nested_mounts(paths)
    # Confere componentes ancestrais sem links, inclusive .local e share.
    for path in paths:
        current = userdir
        for comp in path.relative_to(userdir).parts:
            current = current / comp
            if current.is_symlink():
                raise CleanupDenied('Link simbólico no caminho selecionado: ' + str(current))
    backup_dir = None
    if spec['backup']:
        estimated = sum(item['bytes'] for item in items)
        free = shutil.disk_usage(base).free
        if free < estimated + 1024 ** 3:
            raise CleanupDenied('Espaço insuficiente para backup (requer cópia + margem de 1 GiB).')
        backup_base = base / '.wolf-linux-backups'
        if backup_base.is_symlink():
            raise CleanupDenied('Diretório de backups não pode ser link simbólico.')
        backup_base.mkdir(mode=0o700, exist_ok=True)
        os.chmod(backup_base, 0o700)
        backup_dir = backup_base / ('alpha49-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + str(os.getpid()))
        backup_dir.mkdir(mode=0o700)
        for rel, path in zip(spec['items'], paths):
            target = backup_dir / username / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            cp = subprocess.run(['cp', '-a', '--', str(path), str(target)],
                                capture_output=True, text=True, timeout=3600, check=False)
            if cp.returncode:
                raise CleanupDenied('Backup incompleto; NADA foi apagado: ' + cp.stderr[:200])
        # cp -a preserva dono, links, permissões, timestamps e atributos; só
        # depois da cópia integral começamos a remover qualquer item.
    for path in paths:
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    return len(paths), str(backup_dir) if backup_dir else ''


def main(argv: list[str]) -> int:
    if os.geteuid() != 0:
        print('[BLOQUEADO] Operação exige root na Live.', file=sys.stderr)
        return 2
    if not argv or argv[0] not in ('scan', 'scan-root', 'check', 'apply'):
        print('Uso: wolf_home_cleanup.py scan-root DEVICE USER | check PLAN DEVICE [MANIFESTO] | apply PLAN MOUNT DEVICE [MANIFESTO]', file=sys.stderr)
        return 2
    try:
        if argv[0] == 'scan' and len(argv) == 3:
            probe = _mount_ro(argv[1])
            try:
                print(json.dumps(candidate_info(probe, argv[2]), ensure_ascii=False))
            finally:
                _unmount(probe)
        elif argv[0] == 'scan-root' and len(argv) == 3:
            probe = _mount_ro(argv[1])
            try:
                print(json.dumps(root_dotfile_info(probe, argv[2]), ensure_ascii=False))
            finally:
                _unmount(probe)
        elif argv[0] == 'check' and len(argv) in (3, 4):
            from wolf_discovery import _load_plan
            doc = _load_plan(argv[1]); spec = validate_spec(doc.get('home_cleanup'))
            if doc['roles']['home']['path'] != argv[2]:
                raise CleanupDenied('Dispositivo no contrato não corresponde a /home.')
            probe = _mount_ro(argv[2])
            try:
                info = (root_dotfile_info(probe, doc['identity']['username']) if spec.get('enabled') else
                        selected_info(probe, doc['identity']['username'], spec))
                if 'enabled' in spec:
                    if len(argv) != 4:
                        raise CleanupDenied('Manifesto físico da lista completa é obrigatório.')
                    _write_manifest(Path(argv[3]), [item['path'] for item in info] if spec['enabled'] else [])
                total = sum(i['bytes'] for i in info)
                if spec['backup'] and shutil.disk_usage(probe).free < total + 1024**3:
                    raise CleanupDenied('Espaço insuficiente para backup no volume /home.')
                print('PRÉVIA DE LIMPEZA DA RAIZ DO USUÁRIO — CONFIRMADA' if 'enabled' in spec else 'LIMPEZA SELETIVA DE /home — LISTA CONFIRMADA')
                for item in info:
                    print(f'  /home/{doc["identity"]["username"]}/{item["path"]} — {item["bytes"] / 1024**3:.2f} GiB')
                print(f'TOTAL ESTIMADO: {total / 1024**3:.2f} GiB; backup: {"SIM" if spec["backup"] else "NÃO"}')
                print('A limpeza NÃO formata o LVM, não altera a EFI nem apaga arquivos visíveis da pasta pessoal.')
            finally:
                _unmount(probe)
        elif argv[0] == 'apply' and len(argv) in (4, 5):
            from wolf_discovery import _load_plan
            doc = _load_plan(argv[1]); spec = validate_spec(doc.get('home_cleanup'))
            if doc['roles']['home']['path'] != argv[3]:
                raise CleanupDenied('Dispositivo alterado.')
            if 'enabled' in spec:
                if len(argv) != 5:
                    raise CleanupDenied('Manifesto da prévia ausente: limpeza recusada.')
                total, backup = perform_root(Path(argv[2]), argv[3], doc['identity']['username'], spec, Path(argv[4]))
            else:
                total, backup = perform(Path(argv[2]), argv[3], doc['identity']['username'], spec)
            print(f'[OK] Limpeza seletiva: {total} itens. ' + (f'Backup: {backup}' if backup else 'Sem backup.'))
        else:
            raise CleanupDenied('Argumentos inválidos.')
        return 0
    except (CleanupDenied, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as exc:
        print('[BLOQUEADO] ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
