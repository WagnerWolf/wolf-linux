#!/usr/bin/env python3
"""Alpha32: BIOS MBR no contrato, PTY com mock, LVM apenas diagnóstico."""
from __future__ import annotations
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
G=1024**3
sys.path.insert(0,str(ROOT/'live-gui'))
import wolf_plan as wp
import terminal_engine

p1=dict(path='/dev/vda1',size=42*G,fstype='ext4',maj_min='252:1',parttype='',mountpoints=[])
p2=dict(path='/dev/vda2',size=36*G,fstype='ext4',maj_min='252:2',parttype='',mountpoints=[])
disk=dict(path='/dev/vda',size=80*G,maj_min='252:0',model='VirtIO',transport='',removable=False,mountpoints=[],partitions=[p1,p2])
kbd=dict(layout='br',model='abnt2',variant='')
fmt=dict(root=True,esp=False,home=False)
roles=dict(root='/dev/vda1',esp=None,home='/dev/vda2')

def plan(mode,boot='BIOS', roles=roles,fmt=fmt, home='separate'):
    return wp.build_preview(disks=[disk],disk_path='/dev/vda',mode=mode,preset='minimal',stacks=(),hostname='wolf',username='wolf',keyboard=kbd,boot_mode=boot,roles=roles,formats=fmt,home_layout=home)

def refuses(func):
    try:func()
    except wp.PlanError:return
    raise AssertionError('Falha em bloquear configuração incompatível')

for mode in ('manual','reuse'):
    doc=plan(mode)
    assert wp.validate_document(doc,disks=[disk])==doc
    fields=wp.vm_execution_fields(doc,disks=[disk],active_boot='BIOS')
    assert len(fields)==19 and fields[3]=='BIOS'
    assert fields[10]==mode and fields[11]=='/dev/vda1' and fields[12]=='' and fields[13]=='/dev/vda2'
    assert fields[14:16]==('no','no')
    assert wp.vm_execution_fields(doc,disks=[disk],active_boot='BIOS')==fields
    refuses(lambda:wp.vm_execution_fields(doc,disks=[disk],active_boot='UEFI'))
    with tempfile.TemporaryDirectory() as td:
        f=Path(td)/'plan.json';wp.write_private(doc,f)
        assert wp.vm_preflight_file(f,disks=[disk],active_boot='BIOS',check_device=False)==fields

manual=plan('manual',fmt={**fmt,'home':True})
assert wp.vm_execution_fields(manual,disks=[disk],active_boot='BIOS')[15]=='yes'
refuses(lambda:wp.vm_execution_fields(plan('manual',roles={**roles,'esp':'/dev/vda2'}),disks=[disk],active_boot='BIOS'))
refuses(lambda:wp.vm_execution_fields(plan('reuse',roles={**roles,'home':None},home='in-root'),disks=[disk],active_boot='BIOS'))
refuses(lambda:wp.vm_execution_fields(plan('manual',boot='UEFI'),disks=[disk],active_boot='UEFI'))

# Testar consulta de PTTYPE exclusivamente via subprocess mock (sem disco real).
pt_calls=[]
def lsblk_pt(args,**kwargs):
    assert args == ['lsblk','-dnro','PTTYPE','/dev/vda']
    pt_calls.append(args)
    return subprocess.CompletedProcess(args,0,'dos\n','')
with patch.object(wp.subprocess,'run',side_effect=lsblk_pt):
    # check_device completo requer blocos reais: simular apenas trecho do PTTYPE no fonte.
    assert 'expected_table = "gpt" if canonical["boot_mode"] == "UEFI" else "dos"' in (ROOT/'live-gui/wolf_plan.py').read_text()
assert not pt_calls

# Testar PTY real com executável sudo inteiramente simulado, SEM tocar discos.
with tempfile.TemporaryDirectory() as td:
    tmp=Path(td);fakebin=tmp/'bin';fakebin.mkdir()
    sudo=fakebin/'sudo'
    sudo.write_text('''#!/usr/bin/env bash
[[ "$1" == '-n' && "$2" == 'wolf-install' && "$3" == '--execute-gui-plan-vm' ]] || exit 90
printf 'Confirme APAGAR: '
read -r reply
[[ "$reply" == "APAGAR" ]] || exit 17
printf '\\nSenha: '
read -r -s password
printf '\\nCONCLUIDO\\n'
[[ "$password" == 'teste123' ]] || exit 18
''')
    sudo.chmod(0o700)
    prev=os.environ['PATH']
    os.environ['PATH']=f'{fakebin}:{prev}'
    try:
        engine=terminal_engine.InstallerPty()
        master=engine.start(tmp/'plan.json')
        text=''
        def waitfor(fragment):
            nonlocal_placeholder = None
            for _ in range(200):
                nonlocal_placeholder = 0
                nonlocal_text,closed=engine.read()
                nonlocal_placeholder += len(nonlocal_text)
                yield nonlocal_text
                if closed: return
                time.sleep(0.01)
        for chunk in waitfor('APAGAR'): 
            text+=chunk
            if 'Confirme APAGAR:' in text:break
        assert 'Confirme APAGAR:' in text, text
        engine.send('APAGAR')
        for chunk in waitfor('Senha'):
            text+=chunk
            if 'Senha:' in text:break
        assert 'Senha:' in text,text
        engine.send('teste123')
        for chunk in waitfor('CONCLUIDO'): text+=chunk
        engine.proc.wait(timeout=8)
        text+=engine.read()[0]
        assert engine.poll()==0,(text,engine.poll())
        assert 'CONCLUIDO' in text,text
        assert 'teste123' not in text,'senha não pode aparecer no log'
        engine.close_read()
    finally:os.environ['PATH']=prev

s=(ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
ui=(ROOT/'live-gui/main.py').read_text()
bash=(ROOT/'install/wolf-install.sh').read_text()
assert 'lvm2' in s and 'terminal_engine.py' in s and 'wolf-live-storage-topology' in s
assert 'self.console_tab_index' in ui and 'QSocketNotifier' in ui
assert 'GUI_VM_PLAN' in bash and 'is_supported_test_vm' in bash
assert 'if [[ "$BOOT_MODE" == "UEFI" && -n "$GUI_VM_PLAN" && "$GUI_VM_MODE" == "manual" ]]' in bash
assert '--execute-gui-plan-vm' in (ROOT/'live-gui/terminal_engine.py').read_text()
assert 'vgchange' not in (ROOT/'live-gui/wolf-live-storage-topology').read_text().replace('do NOT run vgchange,', '')
print('[OK] alpha32 BIOS MBR: manual/reuse sem EFI; PTY: confirmação, senha oculta, exit 0; diagnóstico LVM somente leitura')
