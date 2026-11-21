#!/usr/bin/env python3
"""Regression tests: synthetic lsblk inventory only. NEVER touches /dev."""
from pathlib import Path
import sys, json
project = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
sys.path.insert(0, str(project / 'live-gui' / 'preview'))
sys.path.insert(0, str(project / 'live-gui'))
from planner import parse_lsblk, Choices, PreviewError, erase_budget, erase_allocation
import wolf_plan
GIB = 1024**3
assert wolf_plan.VM_MIN_BYTES == 32 * GIB

def inv(gib, firmware):
    raw = {'blockdevices':[{'path':'/dev/sda','name':'sda','type':'disk',
                            'size':gib*GIB,'model':'VBOX HARDDISK','rm':False,
                            'ro':False,'maj:min':'8:0','tran':'sata','mountpoints':[]}]}
    blob=json.dumps(raw)
    return parse_lsblk(blob,firmware=firmware),wolf_plan.inventory(blob)

def expect_failure(fn, label):
    try:
        fn()
    except (PreviewError, wolf_plan.PlanError):
        return
    raise AssertionError(label + ' deveria ser bloqueado')

def backend_check(inv_backend,firmware,root_gib,sep=False,home_gib=0):
    doc=wolf_plan.build_preview(
        disks=inv_backend,disk_path='/dev/sda',mode='erase',preset='minimal',
        stacks=wolf_plan.PRESETS['minimal'],hostname='wolf-linux',username='wolf',
        keyboard={'layout':'br','model':'abnt2','variant':''},boot_mode=firmware,
        home_layout='separate' if sep else 'in-root',
        erase_sizes={'root_gib':root_gib,'home_gib':home_gib})
    return wolf_plan.vm_execution_fields(doc,disks=inv_backend,active_boot=firmware,check_device=False)

for firmware in ('BIOS','UEFI'):
    for size in (20,30,31):
        gui, backend=inv(size,firmware)
        expect_failure(lambda:erase_budget(gui,'/dev/sda'),f'{size} GiB {firmware} GUI')
        expect_failure(lambda:backend_check(backend,firmware,0),f'{size} GiB {firmware} executor')
    gui,backend=inv(32,firmware)
    budget=erase_budget(gui,'/dev/sda')
    assert budget.usable_gib in (30,31)
    assert erase_allocation(gui,Choices(mode='erase',erase_disk='/dev/sda',
                        erase_root_gib=budget.usable_gib)).root_gib==budget.usable_gib
    assert backend_check(backend,firmware,budget.usable_gib)[0]=='/dev/sda'
    expect_failure(lambda:erase_allocation(gui,Choices(mode='erase',erase_disk='/dev/sda',
                    erase_home_separate=True,erase_root_gib=25)), '32 GiB com /home separada')
    for size in (35,40,120):
        gui,backend=inv(size,firmware)
        budget=erase_budget(gui,'/dev/sda')
        assert budget.usable_gib <= size-1
        root=min(60,budget.usable_gib-10)
        choice=Choices(mode='erase',erase_disk='/dev/sda',erase_home_separate=True,
                       erase_root_gib=root)
        if budget.usable_gib < 35:
            expect_failure(lambda:erase_allocation(gui,choice),f'{size} {firmware} /home abaixo do limite')
            continue
        allocation=erase_allocation(gui,choice)
        assert allocation.root_gib + allocation.home_gib <= budget.usable_gib
        assert allocation.root_gib <= budget.usable_gib - 10
        assert backend_check(backend,firmware,root,sep=True)[0]=='/dev/sda'
        expect_failure(lambda:erase_allocation(gui,Choices(mode='erase',erase_disk='/dev/sda',
                        erase_home_separate=True,erase_root_gib=budget.usable_gib)),
                        'raiz excessiva com /home separada')
        expect_failure(lambda:backend_check(backend,firmware,budget.usable_gib+1),
                        'raiz superior ao espaço permitido no backend')
print('[OK] discos sintéticos 20, 30, 31, 32, 35, 40 e 120 GiB em BIOS/UEFI; GUI e backend concordam.')
