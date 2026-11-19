"""Runtime privado por usuário/sessão X11 para o alternador Wolf."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path


def runtime_dir():
    candidate = os.environ.get('XDG_RUNTIME_DIR', '')
    if candidate:
        folder = Path(candidate)
        try:
            stat = folder.stat()
            if folder.is_dir() and stat.st_uid == os.getuid() and not (stat.st_mode & 0o022):
                dest = folder / 'wolf-alt-tab'
                dest.mkdir(mode=0o700, exist_ok=True)
                if dest.stat().st_uid != os.getuid() or (dest.stat().st_mode & 0o077):
                    raise RuntimeError('diretório do socket não é privado')
                return dest
        except (OSError, RuntimeError):
            pass
    dest = Path.home() / '.cache' / 'wolf-alt-tab-runtime'
    dest.mkdir(mode=0o700, parents=True, exist_ok=True)
    if dest.stat().st_uid != os.getuid() or (dest.stat().st_mode & 0o077):
        raise RuntimeError(f'Permissões inseguras: {dest}')
    return dest


def socket_path():
    display = os.environ.get('DISPLAY', ':0')
    session = hashlib.sha256(display.encode()).hexdigest()[:12]
    return runtime_dir() / (session + '.sock')


def lock_path():
    display = os.environ.get('DISPLAY', ':0')
    session = hashlib.sha256(display.encode()).hexdigest()[:12]
    return runtime_dir() / (session + '.lock')
