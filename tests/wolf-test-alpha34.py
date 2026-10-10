#!/usr/bin/env python3
"""Alpha34: dimensionamento seguro / e /home, sem acesso a dispositivos reais."""
from pathlib import Path
import ast
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'live-gui'))
import wolf_plan as wp

G = 1024**3
KB = {'layout': 'br', 'model': 'abnt2', 'variant': ''}

def drive(n):
    return dict(path='/dev/vda', size=n*G, maj_min='252:0', model='VirtIO',
                transport='', removable=False, mountpoints=[], partitions=[])

def plan(disk_gib, boot, layout, root=0, home=0):
    return wp.build_preview(disks=[drive(disk_gib)],disk_path='/dev/vda',mode='erase',
      preset='minimal',stacks=(),hostname='wolf',username='wolf',boot_mode=boot,
      keyboard=KB,home_layout=layout,erase_sizes={'root_gib':root,'home_gib':home})

def reject(*args):
    try:
        plan(*args)
    except wp.PlanError:
        return
    raise AssertionError(f'O backend aceitou tamanho inseguro: {args!r}')

for boot, reserve in [('UEFI',2), ('BIOS',1)]:
    assert wp.erase_usable_gib(80*G,boot) == 80-reserve
    assert wp.erase_usable_gib(80*G+500,boot) == 80-reserve
    assert wp.erase_size_bounds(80*G,boot,'in-root',0,0)['root_max'] == 80-reserve
    assert wp.erase_size_bounds(80*G,boot,'separate',40,0)['root_max'] == 70-reserve
    assert wp.erase_size_bounds(80*G,boot,'separate',40,0)['home_max'] == 40-reserve
    assert wp.erase_size_bounds(80*G,boot,'separate',40,20)['root_max'] == 60-reserve
    plan(80,boot,'in-root',80-reserve,0)
    plan(80,boot,'separate',40,0)
    plan(80,boot,'separate',40,20)
    plan(80,boot,'separate',80-reserve-10,10)
    reject(80,boot,'in-root',80-reserve+1,0)
    reject(80,boot,'in-root',19,0)
    reject(80,boot,'separate',40,80-reserve-39)
    reject(80,boot,'separate',80-reserve-9,0)
    reject(80,boot,'separate',19,0)
    reject(80,boot,'separate',40,9)
    reject(80,boot,'in-root',0,10)
    reject(21,boot,'separate',20,0)
    assert wp.erase_usable_gib(18*G,boot)<20
    reject(18,boot,'in-root',0,0)

assert wp.erase_usable_gib(0,'UEFI') == 0
assert wp.erase_usable_gib(80*G,'unknown') == 0

src = (ROOT/'live-gui/main.py').read_text()
ast.parse(src)
for expected in ('QSlider(Qt.Orientation.Horizontal)', 'erase_capacity_label',
                 'wolf_plan.erase_usable_gib', 'wolf_plan.erase_size_bounds',
                 'self.update_erase_bounds()', 'self.on_erase_size_changed(',
                 'self.erase_root_slider', 'self.erase_home_slider',
                 'self.disk_combo.currentIndexChanged.connect(self.update_erase_bounds)',
                 'ctrl.setRange(minimum, max(minimum, maximum))',
                 'self._syncing_erase_size'):
    assert expected in src, expected
assert 'setRange(0, 16384)' not in src, 'Campo sem limite de capacidade persistiu na GUI'
assert 'VERSION = "1.4"' in src or 'VERSION = "1.5"' in src or 'VERSION = "1.6"' in src or 'VERSION = "1.7"' in src or 'VERSION = "1.8"' in src or 'VERSION = "1.9"' in src or 'VERSION = "2.0"' in src or 'VERSION = "2.1"' in src
print('[OK] alpha34: capacidade BIOS/UEFI, limites raiz/home, rejeição de valores excessivos, controles sincronizados')
