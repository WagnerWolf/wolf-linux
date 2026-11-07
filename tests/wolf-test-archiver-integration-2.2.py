#!/usr/bin/env python3
"""Smoke determinístico, isolado, não destrutivo para integração LXQt Archiver."""
from pathlib import Path
import importlib.util
import os
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
script = ROOT / 'wolf-corrigir-archiver-2.2.0.py'
assert script.is_file(), (
    'Reparador do Archiver não foi copiado para a raiz do projeto preparado: ' + str(script)
)
# Testar também o contrato do preparador para prevenir reincidência na próxima ISO.
prepare = (ROOT / 'preparar_ambiente_wolf_linux.sh').read_text(encoding='utf-8')
assert 'install -m 0755 "$SELF_DIR/wolf-corrigir-archiver-2.2.0.py"' in prepare, (
    'O preparador não copia o reparador do Archiver para a árvore final.'
)
spec = importlib.util.spec_from_file_location('wolf_archiver_fix', script)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.repair('[System]\nArchiver=xarchiver\nTerminal=konsole\n').count('Archiver=lxqt-archiver') == 1
assert 'Terminal=konsole' in mod.repair('[System]\nArchiver=xarchiver\nTerminal=konsole\n')
assert mod.keys(mod.repair('[System]\nArchiver=xarchiver\nArchiver=ark\n')) == ['lxqt-archiver']
assert mod.keys(mod.repair('[Desktop]\nWallpaper=wolf.png\n')) == ['lxqt-archiver']
assert mod.keys(mod.repair('')) == ['lxqt-archiver']
assert mod.repair(mod.repair('[System]\nArchiver=xarchiver\n')) == mod.repair('[System]\nArchiver=xarchiver\n')
config = (ROOT/'tools/lxqt/configurar.py').read_text()
assert "'Archiver':'lxqt-archiver'" in config
installer = (ROOT/'install/wolf-install.sh').read_text()
assert 'install_wolf_lxqt_profile()' in installer and 'configurar.py' in installer
from unittest.mock import patch
with tempfile.TemporaryDirectory() as t:
    home=Path(t)/'home'
    home.mkdir()
    fakebin=Path(t)/'bin'
    fakebin.mkdir()
    tool=fakebin/'lxqt-archiver'
    tool.write_text('#!/bin/sh\nexit 0\n')
    tool.chmod(0o755)
    conf=home/'.config/pcmanfm-qt/lxqt/settings.conf'
    conf.parent.mkdir(parents=True)
    conf.write_text('[System]\nArchiver=xarchiver\nIconThemeName=Papirus-Dark\n[Desktop]\nWallpaper=wolf.png\n')
    with patch.object(mod, 'HOME', home), \
         patch.object(mod, 'SETTINGS', conf), \
         patch.object(mod, 'BACKUPS', home/'wolf-backups/pcmanfm-qt-archiver'), \
         patch.object(mod.os, 'geteuid', return_value=1000), \
         patch.object(mod.shutil, 'which', return_value=str(tool)):
        with patch.object(sys, 'argv', [str(script), '--apply']):
            assert mod.main()==0
        assert 'Archiver=lxqt-archiver' in conf.read_text()
        assert 'Wallpaper=wolf.png' in conf.read_text()
        backups=list((home/'wolf-backups/pcmanfm-qt-archiver').glob('*/settings.conf'))
        assert len(backups)==1 and 'Archiver=xarchiver' in backups[0].read_text()
        with patch.object(sys, 'argv', [str(script), '--check']):
            assert mod.main()==0
        with patch.object(sys, 'argv', [str(script), '--apply']):
            assert mod.main()==0
        assert len(list((home/'wolf-backups/pcmanfm-qt-archiver').glob('*/settings.conf')))==1
print('[OK] Archiver: configurações, backup, execução e idempotência preservados')
