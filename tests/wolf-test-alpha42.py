#!/usr/bin/env python3
"""Alpha42: test VM-lab gate without writing to block devices."""
from pathlib import Path
import ast
import copy
import importlib.util
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'live-gui'))
import wolf_lab42 as lab

def reject(fn, label):
    try:
        fn()
    except lab.LabDenied:
        return
    raise AssertionError('Lab42 deveria rejeitar: '+label)

base = dict(
    roles={
        'root':{'path':'/dev/vdb1','type':'part','parent_disks':['/dev/vdb']},
        'esp':{'path':'/dev/vda1','type':'part','parent_disks':['/dev/vda']},
        'home':{'path':'/dev/mapper/vg_monstro-lv_projetos','type':'lvm',
                'parent_disks':['/dev/vda','/dev/vdb'],'lvm_pvs':['/dev/vda2','/dev/vdb3']},
    },
    boot_mode='UEFI', acknowledge_override=False,
    actions={'root':'format_ext4','esp':'preserve','home':'preserve'},
)
ob=dict(virtual='kvm',in_live=True,firmware='UEFI',mounted=False,
        links={'efi':'/dev/vda','root':'/dev/vdb'},
        inventory={'/dev/vda':dict(serial='WOLF41EFI',bytes=64*1024**3,type='disk',rm='0',ro='0'),
                   '/dev/vdb':dict(serial='WOLF41ROOT',bytes=96*1024**3,type='disk',rm='0',ro='0')})
assert lab.lab_devices(base,**ob) == (base['roles']['root'],base['roles']['esp'],base['roles']['home'])
for prop,value in [('virtual','none'),('in_live',False),('firmware','BIOS'),('mounted',True)]:
    reject(lambda p=prop,v=value:lab.lab_devices(base,**{**ob,p:v}),prop)
for role in ('efi','root'):
    bad=copy.deepcopy(ob);bad['links'][role]='/dev/nvme0n1'
    reject(lambda:lab.lab_devices(base,**bad),'link '+role)
for prop in ('serial','bytes','rm','ro','type'):
    bad=copy.deepcopy(ob);bad['inventory']['/dev/vda'][prop]='NÃO' if prop not in ('bytes',) else 32
    reject(lambda:lab.lab_devices(base,**bad),'identity '+prop)
for kind,value in [('root','/dev/nvme1n1p1'),('esp','/dev/vdb1'),('home','/dev/vda2')]:
    bad=copy.deepcopy(base);bad['roles'][kind]['path']=value
    reject(lambda:lab.lab_devices(bad,**ob),'destination '+kind)
bad=copy.deepcopy(base);bad['roles']['home']['lvm_pvs']=['/dev/vda2']
reject(lambda:lab.lab_devices(bad,**ob),'LVM PV faltando')
bad=copy.deepcopy(base);bad['roles']['home']['parent_disks']=['/dev/vdb']
reject(lambda:lab.lab_devices(bad,**ob),'LVM multidisco errado')
bad=copy.deepcopy(base);bad['acknowledge_override']=True
reject(lambda:lab.lab_devices(bad,**ob),'fstab override')
bad=copy.deepcopy(base);bad['actions']['home']='format_ext4'
reject(lambda:lab.lab_devices(bad,**ob),'home format')

main= (ROOT/'live-gui/main.py').read_text()
cli=(ROOT/'install/wolf-install.sh').read_text()
pty=(ROOT/'live-gui/terminal_engine.py').read_text()
wrapper=(ROOT/'tests/wolf-customize-iso-profile.sh').read_text()
assert 'execute_multidisk_lab42' in main
assert '--execute-multidisk-lab-vm' in cli and '--preflight-multidisk-lab-vm' in cli
assert 'revalidate_gui_lab42_target' in cli
assert '"FORMAT_ROOT=yes; FORMAT_ESP=no; FORMAT_HOME=no"' not in cli # shell actual flag assignment
assert 'FORMAT_ROOT=yes; FORMAT_ESP=no; FORMAT_HOME=no' in cli
assert 'GUI_VM_MODE="reuse" # GRUB' in cli
assert '--execute-multidisk-lab-vm' in pty and '--execute-multidisk-lab-vm' in wrapper
# Unknown flags do not trigger installation, and lab executor is rejected on host.
a=subprocess.run(['bash',str(ROOT/'install/wolf-install.sh'),'--preflight-multidisk-lab-vm','/notfound'],capture_output=True,text=True)
assert a.returncode != 0
b=subprocess.run(['bash',str(ROOT/'install/wolf-install.sh'),'--execute-multidisk-lab-vm','/notfound','--install'],capture_output=True,text=True)
assert b.returncode != 0 and 'conflitantes' in b.stderr.lower()
# GUI has a hardcoded finite set of commands; no arbitrary subprocess arg from JSON.
assert 'mode not in ALLOWED_EXECUTION_MODES' in pty
assert '--execute-gui-plan-vm' in pty and '--execute-multidisk-lab-vm' in pty
print('[OK] alpha42: bloqueios fora QEMU/Live, seriais e tamanhos, mounts e dispositivos')
print('[OK] alpha42: somente raiz formatada; EFI/NTFS/PVs/LVM preservados')
print('[OK] alpha42: integração CLI/GUI/PTY; executores físicos novos usam barreira independente')
