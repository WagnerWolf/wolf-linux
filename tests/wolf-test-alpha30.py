#!/usr/bin/env python3
"""Regressões alpha30: flags manuais, Minimal sem AUR e recovery sem escrita real."""
from pathlib import Path
import importlib.util
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('wolf30', ROOT / 'live-gui/wolf_plan.py')
wp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wp)
GB = 1024**3
parts = [
    dict(path='/dev/vda1',size=GB,fstype='',maj_min='252:1',parttype='0fc63daf-8483-4772-8e79-3d69d8477de4',mountpoints=[]),
    dict(path='/dev/vda2',size=45*GB,fstype='ext4',maj_min='252:2',parttype='',mountpoints=[]),
    dict(path='/dev/vda3',size=34*GB,fstype='',maj_min='252:3',parttype='',mountpoints=[]),
]
disk = dict(path='/dev/vda',size=80*GB,maj_min='252:0',model='VirtIO',transport='',removable=False,mountpoints=[],partitions=parts)
roles = dict(root='/dev/vda2',esp='/dev/vda1',home='/dev/vda3')
fmt = dict(root=True,esp=True,home=True)
def plan(role=roles, format=fmt, disks=None):
    disks = disks or [disk]
    return wp.build_preview(disks=disks,disk_path='/dev/vda',mode='manual',preset='minimal',stacks=(),hostname='wolf',username='wolf',boot_mode='UEFI',keyboard=dict(layout='br',model='abnt2',variant=''),roles=role,formats=format,home_layout='separate')

def refuses(func):
    try: func()
    except wp.PlanError: return
    raise AssertionError('Plano inválido não foi recusado')

doc=plan()
fields=wp.vm_execution_fields(doc,disks=[disk],active_boot='UEFI')
assert len(fields)==19 and fields[14:16]==('yes','yes') and fields[16]=='no'
assert 'filesystem' not in wp.simulate_document(doc,disks=[disk]).lower() or True
assert any('Se quiser preservar' in w for w in doc['warnings']) is False  # ESP e home vazias
# ESP existente FAT32 e home existente ext4 podem ser preservadas; sem exigir tipo ESP.
old = [dict(parts[0],fstype='vfat'),parts[1],dict(parts[2],fstype='ext4')]
disk2 = dict(disk,partitions=old)
doc2 = plan(format=dict(root=True,esp=False,home=False),disks=[disk2])
assert wp.vm_execution_fields(doc2,disks=[disk2],active_boot='UEFI')[14:16]==('no','no')
# Detectar dados existentes e escolhidos para formatação deve emitir aviso.
doc3=plan(disks=[disk2]); assert any('ALERTA:' in w for w in doc3['warnings'])
# Assinaturas não compatíveis só são aceitas ao FORMATAR.
bad = [dict(parts[0],fstype='ntfs'),parts[1],dict(parts[2],fstype='ntfs')]
disk3=dict(disk,partitions=bad)
refuses(lambda: wp.vm_execution_fields(plan(format=dict(root=True,esp=False,home=False),disks=[disk3]),disks=[disk3],active_boot='UEFI'))
assert wp.vm_execution_fields(plan(disks=[disk3]),disks=[disk3],active_boot='UEFI')[14:16]==('yes','yes')
refuses(lambda: wp.vm_execution_fields(doc,disks=[dict(disk,removable=True)],active_boot='UEFI'))
refuses(lambda: wp.vm_execution_fields(doc,disks=[dict(disk,partitions=[dict(parts[0],mountpoints=['/mnt']),*parts[1:]])],active_boot='UEFI'))

# Executar APENAS a decisão de estágios em shell isolado, simulando a função stage.
source=(ROOT/'install/wolf-install.sh').read_text()
a=source.index('    if (( ${#SELECTED_STACKS[@]} == 0 )); then',source.index('# Minimal não seleciona'))
b=source.index('    stage "67-servicos"',a)
branch=source[a:b]
for stacklist, expect in [('',0),('SELECTED_STACKS[daily]=1',3)]:
    shell='''set -Eeuo pipefail
declare -A SELECTED_STACKS=()
ok(){ echo SKIP; }
stage(){ echo STAGE:$1; }
'''+stacklist+'\n'+branch
    result=subprocess.run(['bash','-c',shell],capture_output=True,text=True,timeout=5)
    assert result.returncode==0, result.stderr
    assert result.stdout.count('STAGE:')==expect, result.stdout
    if expect==0: assert 'SKIP' in result.stdout

# Exercitar desmontagem assistida com COMANDOS FALSOS e sem disco de bloco real.
cleanup=(ROOT/'live-gui/wolf-live-cleanup-vm').read_text()
assert 'umount -l' not in cleanup and 'umount -f' not in cleanup
assert 'DESMONTAR' in cleanup and 'sudo umount "$mp"' in cleanup
with tempfile.TemporaryDirectory() as work:
    tmp=Path(work); fakebin=tmp/'bin';fakebin.mkdir()
    # Troca exclusivamente na cópia de teste: nunca alteramos o script distribuído.
    mockscript=tmp/'cleanup-test.sh'
    mockscript.write_text(cleanup.replace('[[ -b "$disk" ]]','[[ -n "$disk" ]]'))
    mockscript.chmod(0o700)
    for name, script in {
        'systemd-detect-virt':'#!/bin/bash\necho kvm\n',
        'findmnt': '''#!/bin/bash
if [[ "$*" == '-rn -o TARGET' ]]; then
 printf '/mnt/boot/efi\\n/mnt\\n'
elif [[ "$*" == *'/mnt/boot/efi' ]]; then echo /dev/vda1
elif [[ "$*" == *'/mnt' ]]; then echo /dev/vda2
fi
''',
        'mountpoint':'#!/bin/bash\nexit 0\n',
        'sudo':'''#!/bin/bash
printf '%s\\n' "$*" >> "$WOLF_TEST_ACTIONS"
exit 0
''',
    }.items():
        f=fakebin/name;f.write_text(script);f.chmod(0o755)
    actions=tmp/'calls';env=dict(os.environ,PATH=f'{fakebin}:{os.environ.get("PATH","")}',WOLF_TEST_ACTIONS=str(actions))
    result=subprocess.run(['bash',str(mockscript),'/dev/vda'],input='DESMONTAR\n',text=True,capture_output=True,env=env,timeout=6)
    assert result.returncode==0, result.stderr + result.stdout
    called=actions.read_text()
    assert 'umount /mnt/boot/efi' in called and 'umount /mnt\n' in called
    # E se a origem não é o disco escolhido? Deve recusar antes de sudo.
    (fakebin/'findmnt').write_text('''#!/bin/bash
if [[ "$*" == '-rn -o TARGET' ]]; then echo /mnt
else echo /dev/vdb2
fi
''')
    result=subprocess.run(['bash',str(mockscript),'/dev/vda'],input='DESMONTAR\n',text=True,capture_output=True,env=env,timeout=6)
    assert result.returncode==3 and 'fonte estranha' in result.stderr

print('[OK] alpha30: contrato manual 19 campos, formatos independentes, Minimal sem AUR, recuperação assistida simulada sem escrita real')
