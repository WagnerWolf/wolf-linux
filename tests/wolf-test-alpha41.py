#!/usr/bin/env python3
"""Testes do laboratório alpha41: sem usar QEMU real nem tocar discos."""
from pathlib import Path
import os
import subprocess
import tempfile

PROJECT=Path(__file__).resolve().parents[1]
runner=PROJECT/'tests/wolf-vm-multidisk.sh'
part=PROJECT/'tests/wolf-lab41-particionar.sh'
verify=PROJECT/'tests/wolf-lab41-verificar.sh'
stager=(PROJECT/'tests/wolf-stage-live-desktop.sh').read_text()
for f in (runner,part,verify):
    assert f.is_file()
    done=subprocess.run(['bash','-n',str(f)],capture_output=True,text=True)
    assert done.returncode==0,(f,done.stderr)
assert 'virtio-blk-pci,drive=wolf41efi,serial=WOLF41EFI' in runner.read_text()
assert 'virtio-blk-pci,drive=wolf41root,serial=WOLF41ROOT' in runner.read_text()
assert '[[ ! -e "$EFI_IMAGE" && ! -e "$ROOT_IMAGE" ]]' in runner.read_text()
assert 'systemd-detect-virt --vm' in part.read_text()
assert 'CRIAR-LAB41' in part.read_text()
assert 'wipefs --no-act --noheadings' in part.read_text()
assert '[[ -d /run/archiso/airootfs ]]' in part.read_text()
assert "[[ \"$virt\" == kvm || \"$virt\" == qemu ]]" in part.read_text()
assert 'pvcreate -y "$A2" "$B3"' in part.read_text()
assert 'lvcreate -y -n lv_projetos -l 100%FREE vg_monstro' in part.read_text()
assert 'UUID=$HOME_UUID /home ext4' in part.read_text()
assert 'WOLF41-PRESERVAR.txt' in part.read_text()
assert 'mkfs.ntfs -Q -F' in part.read_text()
assert 'wolf-lab41-particionar.sh' in stager and 'wolf-lab41-verificar.sh' in stager

with tempfile.TemporaryDirectory(prefix='wolf41-safe-test-') as raw:
    tmp=Path(raw)
    bindir=tmp/'bin'; bindir.mkdir()
    fake=bindir/'qemu-img'
    fake.write_text('#!/bin/bash\n[[ "$1" == create && "$2" == -f && "$3" == qcow2 ]] || exit 2\n: > "$4"\nprintf "%s" "$5" > "$4"\n')
    fake.chmod(0o755)
    env={**os.environ,'WOLF_PROJECT':str(tmp),'PATH':str(bindir)+':'+os.environ['PATH']}
    create=subprocess.run(['bash',str(runner),'create'],env=env,capture_output=True,text=True)
    assert create.returncode==0,(create.stdout,create.stderr)
    lab=tmp/'vm/lab-alpha41-multidisk'
    assert (lab/'wolf41-efi-lvm.qcow2').read_text()=='64G'
    assert (lab/'wolf41-root-lvm.qcow2').read_text()=='96G'
    again=subprocess.run(['bash',str(runner),'create'],env=env,capture_output=True,text=True)
    assert again.returncode==2,again.stdout
    assert (lab/'wolf41-efi-lvm.qcow2').read_text()=='64G'
    assert (lab/'wolf41-root-lvm.qcow2').read_text()=='96G'
    status=subprocess.run(['bash',str(runner),'status'],env=env,capture_output=True,text=True)
    assert status.returncode==0 and 'WOLF41' in status.stdout

# No host/cloud tool runner, the guest partition helper must fail closed.
preflight=subprocess.run(['bash',str(part),'--check'],capture_output=True,text=True)
assert preflight.returncode!=0, 'Guest helper não pode prosseguir fora de uma Live QEMU.'
print('[OK] alpha41: dois qcow2 independentes, criação não destrutiva/idempotente')
print('[OK] alpha41: QEMU identifica cada VirtIO por serial exclusivo')
print('[OK] alpha41: guardas do particionador impedem execução no host')
print('[OK] alpha41: plano EFI + raiz + testemunha + home LVM com dois PVs')
