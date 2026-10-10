#!/usr/bin/env python3
"""Alpha47: contrato exportador e bloqueios sem tocar em discos reais."""
import copy
import json
from pathlib import Path
from unittest.mock import patch
import runpy
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'live-gui'))
import wolf_discovery as wd
import wolf_physical_executor as x
fixture=runpy.run_path(str(ROOT/'tests/wolf-test-alpha39.py'))
raw=json.loads(fixture['lsblk'])
for disk in raw['blockdevices']:
    for part in disk.get('children',[]):
        if part.get('path') == '/dev/nvme1n1p1':
            part['parttype']='0fc63daf-8483-4772-8e79-3d69d8477de4'
snap=wd.discover(raw=json.dumps(raw),fstab_by_root={'/dev/nvme1n1p1':fixture['FSTAB']},boot_mode='UEFI')
plan=fixture['make'](snap)
assert wd.validate_plan(plan,snap)==plan
with patch.object(x.Path,'is_dir',return_value=True):
    topology=x.validated(plan,snap)
    assert topology['root']=='/dev/nvme1n1p1'
    assert len(topology['pvs'])==2
    assert len(x.export_fields(plan,snap))==12

def denies(mod,reason):
    try:
        with patch.object(x.Path,'is_dir',return_value=True):
            x.validated(mod,snap)
    except (ValueError,wd.DiscoveryError):
        return
    raise AssertionError('Não bloqueou '+reason)
for bad,why in [({'acknowledge_override':True},'override'),({'execution':'enabled'},'execucao'),({'boot_mode':'BIOS'},'bios')]:
    p=copy.deepcopy(plan); p.update(bad); denies(p,why)
p=copy.deepcopy(plan);p['roles']['home']['lvm_pvs']=p['roles']['home']['lvm_pvs'][:1];denies(p,'pv ausente')
p=copy.deepcopy(plan);p['roles']['root']['uuid']='falso';denies(p,'uuid diferente')
with patch.object(x.Path,'is_dir',return_value=True),patch.object(x.rehearsal,'mount_guard',return_value=True):
    try:x.validated(plan,snap)
    except ValueError:pass
    else:raise AssertionError('Nao recusou volume montado')
with patch.object(x.Path,'is_dir',return_value=False):
    try:x.validated(plan,snap)
    except ValueError:pass
    else:raise AssertionError('Nao exigiu UEFI')
assert x.main([])==2
bash=(ROOT/'install/wolf-install.sh').read_text()
assert '--execute-multidisk-physical' in bash
assert '--no-nvram' in bash
assert 'FORMATAR $ROOT_DEVICE' in bash
assert 'ACEITO-PERDA-RAIZ' in bash
assert 'revalidate_gui_physical_target\n        mkfs.ext4 -F "$ROOT_DEVICE"' in bash
assert 'FORMAT_ESP=no; FORMAT_HOME=no; CLEAN_HOME_DOTFILES=no' in bash
assert 'install -Dm0644 "$SOURCE/wolf_physical_executor.py"' in (ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
assert 'def execute_multidisk_physical(self)' in (ROOT/'live-gui/main.py').read_text()
result=subprocess.run(['bash',str(ROOT/'install/wolf-install.sh'),'--execute-multidisk-physical'],capture_output=True,text=True)
assert result.returncode==2
print('[OK] alpha47: contrato físico 2xNVMe, LVM multi-PV, UUID e ESP')
print('[OK] alpha47: recusas override, UUID, VM/UEFI, volumes montados e proteção de NVRAM')
print('[OK] alpha47: importador isolado, confirmação dupla, staging GUI e formato exclusivo da raiz')
