#!/usr/bin/env python3
"""Entrada oficial para o editor Wolf; resolve instalação global e por usuário."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys


def editor_dir() -> Path | None:
    """Preferir fontes completas da release; aceitar instalação local anterior."""
    candidates = [
        Path(__file__).resolve().parent,
        Path((os.environ.get('XDG_DATA_HOME') or str(Path.home() / '.local/share'))) / 'wolf-linux/control-center',
    ]
    for candidate in candidates:
        if all((candidate / f).is_file() for f in ('monitor_editor.py', 'monitor_layout.py')):
            return candidate
    return None


def main() -> int:
    if os.environ.get('XDG_SESSION_TYPE', '').lower() == 'wayland' or not os.environ.get('DISPLAY'):
        print('[ERRO] Editor Wolf disponível somente numa sessão X11 com DISPLAY.', file=sys.stderr)
        return 2
    if not shutil.which('xrandr'):
        print('[ERRO] xrandr não está instalado (pacote xorg-xrandr).', file=sys.stderr)
        return 2
    try:
        result = subprocess.run(['xrandr', '--query'], capture_output=True, text=True, timeout=8, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f'[ERRO] Falha ao consultar XRandR: {exc}', file=sys.stderr)
        return 2
    if result.returncode != 0:
        print('[ERRO] XRandR indisponível: ' + (result.stderr or result.stdout).strip(), file=sys.stderr)
        return 2
    base = editor_dir()
    if base is None:
        print('[ERRO] Editor de monitores ausente nos diretórios global e local.', file=sys.stderr)
        return 2
    sys.path.insert(0, str(base))
    try:
        from PySide6.QtGui import QIcon
        from PySide6.QtWidgets import QApplication
        from monitor_editor import open_editor
    except ImportError as exc:
        print(f'[ERRO] Dependência do editor ausente: {exc}', file=sys.stderr)
        return 2
    os.environ.setdefault('XDG_SESSION_TYPE', 'x11')
    app = QApplication(['wolf-monitors'])
    app.setApplicationName('Monitores (Wolf Linux)')
    app.setDesktopFileName('wolf-monitors')
    app.setWindowIcon(QIcon.fromTheme('preferences-desktop-display'))
    open_editor()
    return 0


if __name__ == '__main__':
    sys.exit(main())
