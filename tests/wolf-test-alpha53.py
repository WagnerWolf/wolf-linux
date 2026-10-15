#!/usr/bin/env python3
"""Regressões puras do contrato dos três modos do novo instalador; nenhum disco é alterado."""
from __future__ import annotations
import ast
import json
import subprocess
import sys
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'live-gui' / 'preview'))
sys.path.insert(0, str(ROOT / 'live-gui'))
import planner
import vm_bridge
import wolf_plan

G=1024**3

def fixture(boot):
    d={'path':'/dev/vda','name':'vda','type':'disk','size':120*G,'maj:min':'252:0','model':'QEMU virtual', 'tran':'virtio','rm':False,'mountpoints': [],'children':[
        {'path':'/dev/vda1','name':'vda1','type':'part','size':G,'maj:min':'252:1','fstype':'vfat','parttype':'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'},
        {'path':'/dev/vda2','name':'vda2','type':'part','size':55*G,'maj:min':'252:2','fstype':'ext4'},
        {'path':'/dev/vda3','name':'vda3','type':'part','size':63*G,'maj:min':'252:3','fstype':'ext4'}]}
    if boot == 'BIOS':
        d['children']=d['children'][1:]
    raw=json.dumps({'blockdevices':[d]})
    return planner.parse_lsblk(raw,firmware=boot),wolf_plan.inventory(raw)

class Alpha53(unittest.TestCase):
    def _doc(self, boot, choice, keyboard=('br','abnt2','')):
        inv,disks=fixture(boot)
        return vm_bridge.build_vm_plan(inv,choice,'userlinux','linux-pc','minimal',keyboard,disks=disks),disks

    def test_erase_uefi_and_bios(self):
        for boot in ('UEFI','BIOS'):
            with self.subTest(boot=boot):
                c=planner.Choices(mode='erase',erase_disk='/dev/vda',erase_root_gib=40,
                                  erase_home_separate=True,erase_home_gib=40)
                doc, disks=self._doc(boot,c)
                fields=wolf_plan.vm_execution_fields(doc,disks=disks,active_boot=boot)
                self.assertEqual(fields[10],'erase')
                self.assertEqual(fields[-2:],('40','40'))
                self.assertEqual(fields[5],'userlinux')

    def test_manual_uefi_bios(self):
        for boot in ('UEFI','BIOS'):
            with self.subTest(boot=boot):
                c=planner.Choices(mode='manual',root='/dev/vda2',efi='/dev/vda1' if boot=='UEFI' else '',
                                  home='/dev/vda3',bios_disk='/dev/vda' if boot=='BIOS' else '',format_home=True)
                doc, disks=self._doc(boot,c,('us','pc105',''))
                fields=wolf_plan.vm_execution_fields(doc,disks=disks,active_boot=boot)
                self.assertEqual(fields[10],'manual')
                self.assertEqual(fields[15],'yes')
                self.assertEqual(fields[8],'us')

    def test_reuse_uefi_bios(self):
        for boot in ('UEFI','BIOS'):
            with self.subTest(boot=boot):
                c=planner.Choices(mode='reuse',root='/dev/vda2',efi='/dev/vda1' if boot=='UEFI' else '',
                                  home='/dev/vda3',bios_disk='/dev/vda' if boot=='BIOS' else '',clean_dotfiles=True)
                doc, disks=self._doc(boot,c)
                fields=wolf_plan.vm_execution_fields(doc,disks=disks,active_boot=boot)
                self.assertEqual(fields[10],'reuse')
                self.assertEqual(fields[16],'yes')

    def test_unsafe_rejected(self):
        inv,disks=fixture('UEFI')
        cases=[planner.Choices(mode='reuse',root='/dev/vda2',efi='/dev/vda1'),
               planner.Choices(mode='reuse',root='/dev/vda2',efi='/dev/vda1',home='/dev/vda3',backup_dotfiles=True),
               planner.Choices(mode='manual',root='/dev/vda2',efi='/dev/vda2',home='/dev/vda3')]
        for c in cases:
            with self.subTest(c=c):
                with self.assertRaises(vm_bridge.BridgeError):
                    vm_bridge.build_vm_plan(inv,c,'wolf','test','minimal',('br','abnt2',''),disks=disks)
        doc,_=self._doc('UEFI',planner.Choices(mode='erase',erase_disk='/dev/vda',erase_root_gib=40))
        doc['keyboard']={'layout':'br;rm','model':'pc105','variant':''}
        with self.assertRaises(wolf_plan.PlanError):
            wolf_plan.vm_execution_fields(doc,disks=disks,active_boot='UEFI')
        inv.illustrative=True
        with self.assertRaises(vm_bridge.BridgeError):
            vm_bridge.build_vm_plan(inv,planner.Choices(mode='erase',erase_disk='/dev/vda'),
                                    'wolf','test','minimal',('br','abnt2',''),disks=disks)

    def test_not_exec_on_non_live(self):
        doc,_=self._doc('UEFI',planner.Choices(mode='erase',erase_disk='/dev/vda',erase_root_gib=40))
        with self.assertRaises(vm_bridge.BridgeError):
            vm_bridge.check_vm_plan(doc)

    def test_ui_wiring_and_shell_guard(self):
        app=(ROOT/'live-gui/preview/app.py').read_text()
        ast.parse(app)
        self.assertIn("button('Confirmar'",app)
        self.assertIn('check_vm_plan(current)',app)
        self.assertIn("engine.start(plan, mode='--execute-gui-plan-vm-click')", app)
        bash=(ROOT/'install/wolf-install.sh').read_text()
        self.assertIn('--execute-gui-plan-vm-click',bash)
        self.assertIn('GUI_VM_CLICK_CONFIRMED',bash)
        self.assertIn('revalidate_gui_vm_target',bash)
        self.assertIn('is_supported_test_vm',bash)

if __name__=='__main__':
    unittest.main(verbosity=2)
