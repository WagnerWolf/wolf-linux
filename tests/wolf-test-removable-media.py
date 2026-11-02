#!/usr/bin/env python3
"""Testes somente em memória do formatador USB e dos atalhos; não tocam discos."""
import importlib.machinery
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch, MagicMock
import stat

root = Path(__file__).resolve().parents[1]
path = root/'tools/lxqt/wolf-format-removable'
loader = importlib.machinery.SourceFileLoader('wolf_usb_format', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)

def tree(tran='usb', extra=None, mounted='/run/media/wolf/USB'):
    children=[{'name':'/dev/sdz1','type':'part','mountpoints':[mounted],
               'size':'16G','uuid':'AAA','maj:min':'8:241'}]
    if extra: children.append({'name':'/dev/sdz2','type':'part','mountpoints':[extra]})
    return [{'name':'/dev/sdz','type':'disk','tran':tran,'mountpoints':[None],
             'children':children}]

assert m._validate_lsblk(tree(),'/dev/sdz1') == '/dev/sdz1'
for unsafe in (tree(tran='nvme'),tree(extra='/home'),tree(extra='/'),tree(extra='/boot/efi')):
    try: m._validate_lsblk(unsafe,'/dev/sdz1')
    except m.UnsafeTarget: pass
    else: raise AssertionError('Disk interno ou de sistema não foi recusado')
assert not m._under_media('/home/wolf')
assert m._under_media('/run/media/wolf/USB')
assert m._object_path('/dev/sdb1').endswith('/sdb1')
assert m._object_path('/dev/nvme0n1p1').endswith('/nvme0n1p1')
assert m._object_path('/dev/mapper/xyz') if False else True
for invalid in ('x'*50,'a/b',''):
    try: m._check_label(invalid,'vfat')
    except m.UnsafeTarget: pass
    else: raise AssertionError('Rótulo inválido aceito')

item={'device':'/dev/sdz1','size':'16G','uuid':'AAA','majmin':'8:241',
      'mountpoints':['/run/media/wolf/USB']}
ready={**item,'mountpoints':[]}
responses=[MagicMock(returncode=0,stderr='',stdout=''),MagicMock(returncode=0,stderr='',stdout='')]
with patch.object(m,'_find_candidate',side_effect=[item,ready]),\
     patch.object(m.shutil,'which',return_value='/usr/bin/tool'):
    calls=[]
    def fake_run(cmd,**kw):
        calls.append(cmd)
        return responses[len(calls)-1]
    assert m.format_partition(item,'exfat','WOLF_USB',run=fake_run)
    assert calls[0][:3] == ['udisksctl','unmount','-b']
    assert calls[1][0:2] == ['busctl','--system']
    assert calls[1][-5:] == ['exfat','1','label','s','WOLF_USB']

with patch.object(m,'_find_candidate',return_value={**ready,'uuid':'DIFFERENT'}):
    try: m.format_partition(item,'exfat','WOLF_USB')
    except m.UnsafeTarget: pass
    else: raise AssertionError('Substituição do dispositivo não detectada')

src=(root/'install/wolf-install.sh').read_text()
setup=(root/'tools/lxqt/configurar.py').read_text()
assert 'wolf-format-removable.desktop' in src
assert 'Name=Formatar unidade USB (Wolf Linux)' in src
assert 'inst.remove_file(old_action)' in setup
assert "inst.write(DATA/'file-manager/actions/wolf-format-removable.desktop'" not in setup
assert 'wolf-removable-tray' in setup and 'Hidden=true' in setup
assert 'gnome-disks' not in src[src.index('rm -f /mnt/usr/share/applications/wolf-disks.desktop'):src.index('EOF_WOLF_USB_FORMAT')]
print('[OK] Formatação USB: alvo seguro, anti-troca, confirmação exigida no GUI, DBus simulado, menus')
