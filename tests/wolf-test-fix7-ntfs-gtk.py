#!/usr/bin/env python3
"""Teste não destrutivo: NTFS e inicialização do tema GTK no LXQt/X11."""
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
import importlib.machinery
import importlib.util
import os
from tempfile import TemporaryDirectory

ROOT=Path(__file__).resolve().parents[1]
def load(filename,name):
    spec=importlib.util.spec_from_loader(name,importlib.machinery.SourceFileLoader(name,str(ROOT/'tools/lxqt'/filename)))
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

fmt=load('wolf-format-removable','wolf7format')
fmt._check_label('WOLF_USB','ntfs')
fmt._check_label('É' * 32,'ntfs')
for bad in ('x'*33, '😀'*17, 'a:b', 'x/y', '', 'USB|TEST'):
    try:fmt._check_label(bad,'ntfs')
    except fmt.UnsafeTarget:pass
    else:raise AssertionError('Rótulo NTFS inseguro aceito: '+bad)

item={'device':'/dev/sdz1','size':'1G','uuid':'AAA','majmin':'8:1','mountpoints':[]}
calls=[]
def fake_run(args,**kw):
    calls.append(args)
    return SimpleNamespace(returncode=0,stdout='',stderr='')
with patch.object(fmt,'_find_candidate',return_value=item),patch.object(fmt.shutil,'which',return_value='/bin/tool') as which:
    assert fmt.format_partition(item,'ntfs','WOLF_USB',run=fake_run)
    assert calls[-1][0:3] == ['busctl','--system','call']
    assert calls[-1][-5:] == ['ntfs','1','label','s','WOLF_USB']
    assert any(call.args[0]=='mkfs.ntfs' for call in which.mock_calls)

appearance=load('wolf-appearance-dark','wolf7appearance')
with patch.dict(os.environ,{'DISPLAY':':0'}):
    with patch.object(appearance,'_owned_xsettings',return_value=[(123,['/usr/bin/xsettingsd','-c','/home/test/.config/xsettingsd/xsettingsd.conf'])]),\
         patch.object(appearance,'_xsettings_snapshot',return_value='Net/ThemeName "Breeze-Dark"\n'),\
         patch.object(appearance.os,'kill') as kill:
        appearance._refresh_xsettings(Path('/home/test/.config/xsettingsd/xsettingsd.conf'))
        kill.assert_called_once()
    with patch.object(appearance,'_owned_xsettings',return_value=[(123,['/usr/bin/xsettingsd','-c','/tmp/lxqt-config-appearance.001'])]),\
         patch.object(appearance.os,'kill') as kill,\
         patch.object(appearance.subprocess,'Popen') as popen:
        appearance._refresh_xsettings(Path('/home/test/.config/xsettingsd/xsettingsd.conf'))
        kill.assert_not_called();popen.assert_not_called()

wrapper=(ROOT/'tools/lxqt/wolf-gtk-xsettings').read_text()
assert 'xsettingsd -c "$config"' in wrapper
configurer=(ROOT/'tools/lxqt/configurar.py').read_text()
installer=(ROOT/'install/wolf-install.sh').read_text()
updater=(ROOT/'atualizar-paineis-pastas-control-center.sh').read_text()
for body in (configurer,updater):
    assert 'Exec=/usr/local/bin/wolf-gtk-xsettings' in body
assert 'install -m 0755 "$source/wolf-gtk-xsettings"' in installer
assert 'wolf-gtk-xsettings' in updater
assert "'ntfs':32" in (ROOT/'tools/lxqt/wolf-format-removable').read_text()
assert 'ntfs-3g' in (ROOT/'package-profiles/packages.conf').read_text()
print('[OK] Fix7: opção NTFS via UDisks2 (simulada), rótulos, XSETTINGS explícito, reload sem interferir em outros')
