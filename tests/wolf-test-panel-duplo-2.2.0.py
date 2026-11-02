#!/usr/bin/env python3
"""Regressão: QSettings perde painel secundário se `panels` estiver duplicado."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.util
import sys

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('wolf_monitors_fix4',ROOT/'tools/lxqt/wolf_lxqt_monitors.py')
mod=importlib.util.module_from_spec(spec); sys.modules[spec.name]=mod; spec.loader.exec_module(mod)
qt_state={'names':['panel1']}
mod._qt_panels=lambda panel: (qt_state['names'], 'list')
def fake_write(panel, ids): qt_state['names']=[f'panel{i}' for i in range(1,len(ids)+1)]
mod._qt_write_panels=fake_write

with TemporaryDirectory() as tmp:
    home=Path(tmp)/'wolf'
    panel=home/'.config/lxqt/panel.conf';panel.parent.mkdir(parents=True)
    original=('panels=panel1,panel2\npanels=panel1\n[panel1]\ndesktop=0\n'
              'plugins=menu1,quick1,tasks1,status1,tray1,volume1,clock1,showdesktop1\n'
              '[panel2]\ndesktop=1\nplugins=menu2,quick2,tasks2,clock2,showdesktop2\n')
    panel.write_text(original)
    assert mod.root_panels_entries(original)==['panel1,panel2','panel1']
    assert not mod._matches(original,(0,1)), 'Não pode considerar duas chaves sincronizadas'
    assert 'necessário aplicar' in mod.status(panel,counts=(0,1))
    assert mod.apply(panel,counts=(0,1),refresh=False)
    clean=panel.read_text()
    assert mod.root_panels_entries(clean)==['panel1,panel2']
    assert mod._matches(clean,(0,1))
    assert 'desktop=1' in clean and '[panel2]' in clean
    assert not mod.apply(panel,counts=(0,1),refresh=False), 'idempotência'
    assert any((home/'wolf-backups/lxqt-panels').glob('*/panel.conf'))
    assert mod.apply(panel,counts=(0,None),refresh=False)
    assert mod.root_panels_entries(panel.read_text())==['panel1']

# Verificar que o script portátil está incluso e o controle da sessão é estático.
assert (ROOT/'wolf-corrigir-painel-duplo.py').is_file()
assert 'wolf-test-panel-duplo-2.2.0.py' in (ROOT/'tests/wolf-smoke-test.sh').read_text()
print('[OK] Duplicidade de panels detectada e corrigida, com backup e idempotência')
