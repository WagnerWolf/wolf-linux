#!/usr/bin/env python3
"""Hook ALPM: registrar atualização, sem executar Pacman, makepkg ou rede."""
from __future__ import annotations
import os
from pathlib import Path
import tempfile
from datetime import datetime, timezone

STATE = Path('/var/lib/wolf-linux/integrations/libfm-qt.changed')


def record(state=STATE):
    state.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    fd, temp = tempfile.mkstemp(prefix='.libfm-qt-', dir=state.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write('Rever integração PCManFM-Qt após transação ALPM em '
                         + datetime.now(timezone.utc).isoformat() + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, 0o644)
        os.replace(temp, state)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


if __name__ == '__main__':
    record()
