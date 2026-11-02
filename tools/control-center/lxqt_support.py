#!/usr/bin/env python3
"""Integração LXQt somente sob demanda; NÃO altera painéis ao consultar."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
from datetime import datetime, timezone

# Apenas arquivos de configuração do usuário, relativos a ~/.config.
FILES = (
    "lxqt/panel.conf",
    "lxqt/lxqt.conf",
    "lxqt/session.conf",
    "lxqt/globalkeyshortcuts.conf",
    "lxqt/lxqt-config-appearance.conf",
    "pcmanfm-qt/lxqt/settings.conf",
    "openbox/lxqt-rc.xml",
    "openbox/rc.xml",
    "mimeapps.list",
    "lxqt-mimeapps.list",
    "kdeglobals",
    "gtk-3.0/settings.ini",
)
STATE = Path(".local/state/wolf-linux/control-center/lxqt-backups")


def _home(home: Path | None = None) -> Path:
    return home if home is not None else Path.home()


def _config_base(home: Path | None = None) -> Path:
    h = _home(home)
    return h / ".config"  # intentionally isolated from XDG_CONFIG_HOME for predictable rollback


def backup_root(home: Path | None = None) -> Path:
    return _home(home) / STATE


def diagnostic_text(home: Path | None = None) -> str:
    base = _config_base(home)
    present = [x for x in FILES if (base / x).is_file()]
    return (f"Configurações LXQt/Openbox: {len(present)}/{len(FILES)} arquivos encontrados; "
            f"panel.conf: {'presente' if 'lxqt/panel.conf' in present else 'ausente'}; "
            f"snapshots: {len(list_backups(home))}")


def list_backups(home: Path | None = None) -> list[Path]:
    root = backup_root(home)
    if not root.is_dir():
        return []
    return sorted((p for p in root.iterdir() if p.is_dir() and not p.is_symlink()
                   and (p / 'manifest.json').is_file()), reverse=True)


def _digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as fp:
        for data in iter(lambda: fp.read(65536), b''):
            h.update(data)
    return h.hexdigest()


def create_snapshot(home: Path | None = None) -> Path:
    """Backups explícitos; nenhum reinício de painel, Chrome ou sessão."""
    source = _config_base(home)
    root = backup_root(home)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder = root / stamp
    folder.mkdir(mode=0o700)
    found: dict[str, str] = {}
    try:
        for rel in FILES:
            file = source / rel
            if file.is_symlink() or not file.is_file():
                continue
            dest = folder / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, dest, follow_symlinks=False)
            dest.chmod(0o600)
            found[rel] = _digest(dest)
        if not found:
            raise RuntimeError('Nenhum arquivo de configuração LXQt/Openbox encontrado')
        manifest = {'format': 1, 'files': found, 'created_utc': stamp}
        target = folder / 'manifest.json'
        target.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        target.chmod(0o600)
        return folder
    except Exception:
        shutil.rmtree(folder)
        raise


def restore_snapshot(folder: Path, home: Path | None = None, *, running_desktop: str = '') -> list[str]:
    """Restaurar offline; validar hashes e conteúdo antes de sobrescrever.

    A UI da sessão LXQt não disponibiliza restauração; use do Plasma/X11 ou TTY.
    """
    if 'LXQT' in running_desktop.upper().split(':'):
        raise RuntimeError('Saia da sessão LXQt para restaurar: o painel pode sobrescrever arquivos em execução')
    root = backup_root(home).resolve()
    folder = folder.resolve()
    if folder.parent != root or not (folder / 'manifest.json').is_file():
        raise ValueError('Snapshot fora do diretório autorizado')
    manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
    if manifest.get('format') != 1:
        raise ValueError('Formato de snapshot não reconhecido')
    files: dict[str, str] = manifest.get('files', {})
    if not isinstance(files, dict) or not files:
        raise ValueError('Manifesto sem arquivos')
    # Validar TODOS os arquivos antes de iniciar a restauração.
    for rel, digest in files.items():
        if rel not in FILES:
            raise ValueError('Arquivo fora da lista de permissões')
        src = folder / rel
        if src.is_symlink() or not src.is_file() or _digest(src) != digest:
            raise ValueError('Arquivo de snapshot ausente, alterado ou inválido: ' + rel)
    dest_base = _config_base(home)
    # Impede restauração parcial se algum destino for um link simbólico.
    for rel in files:
        target = dest_base / rel
        if target.is_symlink():
            raise ValueError('Destino é link simbólico: ' + str(target))
    restored = []
    for rel in files:
        target = dest_base / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        # Preserva uma cópia imediata da configuração anterior à restauração.
        if target.is_file():
            shutil.copy2(target, target.with_name(target.name + '.wolf-before-restore'))
        shutil.copy2(folder / rel, target)
        restored.append(rel)
    return restored


def cli() -> None:
    import argparse
    p = argparse.ArgumentParser(description='Snapshot seguro das configurações LXQt/Openbox')
    p.add_argument('action', choices=['status','snapshot','list','restore'])
    p.add_argument('--snapshot', dest='snapshot_path', help='Caminho absoluto de snapshot para restore')
    args = p.parse_args()
    if args.action == 'status':
        print(diagnostic_text())
    elif args.action == 'snapshot':
        print(create_snapshot())
    elif args.action == 'list':
        print('\n'.join(map(str, list_backups())) or 'Nenhum snapshot')
    else:
        if not args.snapshot_path:
            p.error('restore exige --snapshot PATH')
        import sys
        print('Restaurando arquivos (somente fora do LXQt):', file=sys.stderr)
        print('\n'.join(restore_snapshot(Path(args.snapshot_path), running_desktop=os.environ.get('XDG_CURRENT_DESKTOP',''))))

if __name__ == '__main__':
    cli()
