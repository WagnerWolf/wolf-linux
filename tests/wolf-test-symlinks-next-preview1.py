#!/usr/bin/env python3
"""Smoke static non-destructive for Wolf libfm-qt 4.2 + helper; no Arch required."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.util
import os
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
installer=(ROOT/'install/wolf-install.sh').read_text()
assert 'stage "69d3-formato-usb-menu-wolf"' in installer
assert 'stage "69d4-links-simbolicos-wolf"' in installer
assert installer.index('stage "69d3-formato-usb-menu-wolf"') < installer.index('stage "69d4-links-simbolicos-wolf"')
assert 'libfm-qt-2.4.0-4.2-x86_64.pkg.tar.zst' in installer
assert installer.index('verificar-abi-lxqt-24.sh') < installer.index('stage "10-preparar-disco"')
assert 'verificar-abi-lxqt-24.sh' in (ROOT/'gerar-iso-2.2.0.sh').read_text()
assert '2.4.0-4)' in (ROOT/'tools/wolf-integration-monitor/verificar-abi-lxqt-24.sh').read_text()
assert 'libfm-qt 2.4.0-4.2' in (ROOT/'tools/package-manager/wolfpkg/upgrade_guard.py').read_text() or "WOLF_VERSION = '2.4.0-4.2'" in (ROOT/'tools/package-manager/wolfpkg/upgrade_guard.py').read_text()
assert 'libfm-qt-2.4.0-4.2-x86_64.pkg.tar.zst' in (ROOT/'gerar-iso-2.2.0.sh').read_text()
assert 'libfm-qt-2.4.0-4.2-x86_64.pkg.tar.zst' in (ROOT/'tests/wolf-customize-iso-profile.sh').read_text()
helper=ROOT/'tools/lxqt/wolf-symlink-actions.py'
text=helper.read_text()
assert "_message('Links simbólicos criados'" not in text
assert "'Falha ao criar alguns links'" in text
assert "'wolf-link-here.desktop'" in (ROOT/'tools/lxqt/instalar-helper.py').read_text()
assert 'libfm-qt 2.4.0-4.2' in (ROOT/'tools/lxqt/instalar-helper.py').read_text()
spec=importlib.util.spec_from_file_location('wolfsymlinks', helper)
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
with TemporaryDirectory() as d:
    root=Path(d); src=root/'arquivo de teste'; src.write_text('wolf')
    dest=root/'destino'; dest.mkdir()
    created,errors=mod.create_links([str(src)],dest)
    assert len(created)==1 and not errors
    assert created[0].is_symlink() and created[0].resolve()==src
    created,errors=mod.create_links([str(src)],dest)
    assert len(created)==1 and created[0].name.endswith(' - link')
    assert created[0].resolve()==src
print('[OK] Wolf links 4.2: empacotamento, instalação, sucesso silencioso, erro e symlink funcional')
