#!/usr/bin/env python3
"""Regressões alpha29: VM manual/erase, nenhum disco real é modificado."""
from __future__ import annotations
from pathlib import Path
from unittest.mock import patch
import importlib.util
import copy
import subprocess
import sys

P = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("wolf29_plan", P / "live-gui/wolf_plan.py")
wp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wp)
GB = 1024**3
P1 = dict(path='/dev/vda1', size=GB, fstype='vfat', maj_min='252:1', parttype='c12a7328-f81f-11d2-ba4b-00a0c93ec93b', mountpoints=[])
P2 = dict(path='/dev/vda2', size=52*GB, fstype='ext4', maj_min='252:2', mountpoints=[])
P3 = dict(path='/dev/vda3', size=27*GB, fstype='ext4', maj_min='252:3', mountpoints=[])
D = dict(path='/dev/vda', size=80*GB, maj_min='252:0', model='VirtIO',
         transport='', removable=False, mountpoints=[], partitions=[P1, P2, P3])
KB = dict(layout='br', model='abnt2', variant='thinkpad')
F = dict(root=True, esp=False, home=False)
R = dict(root='/dev/vda2', esp='/dev/vda1', home=None)

def plan(mode, **extra):
    return wp.build_preview(disks=extra.get("disks", [D]), disk_path='/dev/vda', mode=mode,
                            preset='minimal', stacks=(), hostname='wolf-vm',
                            username='wolf', boot_mode='UEFI', keyboard=KB,
                            roles=extra.get('roles'), formats=extra.get('formats'),
                            home_layout=extra.get('home_layout', 'in-root'))

def fails(description, fn):
    try:
        fn()
    except wp.PlanError:
        return
    raise AssertionError(f'{description} deveria ser recusado')

# Apagar DISCO INTEIRO com partições/assinaturas antigas agora é legítimo.
erase = plan('erase')
fields = wp.vm_execution_fields(erase, disks=[D], active_boot='UEFI')
assert len(fields) == 19 and fields[10] == 'erase' and fields[0] == '/dev/vda'
assert '/home' in wp.text_summary(erase)
assert 'TODAS as partições' in wp.simulate_document(erase, disks=[D])
fails('disco removível', lambda: wp.vm_execution_fields(erase, disks=[{**D, 'removable':True}], active_boot='UEFI'))
fails('partição montada', lambda: wp.vm_execution_fields(erase, disks=[{**D,'partitions':[P1 | {'mountpoints':['/mnt']},P2,P3]}], active_boot='UEFI'))

# Manual: raiz formatada, ESP e home preservadas; firmware UEFI obrigatório.
manual = plan('manual', roles=R, formats=F)
assert wp.validate_document(manual, disks=[D]) == manual
exported = wp.vm_execution_fields(manual, disks=[D], active_boot='UEFI')
assert len(exported) == 19 and exported[10:] == ('manual', '/dev/vda2', '/dev/vda1', '', 'no', 'no', 'no', '0', '0')
assert 'Raiz /: formatada ext4' in wp.simulate_document(manual, disks=[D])
separate = plan('manual', roles=R | {'home':'/dev/vda3'}, formats=F, home_layout='separate')
assert wp.vm_execution_fields(separate, disks=[D], active_boot='UEFI')[13] == '/dev/vda3'

fails('manual BIOS', lambda: wp.vm_execution_fields(manual, disks=[D], active_boot='BIOS'))
fails('raiz sem formatação', lambda: wp.vm_execution_fields(plan('manual', roles=R, formats={**F, 'root':False}), disks=[D], active_boot='UEFI'))
assert wp.vm_execution_fields(plan('manual', roles=R, formats={**F, 'esp':True}), disks=[D], active_boot='UEFI')[14] == 'yes'
assert wp.vm_execution_fields(plan('manual', roles=R|{'home':'/dev/vda3'},
    formats={**F,'home':True}, home_layout='separate'), disks=[D], active_boot='UEFI')[15] == 'yes'
fails('ESP menor que 512MB', lambda: wp.vm_execution_fields(manual, disks=[{**D,'partitions':[P1|{'size':256*1024**2},P2,P3]}], active_boot='UEFI'))
assert wp.vm_execution_fields(plan('manual',roles=R,formats=F,disks=[{**D,'partitions':[P1|{'parttype':''},P2,P3]}]), disks=[{**D,'partitions':[P1|{'parttype':''},P2,P3]}], active_boot='UEFI')[10] == 'manual'
fails('ESP não FAT32 sem formatação', lambda: wp.vm_execution_fields(manual, disks=[{**D,'partitions':[P1|{'fstype':'ntfs'},P2,P3]}], active_boot='UEFI'))
assert wp.vm_execution_fields(plan('manual', roles=R, formats={**F,'esp':True}, disks=[{**D,'partitions':[P1|{'fstype':'ntfs'},P2,P3]}]), disks=[{**D,'partitions':[P1|{'fstype':'ntfs'},P2,P3]}], active_boot='UEFI')[14] == 'yes'
fails('raiz pequena', lambda: wp.vm_execution_fields(manual, disks=[{**D,'partitions':[P1,P2|{'size':10*GB},P3]}], active_boot='UEFI'))
fails('home não ext4 sem formatação', lambda: wp.vm_execution_fields(separate, disks=[{**D,'partitions':[P1,P2,P3|{'fstype':'ntfs'}]}], active_boot='UEFI'))
assert wp.vm_execution_fields(plan('manual', roles=R|{'home':'/dev/vda3'}, formats={**F,'home':True}, home_layout='separate', disks=[{**D,'partitions':[P1,P2,P3|{'fstype':'ntfs'}]}]), disks=[{**D,'partitions':[P1,P2,P3|{'fstype':'ntfs'}]}], active_boot='UEFI')[15] == 'yes'
fails('partição / montada', lambda: wp.vm_execution_fields(manual, disks=[{**D,'partitions':[P1,P2|{'mountpoints':['/mnt']},P3]}], active_boot='UEFI'))
fails('partição desaparecida', lambda: wp.vm_execution_fields(manual, disks=[{**D,'partitions':[P1,P3]}], active_boot='UEFI'))
fails('reutilização bloqueada', lambda: wp.vm_execution_fields(plan('reuse',roles=R,formats=F),disks=[D],active_boot='UEFI'))

# O contrato CLI deve continuar separado de --install e --execute-gui-plan-vm.
ui = (P/'live-gui/main.py').read_text(encoding='utf-8')
bash = (P/'install/wolf-install.sh').read_text(encoding='utf-8')
assert 'expected = "APAGAR"' in ui
assert 'self.partition_roles["home"]' in ui
assert 'Raiz /' in ui or 'RAIZ /' in ui
assert 'GUI_VM_MODE="${fields[10]}"' in bash
assert 'STORAGE_MODE="reuse-manual"' in bash
assert 'FORMAT_ESP="${fields[14]}"' in bash
assert 'HOME_DEVICE="${fields[13]}"' in bash
assert '"${pkg//[[:space:]]/}"' in bash

print('[OK] alpha30: manual UEFI, ESP sem flag, /home e EFI formatáveis, proteção de dados, contrato 19 campos; nenhuma escrita')
