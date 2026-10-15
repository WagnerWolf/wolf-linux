#!/usr/bin/env python3
"""Contrato alpha46: roteiro do Bash, recusa física e topologia de dois NVMe sem escrita."""
from pathlib import Path
from unittest.mock import patch
import copy
import runpy
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'live-gui'))
import wolf_discovery as wd
import wolf_physical_rehearsal as pr

fixture = runpy.run_path(str(ROOT/'tests/wolf-test-alpha39.py'))
snap = wd.discover(raw=fixture['lsblk'], fstab_by_root={'/dev/nvme1n1p1': fixture['FSTAB']}, boot_mode='UEFI')
plan = fixture['make'](snap)
assert wd.validate_plan(plan, snap) == plan
stages = pr.stage_names((ROOT/'install/wolf-install.sh').read_text())
assert len(stages) >= 20 and stages[0] == '10-preparar-disco' and stages[-1] == '80-finalizar'
text = pr.report(plan, stages)
assert 'Formataria SOMENTE /dev/nvme1n1p1' in text
for needle in ['/dev/nvme1n1p1', '/dev/nvme0n1p1', '/dev/mapper/vg_monstro-lv_projetos',
               '/dev/nvme0n1p2', '/dev/nvme1n1p6', 'pacstrap', 'NÃO EXECUTADO',
               'RESULTADO: ENSAIO DE PLANO APROVADO', 'NÃO EQUIVALE A INSTALAÇÃO FÍSICA HOMOLOGADA',
               '63-chaotic-aur', '70-bootloader', 'EFI/Microsoft']:
    assert needle in text, needle
assert text.count('[NÃO EXECUTADO]') + text.count('[NÃO APLICÁVEL]') == len(stages)


def deny(changed, why):
    try:
        pr.evaluate(changed)
    except pr.RehearsalDenied:
        return
    raise AssertionError('Ensaio deveria bloquear: ' + why)

# O próprio contrato original rejeita qualquer troca de UUID ou caminho.
changed = copy.deepcopy(plan);changed['roles']['esp']['uuid']='fraude'
try:
    wd.validate_plan(changed, snap)
except wd.DiscoveryError:
    pass
else:
    raise AssertionError('Plano alterado não foi bloqueado')
for key, val in [('boot_mode','BIOS'),('acknowledge_override',True)]:
    bad=copy.deepcopy(plan);bad[key]=val;deny(bad,key)
bad=copy.deepcopy(plan);bad['actions']['esp']='format_vfat';deny(bad,'formatar esp')
bad=copy.deepcopy(plan);bad['roles']['home']['lvm_pvs']=['/dev/nvme0n1p2'];deny(bad,'falta PV')
bad=copy.deepcopy(plan);bad['roles']['root']['parent_disks']=['/dev/nvme0n1'];deny(bad,'root e EFI mesma unidade')
try:
    pr.evaluate(plan,mounts=True)
except pr.RehearsalDenied:
    pass
else:
    raise AssertionError('Montagens ativas não bloquearam ensaio')
# Compatibilidade estrita: adição ou supressão de etapa no Bash => falha imediata.
source = (ROOT/'install/wolf-install.sh').read_text()
try:
    pr.stage_names(source.replace('stage "30-pacstrap" install_base_system', 'stage "30-NOVA-ETAPA" install_base_system'))
except pr.RehearsalDenied:
    pass
else:
    raise AssertionError('Etapa Bash desconhecida não bloqueou')

with patch.object(pr.os, 'geteuid', return_value=0), \
     patch.object(pr.Path, 'is_dir', return_value=False):
    assert pr.main(['/tmp/preview.json']) == 2 # exige Live
result = subprocess.run(['bash', str(ROOT/'install/wolf-install.sh'), '--rehearse-multidisk-physical'],
                        capture_output=True,text=True)
assert result.returncode == 2
# Segurança estática: CLI ensaio usa exec python antes do main Bash, sem flags write.
assert source.find('--rehearse-multidisk-physical') < source.find('while (($#))')
assert 'exec /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_physical_rehearsal.py" "$2"' in source
assert '--rehearse-multidisk-physical|' in (ROOT/'tests/wolf-customize-iso-profile.sh').read_text()
ui = (ROOT/'live-gui/main.py').read_text()
assert 'def rehearse_physical(self)' in ui and 'wolf-live-physical-rehearsal' in ui
stage = (ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
assert 'wolf_physical_rehearsal.py' in stage and 'wolf-live-physical-rehearsal' in stage
assert pr.mount_guard({'devices': {'/dev/nvme1n1p1': {'mountpoints': ['/somewhere']}}}, plan)
print(f'[OK] alpha46: roteiro em {len(stages)} etapas derivado do Bash, SEM chamar operações destrutivas')
print('[OK] alpha46: bloqueios UEFI, EFI, PV, montagem e JSON alterado; Live exigida')
print('[OK] alpha46: GUI/CLI/staging, segurança do lançador e divergência de etapas')
