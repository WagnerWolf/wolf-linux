#!/usr/bin/env python3
"""Regressões alpha59: contrato estrito Bash/ensaio e etapa Vulkan condicional."""
from pathlib import Path
from unittest.mock import patch
import runpy
import sys
import copy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'live-gui'))
import wolf_physical_rehearsal as rehearsal
import wolf_discovery as discovery

installer = (ROOT / 'install/wolf-install.sh').read_text(encoding='utf-8')
stages = rehearsal.stage_names(installer)
assert '63b-vulkan' in stages
assert stages.index('63-chaotic-aur') < stages.index('63b-vulkan') < stages.index('64-resolver-stacks')

fixture = runpy.run_path(str(ROOT / 'tests/wolf-test-alpha39.py'))
snap = discovery.discover(raw=fixture['lsblk'],
                          fstab_by_root={'/dev/nvme1n1p1': fixture['FSTAB']},
                          boot_mode='UEFI')
plan = fixture['make'](snap)
report = rehearsal.report(plan, stages)
assert len([line for line in report.splitlines() if line.startswith('[NÃO EXECUTADO]') or line.startswith('[NÃO APLICÁVEL]')]) == len(stages)

no_gaming = copy.deepcopy(plan)
no_gaming['software']['stacks'] = [s for s in no_gaming['software']['stacks'] if s != 'gaming']
assert '[NÃO APLICÁVEL] 63b-vulkan: stack Gaming não selecionada.' in rehearsal.report(no_gaming, stages)

with_gaming = copy.deepcopy(plan)
with_gaming['software']['stacks'] = ['gaming']
assert '[NÃO EXECUTADO] 63b-vulkan:' in rehearsal.report(with_gaming, stages)

# O mecanismo de recusa de alterações não catalogadas deve permanecer ativo.
try:
    rehearsal.stage_names(installer.replace('stage "63b-vulkan" install_preferred_vulkan_provider',
                                          'stage "63c-desconhecida" install_preferred_vulkan_provider'))
except rehearsal.RehearsalDenied as exc:
    assert '63c-desconhecida' in str(exc)
else:
    raise AssertionError('Etapa desconhecida deveria bloquear o ensaio')

print('[OK] alpha59: etapa Vulkan catalogada e posição correta no Bash')
print('[OK] alpha59: ensaio marca Vulkan como N/A sem Gaming e executável com Gaming')
print('[OK] alpha59: contrato estrito continua recusando etapas não reconhecidas')
