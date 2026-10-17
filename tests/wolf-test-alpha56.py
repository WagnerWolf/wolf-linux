#!/usr/bin/env python3
"""Regressão da interface alpha56. Nunca acessa /dev nem formata dispositivos."""
from __future__ import annotations
import ast
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
ROOT = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(ROOT/'live-gui'), str(ROOT/'live-gui/preview')]
import planner, vm_bridge, wolf_plan
G=1024**3

def fixtures(dev: str, firmware='UEFI', removable=False, fstypes=('vfat','ext4','ext4')):
    children=[]
    for i,size in enumerate((1,50,60),1):
        path=f'{dev}{"p" if dev[-1].isdigit() else ""}{i}'
        children.append(dict(path=path,type='part',size=size*G,**{'maj:min':f'8:{i}', 'fstype':fstypes[i-1]}))
    raw=json.dumps({'blockdevices':[dict(path=dev,type='disk',size=120*G,**{'maj:min':'8:0'},
                         rm=removable,tran='nvme' if 'nvme' in dev else 'sata', children=children)]})
    return planner.parse_lsblk(raw, firmware=firmware),wolf_plan.inventory(raw),children

class Alpha56(unittest.TestCase):
    def test_generic_sata_nvme_emmc_and_virtio(self):
        for dev in ('/dev/vda','/dev/sda','/dev/nvme0n1','/dev/mmcblk0'):
            with self.subTest(dev=dev):
                inv,disks,parts=fixtures(dev)
                options=[planner.Choices(mode='erase',erase_disk=dev,erase_root_gib=35),
                    planner.Choices(mode='manual',root=parts[1]['path'],efi=parts[0]['path'],home=parts[2]['path']),
                    planner.Choices(mode='reuse',root=parts[1]['path'],efi=parts[0]['path'],home=parts[2]['path'],clean_dotfiles=True)]
                for c in options:
                    with self.subTest(mode=c.mode):
                        doc=vm_bridge.build_vm_plan(inv,c,'wolf','wolf-linux','full',('br','abnt2',''),disks=disks)
                        fields=wolf_plan.vm_execution_fields(doc,disks=disks,active_boot='UEFI',check_device=False)
                        self.assertEqual(fields[0],dev)
                        self.assertEqual(fields[10],c.mode)
    def test_disallowed_disk_and_removable(self):
        for dev in ('/dev/disk/by-id/fake','/dev/null','/tmp/disk'):
            with self.subTest(dev=dev),self.assertRaises(wolf_plan.PlanError):
                wolf_plan.require_install_disk_path(dev)
        inv,disks,_=fixtures('/dev/sda',removable=True)
        with self.assertRaises(vm_bridge.BridgeError):
            vm_bridge.build_vm_plan(inv,planner.Choices(mode='erase',erase_disk='/dev/sda',erase_root_gib=35),
                                    'wolf','linux','full',('br','abnt2',''),disks=disks)
    def test_lvm_pv_rejected_for_manual(self):
        inv,disks,parts=fixtures('/dev/nvme0n1',fstypes=('vfat','LVM2_member','ext4'))
        c=planner.Choices(mode='manual',root=parts[1]['path'],efi=parts[0]['path'],home=parts[2]['path'])
        with self.assertRaisesRegex(vm_bridge.BridgeError, 'LVM'):
            vm_bridge.build_vm_plan(inv,c,'wolf','linux','minimal',('br','abnt2',''),disks=disks)
    def test_no_live_cannot_call_privileged_preflight(self):
        with patch.object(vm_bridge,'_is_live_archiso',return_value=False),patch.object(vm_bridge.subprocess,'run') as runner:
            with self.assertRaises(vm_bridge.BridgeError):vm_bridge.check_vm_plan({})
            runner.assert_not_called()
    def test_full_flow_present_and_ptysafe(self):
        bash=(ROOT/'install/wolf-install.sh').read_text()
        app=(ROOT/'live-gui/preview/app.py').read_text()
        stager=(ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
        ast.parse(app)
        self.assertIn("self.preset_combo.addItem('Escolha Minimal, Basic, Test ou Full...', None)",app)
        self.assertIn('QTimer.singleShot(0, self.apply_keyboard)',app)
        self.assertIn('self.preset_combo.currentData() is None',app)
        self.assertIn('self._gparted.finished.connect',app)
        self.assertIn("'wolf-home-preview-live'",app)
        self.assertIn('wolf-home-preview-live',stager)
        self.assertIn('install_optional_flutter_sdk',bash)
        self.assertIn('if [[ -n "$GUI_VM_PLAN" ]]; then\n        [[ -d /run/archiso/airootfs ]]',bash)
        self.assertIn('revalidate_gui_vm_target',bash)
        self.assertIn('GUI_VM_CLICK_CONFIRMED',bash)
        subprocess.run(['bash','-n',str(ROOT/'install/wolf-install.sh')],check=True)
        subprocess.run(['bash','-n',str(ROOT/'live-gui/wolf-home-preview-live')],check=True)
        self.assertIn((ROOT/'VERSION').read_text().strip(), ('2.0.0-alpha56', '2.0.0-alpha57', '2.0.0-alpha58', '2.0.0-alpha59', '2.0.0', '2.1.0-rc1', '2.1.0', '2.1.1-rc1', '2.1.1-rc2', '2.1.1', '2.1.2-rc1', '2.1.2'))

if __name__=='__main__':unittest.main(verbosity=2)
