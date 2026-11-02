#!/usr/bin/env python3
"""Fix6: simulações sem devices reais, sem servidor X11 e sem formatar mídias."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch, MagicMock
from types import ModuleType, SimpleNamespace
import importlib.machinery
import importlib.util
import importlib
import sys

ROOT=Path(__file__).resolve().parents[1]

def loader(filename, name):
    f=ROOT/'tools/lxqt'/filename
    spec=importlib.util.spec_from_loader(name,importlib.machinery.SourceFileLoader(name,str(f)))
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
    return mod

panel=loader('wolf_lxqt_monitors.py','wolf_fix6_panel')
state={}
class FakeQSettings:
    IniFormat=1
    NoError='Status.NoError'
    def __init__(self, name, fmt): self.key=str(name)
    def sync(self): pass
    def status(self): return self.NoError
    def value(self, name): return state.get(self.key,['panel1'])
    def setValue(self, name, val): state[self.key]=list(val)
qt=ModuleType('PySide6.QtCore');qt.QSettings=FakeQSettings
pkg=ModuleType('PySide6');pkg.QtCore=qt
with TemporaryDirectory() as tmp, patch.dict(sys.modules,{'PySide6':pkg,'PySide6.QtCore':qt}):
    f=Path(tmp)/'panel.conf';f.write_text('panels=panel1\n[panel1]\nplugins=menu1\n')
    got, kind = panel._qt_panels(f)
    assert got == ['panel1']
    def child(cmd,**kw):
        assert cmd[:2]==[sys.executable,'-c'] and cmd[-1]==str(f)
        return SimpleNamespace(returncode=0,stdout='panel1|panel2\nlist\nStatus.NoError\n',stderr='')
    with patch.object(panel.subprocess,'run',side_effect=child):
        panel._qt_write_panels(f,(0,1))
    assert state[str(f)]==['panel1','panel2']

tray=loader('wolf-removable-tray','wolf_fix6_tray')
raw={'blockdevices':[
  {'type':'disk','tran':'usb','path':'/dev/sdz','size':'8G','model':'Teste USB',
   'children':[{'type':'part','path':'/dev/sdz1','size':'8G','label':'USB','mountpoints':['/run/media/wolf/USB']}]},
  {'type':'disk','tran':'nvme','path':'/dev/nvme0n1','children':[{'type':'part','path':'/dev/nvme0n1p1'}]},
  {'type':'disk','tran':'usb','path':'/dev/sdy','children':[{'type':'part','path':'/dev/sdy1','mountpoints':['/home']}]},
]}
import json
with patch.object(tray.subprocess,'run',return_value=SimpleNamespace(stdout=json.dumps(raw))):
    disks=tray.scan_disks()
assert len(disks)==2 and disks[0]['parts'][0]['device']=='/dev/sdz1'
assert tray.removable(disks[0]) and not tray.removable(disks[1])
for forbidden in ('Dolphin','udiskie --smart-tray'):
    assert forbidden not in (ROOT/'tools/lxqt/wolf-removable-tray').read_text()

setup=loader('configurar.py','wolf_fix6_setup')
with TemporaryDirectory() as tmp:
    home=Path(tmp)/'wolf';home.mkdir()
    with patch.object(setup,'HOME',home),patch.object(setup,'CONFIG',home/'.config'),\
         patch.object(setup,'DATA',home/'.local/share'),patch.object(setup,'BASE',home/'backups'):
        inst=setup.Installer();setup.setup_removable_media(inst)
        cfg=(home/'.config/autostart')
        assert 'Hidden=true' in (cfg/'wolf-udiskie.desktop').read_text()
        assert 'wolf-removable-tray' in (cfg/'wolf-removable-tray.desktop').read_text()
        legacy=home/'.local/share/file-manager/actions/wolf-format-removable.desktop'
        assert not legacy.exists(), 'Ação antiga de pastas não deve ser recriada'
        legacy.parent.mkdir(parents=True, exist_ok=True)
        legacy.write_text('[Desktop Entry]\nType=Action\nFolders=/run/media/*;/media/*;\nExec=/usr/local/bin/wolf-format-removable --format %f\n')
        setup.setup_removable_media(inst)
        assert not legacy.exists(), 'Migrador deve retirar o menu antigo com backup'
        inst.complete()

manifest=(ROOT/'package-profiles/packages.conf').read_text()
assert 'xsettingsd' in manifest and 'breeze-gtk' in manifest
installer=(ROOT/'install/wolf-install.sh').read_text()
assert 'install -m 0755 "$source/wolf-removable-tray"' in installer
assert 'xsettingsd gnome-disk-utility' in installer
assert 'wolf-removable-tray' in (ROOT/'atualizar-paineis-pastas-control-center.sh').read_text()
assert 'runpy.run_path' in (ROOT/'tools/lxqt/wolf-appearance-dark').read_text()
print('[OK] Fix6: QSettings QStringList, USB seguro/português, ação PCManFM-Qt, GTK XSETTINGS')
