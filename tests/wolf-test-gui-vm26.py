#!/usr/bin/env python3
"""Testes de aceitação do piloto VM. Proibido modificar discos."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'live-gui'))
import wolf_plan as wp

D = {"path": "/dev/vda", "size": 64*1024**3, "maj_min": "252:0",
     "model": "VirtIO Block", "transport": "", "removable": False,
     "partitions": [], "mountpoints": []}
KB = {"layout":"br", "model":"abnt2", "variant":"thinkpad"}
def make(disks=None, mode="erase", home_layout="in-root", kb=None):
    return wp.build_preview(disks=disks if disks is not None else [D], disk_path="/dev/vda",
        mode=mode, home_layout=home_layout, preset="test",
        stacks=wp.PRESETS['test'], hostname="wolf-test", username="wolf",
        keyboard=kb if kb is not None else KB, boot_mode="UEFI")

def reject(label, fn):
    try: fn()
    except wp.PlanError: return
    raise AssertionError(f'{label}: deveria ser recusado')

c=make()
assert c['execution']=='disabled'
assert wp.vm_erase_fields(c, disks=[D], active_boot='UEFI')[0] == '/dev/vda'
assert wp.vm_erase_fields(c, disks=[D], active_boot='UEFI')[5] == 'wolf'
assert wp.vm_erase_fields(c, disks=[D], active_boot='UEFI')[7] == 'daily,gaming,development,extras'
reject('BIOS divergente', lambda: wp.vm_erase_fields(c, disks=[D], active_boot='BIOS'))
reject('disco trocado', lambda: wp.vm_erase_fields(c, disks=[{**D, 'maj_min':'252:1'}], active_boot='UEFI'))
# Apagar TODO O DISCO deve permitir partições existentes, com confirmação posterior.
partitioned = {**D, 'partitions':[{'path':'/dev/vda1','size':4*1024**3,'fstype':'ext4','mountpoints':[]}]}
assert wp.vm_erase_fields(wp.build_preview(disks=[partitioned], disk_path='/dev/vda', mode='erase',
    preset='test', stacks=wp.PRESETS['test'], hostname='wolf-test', username='wolf',
    keyboard=KB, boot_mode='UEFI'), disks=[partitioned], active_boot='UEFI')[0] == '/dev/vda'
reject('partição montada', lambda: wp.vm_erase_fields(c, disks=[{**D, 'partitions':[{'path':'/dev/vda1','size':4*1024**3,'fstype':'ext4','mountpoints':['/mnt']}]}], active_boot='UEFI'))
reject('montado', lambda: wp.vm_erase_fields(c, disks=[{**D, 'mountpoints':['/mnt']}], active_boot='UEFI'))
reject('removível', lambda: wp.vm_erase_fields(c, disks=[{**D,'removable':True}], active_boot='UEFI'))
reject('USB', lambda: wp.vm_erase_fields(c, disks=[{**D,'transport':'usb'}], active_boot='UEFI'))
reject('pequeno', lambda: wp.vm_erase_fields(c, disks=[{**D,'size':20*1024**3}], active_boot='UEFI'))
reject('sem MAJ:MIN', lambda: wp.vm_erase_fields(c, disks=[{**D,'maj_min':''}], active_boot='UEFI'))
reject('não VirtIO', lambda: wp.vm_erase_fields(make([{**D,'path':'/dev/sda'}]), disks=[{**D,'path':'/dev/sda'}], active_boot='UEFI'))
reject('firmware unknown', lambda: wp.vm_erase_fields({**c,'boot_mode':'unknown'}, disks=[D], active_boot='UEFI'))
reject('alterado', lambda: wp.vm_erase_fields({**c, 'execution':'enabled'}, disks=[D], active_boot='UEFI'))
reject('teclado não suportado', lambda: wp.vm_erase_fields(make(kb={'layout':'us','model':'pc105','variant':''}), disks=[D], active_boot='UEFI'))
reject('modo manual', lambda: wp.vm_erase_fields(make(mode='manual'), disks=[D], active_boot='UEFI'))
reject('modo reuse', lambda: wp.vm_erase_fields(make(mode='reuse'), disks=[D], active_boot='UEFI'))
with tempfile.TemporaryDirectory() as t:
    f=Path(t)/'plan.json'
    f.write_text(json.dumps(c))
    assert wp.vm_preflight_file(f, disks=[D], active_boot='UEFI', check_device=False)[0]=='/dev/vda'
    link=Path(t)/'link.json'; link.symlink_to(f)
    reject('symlink', lambda: wp.vm_preflight_file(link, disks=[D], active_boot='UEFI', check_device=False))
    cli=subprocess.run(['bash',str(ROOT/'install/wolf-install.sh'),'--review-gui-plan',str(f),'--execute-gui-plan-vm',str(f)],capture_output=True,text=True,timeout=10)
    assert cli.returncode != 0, 'modos misturados não podem executar'
    pre=subprocess.run(['bash',str(ROOT/'install/wolf-install.sh'),'--preflight-gui-plan-vm',str(f)],capture_output=True,text=True,timeout=10)
    assert pre.returncode != 0, 'disco fictício em ambiente real não deve passar como bloco'
print('[OK] GUI VM alpha26: 16 barreiras, exportação, CLI independente; nenhum disco foi alterado')
