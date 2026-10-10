#!/usr/bin/env python3
"""Alpha35 offline RO checks; NO real devices mounted/modified."""
from pathlib import Path
from unittest.mock import patch
import importlib.util
import json
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'live-gui'
spec = importlib.util.spec_from_file_location('wolf_mount_backend', SOURCE / 'mount_backend.py')
backend = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(backend)

raw = json.dumps({'blockdevices': [
    {'name':'sda','path':'/dev/sda','type':'disk','size':32000000000,'children':[
        {'name':'sda1','path':'/dev/sda1','type':'part','fstype':'exfat','size':30000000000,
         'label':'Ventoy','mountpoints':['/run/archiso/bootmnt']}]},
    {'name':'nvme0n1','path':'/dev/nvme0n1','type':'disk','size':1000000000000,'children':[
        {'name':'nvme0n1p1','path':'/dev/nvme0n1p1','type':'part','fstype':'vfat','size':1000000000,'label':'EFI','mountpoints':[]},
        {'name':'nvme0n1p2','path':'/dev/nvme0n1p2','type':'part','fstype':'LVM2_member','size':950000000000,'children':[
            {'name':'vg_monstro-lv_projetos','path':'/dev/mapper/vg_monstro-lv_projetos',
             'type':'lvm','fstype':'ext4','size':1100000000000,'mountpoints':[]}]}]},
    {'name':'nvme1n1','path':'/dev/nvme1n1','type':'disk','size':480000000000,'children':[
        {'name':'nvme1n1p1','path':'/dev/nvme1n1p1','type':'part','fstype':'ext4','size':100000000000,'mountpoints':[]},
        {'name':'nvme1n1p2','path':'/dev/nvme1n1p2','type':'part','fstype':'ntfs','size':138000000000,'mountpoints':[]}]}],
})
items = backend.disk_inventory(raw)
assert len(items) == 9, len(items)
assert backend.permitted_path('/dev/mapper/vg_monstro-lv_projetos', items)['fstype'] == 'ext4'
assert not next(v for v in items if v['path']=='/dev/nvme0n1p2')['supported']
assert next(v for v in items if v['path']=='/dev/sda1')['mountpoints']
for invalid in ('/dev/../etc/passwd','/etc/passwd','/dev/sda;rm -rf /','/dev/nvme0n1p2'):
    try:
        backend.permitted_path(invalid,items)
    except ValueError:
        pass
    else:
        raise AssertionError(f'Unsafe input accepted: {invalid}')
for fs, flags in [('ext4', 'noload'), ('ext3', 'noload'), ('xfs', 'norecovery'),
                  ('ntfs', 'ro'), ('vfat', 'ro'), ('btrfs','ro')]:
    assert flags in backend.SUPPORTED[fs][1]
    assert 'rw' not in backend.SUPPORTED[fs][1].split(',')
    assert 'nosuid' in backend.SUPPORTED[fs][1]

with patch.object(backend, 'ensure_live_root', side_effect=PermissionError('test')):
    try:
        backend.mount_readonly('/dev/nvme1n1p1')
    except PermissionError:
        pass
    else:
        raise AssertionError('Mount operation incorrectly bypassed privilege check')

# Simulate an actual mount/unmount lifecycle WITHOUT invoking mount/umount.
# Verify the command includes ro,noload and kernel confirmation of RO.
with tempfile.TemporaryDirectory() as td:
    dev = '/dev/nvme1n1p1'
    item = next(v for v in items if v['path'] == dev)
    calls = []
    native_exists = Path.exists
    native_is_block = Path.is_block_device
    def fake_exists(p):
        return True if str(p)==dev else native_exists(p)
    def fake_block(p):
        return True if str(p)==dev else native_is_block(p)
    def fake_run(cmd, timeout=20):
        calls.append(cmd)
        if cmd[0] == 'findmnt':
            if '--source' in cmd:
                return subprocess.CompletedProcess(cmd, 1, '', '')
            if '--target' in cmd:
                return subprocess.CompletedProcess(cmd, 0, 'ro,nosuid,nodev,noexec\n', '')
            if '--mountpoint' in cmd:
                return subprocess.CompletedProcess(cmd, 0, dev+'\n', '')
        return subprocess.CompletedProcess(cmd, 0, '', '')
    with patch.object(backend, 'ROOT', Path(td)), \
         patch.object(backend, 'ensure_live_root', return_value=None), \
         patch.object(backend, 'disk_inventory', return_value=items), \
         patch.object(backend, '_run', side_effect=fake_run), \
         patch.object(Path, 'exists', fake_exists), \
         patch.object(Path, 'is_block_device', fake_block):
        target = backend.mount_readonly(dev)
        assert target == td+'/wolf-ro-nvme1n1p1'
        mounted_cmd = next(cmd for cmd in calls if cmd[0] == 'mount')
        assert 'ro,noload,nosuid,nodev,noexec' in mounted_cmd, mounted_cmd
        # Verificar somente as opções reais do mount: caminhos aleatórios de
        # TemporaryDirectory podem conter as letras 'rw' por acaso.
        mount_opts = mounted_cmd[mounted_cmd.index('-o') + 1].split(',')
        assert 'rw' not in mount_opts, mounted_cmd
        assert backend.unmount_managed(dev) == target
        assert any(cmd[0] == 'umount' for cmd in calls)

ET.parse(SOURCE/'home/.config/openbox/menu.xml')
menu=(SOURCE/'home/.config/openbox/menu.xml').read_text()
main=(SOURCE/'main.py').read_text()
staging=(ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
assert 'wolf-live-browser' in menu and 'wolf-live-browser' in main and 'chromium' in staging
# Legado alpha35 permanece testável, mas sua UI foi substituída por GVfs na alpha36.
assert 'wolf-live-mount-manager' not in menu and 'wolf-live-mount-manager' not in main
for pkg in ('chromium','udisks2-lvm2','gvfs','ntfs-3g'):
    assert pkg in staging
assert 'chromium' not in (ROOT/'package-profiles/packages.conf').read_text(), 'Chromium Live added to KDE stacks'
assert 'mount -o rw' not in (SOURCE/'mount_backend.py').read_text()
assert 'readonly_probe pvs --readonly' in (SOURCE/'wolf-live-storage-topology').read_text()
print('[OK] Alpha35: volume inventory (NVMe + Ventoy + LVM), denylist, read-only and staging')
