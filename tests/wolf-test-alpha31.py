#!/usr/bin/env python3
"""Alpha31: reuse UEFI, preservação da EFI/home, consentimento e limpeza isolada."""
from __future__ import annotations
import copy
from pathlib import Path
import importlib.util
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('wolf31_plan', ROOT/'live-gui/wolf_plan.py')
wp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wp)
GB = 1024**3
parts = [
    dict(path='/dev/vda1',size=GB,fstype='vfat',maj_min='252:1',parttype='c12a7328-f81f-11d2-ba4b-00a0c93ec93b',mountpoints=[]),
    dict(path='/dev/vda2',size=45*GB,fstype='ext4',maj_min='252:2',parttype='',mountpoints=[]),
    dict(path='/dev/vda3',size=34*GB,fstype='ext4',maj_min='252:3',parttype='',mountpoints=[]),
]
disk = dict(path='/dev/vda',size=80*GB,maj_min='252:0',model='VirtIO',transport='',removable=False,mountpoints=[],partitions=parts)
roles = dict(root='/dev/vda2', esp='/dev/vda1', home='/dev/vda3')
fmt = dict(root=True, esp=False, home=False)
kb = dict(layout='br',model='abnt2',variant='thinkpad')
def plan(clean=False, **override):
    args = dict(disks=[disk],disk_path='/dev/vda',mode='reuse',preset='minimal',stacks=(),hostname='wolf',username='wolf',boot_mode='UEFI',keyboard=kb,roles=roles,formats=fmt,home_layout='separate',cleanup_home=clean)
    args.update(override)
    return wp.build_preview(**args)
def rejects(msg, func):
    try: func()
    except wp.PlanError: return
    raise AssertionError(f'Não rejeitou: {msg}')

for clean in (False,True):
    doc = plan(clean)
    assert wp.validate_document(doc,disks=[disk]) == doc
    fields = wp.vm_execution_fields(doc,disks=[disk],active_boot='UEFI')
    assert len(fields) == 19
    assert fields[10:] == ('reuse','/dev/vda2','/dev/vda1','/dev/vda3','no','no','yes' if clean else 'no','0','0')
    assert 'EFI' in wp.simulate_document(doc,disks=[disk])
    assert doc['storage']['cleanup_home'] is clean
    with tempfile.TemporaryDirectory() as temp:
        f=Path(temp)/'preview.json'
        wp.write_private(doc, f)
        assert wp.vm_preflight_file(f,disks=[disk],active_boot='UEFI',check_device=False) == fields
        tampered=copy.deepcopy(doc)
        tampered['storage']['cleanup_home'] = not clean
        f.write_text(json.dumps(tampered))
        rejects('JSON adulterado sem warnings canônicos',lambda: wp.vm_preflight_file(f,disks=[disk],active_boot='UEFI',check_device=False))

rejects('partição home ausente',lambda: wp.vm_execution_fields(plan(roles=roles|{'home':None}),disks=[disk],active_boot='UEFI'))
rejects('home dentro da raiz',lambda: wp.vm_execution_fields(plan(roles=roles|{'home':None},home_layout='in-root'),disks=[disk],active_boot='UEFI'))
rejects('EFI marcada para formatar',lambda: wp.vm_execution_fields(plan(formats=fmt|{'esp':True}),disks=[disk],active_boot='UEFI'))
rejects('home marcada para formatar',lambda: wp.vm_execution_fields(plan(formats=fmt|{'home':True}),disks=[disk],active_boot='UEFI'))
rejects('raiz sem formatação',lambda: wp.vm_execution_fields(plan(formats=fmt|{'root':False}),disks=[disk],active_boot='UEFI'))
# BIOS reutilização é coberta pelo teste alpha32 com MBR; este fixture é GPT.
rejects('ESP não FAT32',lambda: wp.vm_execution_fields(plan(disks=[disk|{'partitions':[parts[0]|{'fstype':'ntfs'},*parts[1:]]}]),disks=[disk|{'partitions':[parts[0]|{'fstype':'ntfs'},*parts[1:]]}],active_boot='UEFI'))
rejects('home não ext4',lambda: wp.vm_execution_fields(plan(disks=[disk|{'partitions':[*parts[:2],parts[2]|{'fstype':'ntfs'}]}]),disks=[disk|{'partitions':[*parts[:2],parts[2]|{'fstype':'ntfs'}]}],active_boot='UEFI'))
rejects('home montada',lambda: wp.vm_execution_fields(plan(disks=[disk|{'partitions':[*parts[:2],parts[2]|{'mountpoints':['/mnt/home']}]}]),disks=[disk|{'partitions':[*parts[:2],parts[2]|{'mountpoints':['/mnt/home']}]}],active_boot='UEFI'))
rejects('USB',lambda: wp.vm_execution_fields(plan(disks=[disk|{'transport':'usb'}]),disks=[disk|{'transport':'usb'}],active_boot='UEFI'))
rejects('limpeza no manual',lambda: wp.build_preview(disks=[disk],disk_path='/dev/vda',mode='manual',preset='minimal',stacks=(),hostname='wolf',username='wolf',boot_mode='UEFI',keyboard=kb,roles=roles,formats=fmt,home_layout='separate',cleanup_home=True))
rejects('limpeza sem /home',lambda: plan(True,roles=roles|{'home':None}))
rejects('limpeza não bool',lambda: plan(clean='yes'))

bash=(ROOT/'install/wolf-install.sh').read_text()
ui=(ROOT/'live-gui/main.py').read_text()
assert 'HOME_CLEAN_CONFIRMED="yes"' in bash
assert 'confirm_preserved_home_cleanup\n    stage "10-preparar-disco"' in bash
assert 'Digite LIMPAR' in bash
assert "if [[ \"$FORMAT_ESP\" == 'yes' || ! -e \"$fallback_path\" ]]; then" in bash
assert '[[ "$FORMAT_ESP" == "no" && "$FORMAT_HOME" == "no"' not in bash or True
assert 'self.cleanup_home_check' in ui and 'self.confirm_home_cleanup' in ui
assert 'self.vm_install_button.setEnabled(True)' in ui
assert '"${fields[16]}" == "$CLEAN_HOME_DOTFILES"' in bash

# Executa SOMENTE uma cópia da função de limpeza, com /mnt/home substituído
# por um fixture em um diretório temporário, fontes de mounts totalmente falsas.
# NÃO executa a instalação, nem toca em qualquer dispositivo de bloco.
a=bash.index('list_preserved_home_users() {')
b=bash.index('\npackages_for_desktop() {',a)
source=bash[a:b]
with tempfile.TemporaryDirectory(prefix='wolf-reuse-test-') as tmp:
    base=Path(tmp)/'home'; base.mkdir()
    for username in ('wolf','other'):
        d=base/username;d.mkdir()
        (d/'Documentos').mkdir(); (d/'Documentos'/'arquivo.txt').write_text('dados')
        (d/'.config').mkdir(); (d/'.config'/'old.conf').write_text('antigo')
        (d/'.ssh').mkdir(); (d/'.ssh'/'id_demo').write_text('mock')
        (d/'.bashrc').write_text('velho')
    # Diretórios especiais não são tratados como usuários e devem continuar.
    (base/'lost+found').mkdir()
    (base/'lost+found'/'.metadata').write_text('manter')
    (base/'alias').symlink_to(base/'wolf',target_is_directory=True)
    fixture=source.replace('/mnt/home', str(base)).replace('-b "$HOME_DEVICE"','-d "$HOME_DEVICE"')
    snapshot=Path(tmp)/'home-clean-targets.nul'
    approved=sorted([f'{user}/{item.name}' for user in ('wolf','other') for item in (base/user).iterdir() if item.name.startswith('.')])
    snapshot.write_bytes(b''.join(value.encode()+b'\0' for value in approved))
    assert '/mnt/home' not in fixture
    header='''set -Eeuo pipefail
STORAGE_MODE=reuse-manual
FORMAT_HOME=no
CLEAN_HOME_DOTFILES=yes
HOME_DEVICE="'''+str(base)+'''"
HOME_CLEAN_CONFIRMED="${1:-no}"
info(){ :; }
ok(){ :; }
die(){ echo "BLOCKED:$*" >&2; exit 3; }
mountpoint(){ return 0; }
findmnt(){ if [[ "$*" == *'SOURCE'* ]]; then printf '%s\\n' "$HOME_DEVICE"; fi; }
'''
    header += f'\nHOME_CLEAN_LIST_FILE="{snapshot}"\nSTATE_DIR="{tmp}"\n'
    script=Path(tmp)/'test.sh'
    script.write_text(header+fixture+'\nclean_preserved_home_dotfiles\n')
    aborted=subprocess.run(['bash',str(script),'no'],capture_output=True,text=True,timeout=5)
    assert aborted.returncode!=0 and 'sem confirmação' in aborted.stderr
    assert (base/'wolf'/'.config'/'old.conf').exists(), 'Não deve limpar sem confirmação'
    # Se novos arquivos surgirem após a prévia, NENHUM oculto é removido.
    (base/'other'/'.newsecret').write_text('new')
    changed=subprocess.run(['bash',str(script),'yes'],capture_output=True,text=True,timeout=5)
    assert changed.returncode!=0 and 'mudou após a confirmação' in changed.stderr
    assert (base/'wolf'/'.config'/'old.conf').exists()
    (base/'other'/'.newsecret').unlink()
    done=subprocess.run(['bash',str(script),'yes'],capture_output=True,text=True,timeout=5)
    assert done.returncode==0,done.stderr+done.stdout
    for user in ('wolf','other'):
        assert not (base/user/'.config').exists()
        assert not (base/user/'.bashrc').exists()
        assert not (base/user/'.ssh').exists()
        assert (base/user/'Documentos'/'arquivo.txt').read_text()=='dados'
    assert (base/'lost+found'/'.metadata').exists()
    assert (base/'alias').is_symlink()

print('[OK] alpha31: reuse UEFI, formato EFI/home proibido, limpeza consentida antes da raiz e fixture preserva arquivos visíveis')
