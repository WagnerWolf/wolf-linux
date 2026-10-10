#!/usr/bin/env python3
"""Alpha33: layout automático BIOS/UEFI com /home dedicada, tamanhos e BIOS reuse.
Todas as operações Bash de partição são substituídas por stubs; NUNCA grava discos.
"""
from __future__ import annotations
from pathlib import Path
import copy
import json
import os
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'live-gui'))
import wolf_plan as wp
G=1024**3
D = dict(path='/dev/vda',size=80*G,maj_min='252:0',model='VirtIO',transport='',removable=False,mountpoints=[],partitions=[])
KB = dict(layout='br',model='abnt2',variant='thinkpad')

def doc(boot='UEFI', home='in-root', root=0, homesize=0):
    return wp.build_preview(disks=[D],disk_path='/dev/vda',mode='erase',preset='minimal',stacks=(),
      hostname='wolf',username='wolf',boot_mode=boot,keyboard=KB,home_layout=home,
      erase_sizes=dict(root_gib=root,home_gib=homesize))

def rejects(fn):
    try: fn()
    except wp.PlanError: return
    raise AssertionError('configuração insegura foi aceita')

for boot in ('BIOS','UEFI'):
    for home,root,hs in [('in-root',0,0),('in-root',50,0),('separate',40,0),('separate',40,20)]:
        plan=doc(boot,home,root,hs)
        assert wp.validate_document(plan,disks=[D])==plan
        fields=wp.vm_execution_fields(plan,disks=[D],active_boot=boot)
        assert len(fields)==19 and fields[3]==boot and fields[10]=='erase'
        assert fields[13]==('separate' if home=='separate' else '')
        assert fields[17:]==(str(root),str(hs))
        assert '1 GiB' in wp.text_summary(plan) if boot=='UEFI' else 'NÃO necessita EFI' in wp.text_summary(plan)
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'preview.json'
            wp.write_private(plan,path)
            assert wp.vm_preflight_file(path,disks=[D],active_boot=boot,check_device=False)==fields
            bad=copy.deepcopy(plan);bad['storage']['erase_sizes']['root_gib']+=1
            path.write_text(json.dumps(bad))
            rejects(lambda:wp.vm_preflight_file(path,disks=[D],active_boot=boot,check_device=False))
rejects(lambda:doc('UEFI','separate',19,0))
rejects(lambda:doc('UEFI','separate',65,15))
rejects(lambda:doc('BIOS','separate',40,9))
rejects(lambda:doc('UEFI','in-root',0,12))
rejects(lambda:doc('UEFI','in-root',100,0))
# O contrato não permite colar tamanhos do modo erase em manual/reuse.
rejects(lambda:wp.build_preview(disks=[D],disk_path='/dev/vda',mode='manual',preset='minimal',stacks=(),
 hostname='wolf',username='wolf',boot_mode='BIOS',keyboard=KB,erase_sizes={'root_gib':40,'home_gib':0}))

# Testes do particionamento propriamente dito em shell isolado.
# Os comandos wipefs, sgdisk, parted, etc. são substituídos por funções que apenas registram argumentos.
bash=(ROOT/'install/wolf-install.sh').read_text()
a=bash.index('prepare_erase_disk() {');b=bash.index('\nformat_and_mount() {',a)
function=bash[a:b]
for boot in ('UEFI','BIOS'):
 for home,root,hs in [('in-root',0,0),('separate',40,0),('separate',40,20)]:
    stub='''set -Eeuo pipefail
INSTALL_DISK=/dev/vda
STORAGE_MODE=erase
GUI_VM_PLAN=/tmp/fixture-preview.json
GUI_VM_MODE=erase
'''
    stub+=f'BOOT_MODE={boot}\nGUI_ERASE_ROOT_GIB={root}\nGUI_ERASE_HOME_GIB={hs}\nGUI_ERASE_SEPARATE={"yes" if home=="separate" else "no"}\n'
    stub+='''wipefs(){ printf 'wipefs %s\\n' "$*"; }
sgdisk(){ printf 'sgdisk %s\\n' "$*"; }
parted(){ printf 'parted %s\\n' "$*"; }
partprobe(){ :; }
blockdev(){ :; }
udevadm(){ :; }
sleep(){ :; }
lsblk(){ :; }
'''
    proc=subprocess.run(['bash','-c',stub+function+'\nprepare_erase_disk\n'],capture_output=True,text=True,timeout=5)
    assert proc.returncode==0,proc.stderr
    out=proc.stdout
    if boot=='UEFI':
        assert 'sgdisk -n 1:0:+1G -t 1:ef00 /dev/vda' in out
        assert ('sgdisk -n 3:0:' in out)==(home=='separate')
        if home=='separate':assert 'sgdisk -n 2:0:+40G' in out
    else:
        assert 'parted -s /dev/vda mklabel msdos' in out
        assert 'sgdisk' not in out
        assert ('mkpart primary ext4 40961' in out)==(home=='separate')
        if home=='separate': assert out.count('mkpart primary ext4')==2

# BIOS reuse do Bash não pode impor UEFI: o Python já valida BIOS+MBR/sem ESP.
assert '"$BOOT_MODE" == "UEFI" && -n "$HOME_DEVICE"' not in bash
assert '"$BOOT_MODE" == "UEFI"' in bash and "Reutilização BIOS não deve utilizar EFI" in bash
assert 'GUI_ERASE_ROOT_GIB' in bash and 'GUI_ERASE_SEPARATE' in bash
ui=(ROOT/'live-gui/main.py').read_text()
assert 'self.erase_root_gib' in ui and 'self.erase_home_gib' in ui
assert 'MODO BIOS/LEGACY: partição EFI NÃO NECESSÁRIA' in ui
print('[OK] alpha33: BIOS reuse e tamanhos /+/home, GPT ESP fixa 1 GiB, MBR sem EFI; stubs sem escrita')
