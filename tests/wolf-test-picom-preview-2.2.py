#!/usr/bin/env python3
"""Teste offline, sem modificar a sessão gráfica ou iniciar Picom."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.machinery
import importlib.util
import subprocess
import sys
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
installer=(ROOT/'tools/lxqt/configurar.py').read_text()
manifest=(ROOT/'package-profiles/packages.conf').read_text()
assert 'LXQtPanel #BackgroundWidget { background: #242a34; }' in installer
assert 'setup_picom_config(inst)' in installer
assert 'openbox obconf-qt picom' in manifest
assert 'picom' not in (ROOT/'tools/lxqt/wolf_lxqt_monitors.py').read_text()
script=ROOT/'experimental/picom/wolf-picom-lxqt.py'
assert script.is_file()
subprocess.run([sys.executable,'-m','py_compile',str(script)],check=True)
loader=importlib.machinery.SourceFileLoader('wolf_picom_experimental',str(script))
spec=importlib.util.spec_from_loader('wolf_picom_experimental',loader)
mod=importlib.util.module_from_spec(spec)
loader.exec_module(mod)
with TemporaryDirectory() as temp:
    home=Path(temp)
    panel=home/'.local/share/lxqt/themes/wolf-dark/lxqt-panel.qss'
    panel.parent.mkdir(parents=True)
    panel.write_text('QMenu { color: #fff; }\n')
    with patch.object(mod,'HOME',home), patch.object(mod,'THEME',panel), \
         patch.object(mod,'CONFIG',home/'.config/picom/picom.conf'), \
         patch.object(mod,'AUTO',home/'.config/autostart/wolf-picom.desktop'), \
         patch.object(mod,'BACKUPS',home/'backups'):
        mod.apply()
        assert mod.MARKER in panel.read_text()
        assert mod.CONFIG.is_file()
        assert not mod.AUTO.exists(), 'Prévia não pode ativar compositor sem validação gráfica'
        mod.apply()
        assert panel.read_text().count(mod.MARKER)==1
        mod.undo();mod.undo()
        assert panel.read_text()=='QMenu { color: #fff; }\n'
        assert not mod.CONFIG.exists()
print('[OK] Picom preview: fundo opaco, perfil GLX, backup, restauração e sem autostart obrigatório')
