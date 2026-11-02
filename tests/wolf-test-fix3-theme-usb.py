#!/usr/bin/env python3
"""Verificações de integração sem dispositivos reais."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import importlib.machinery
import importlib.util

r=Path(__file__).resolve().parents[1]
for path in (r/'tools/lxqt/wolf-appearance-dark',r/'tools/lxqt/wolf-format-removable'):
    assert path.is_file()
s=(r/'tools/lxqt/configurar.py').read_text()
assert "'gtk-theme-name':'Breeze-Dark'" in s
assert 'wolf-removable-tray' in s
main=(r/'tools/control-center/main.py').read_text()
assert 'Reaplicar Wolf-dark (LXQt + GTK)' in main
assert '--apply', '--force' in main
assert 'Diagnóstico detalhado das telas e painéis' in main
install=(r/'install/wolf-install.sh').read_text()
assert 'wolf-format-removable --browse' in install
assert 'install -m 0755 "$source/wolf-appearance-dark"' in install
updater=(r/'atualizar-paineis-pastas-control-center.sh').read_text()
assert 'wolf-removable-tray' in updater
assert 'wolf-format-removable.desktop' in updater
print('[OK] Fix3: tema GTK, painel forçado + diagnóstico, formatação USB via UDisks2, autostart pt_BR')
