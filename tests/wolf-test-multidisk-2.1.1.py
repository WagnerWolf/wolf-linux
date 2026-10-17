#!/usr/bin/env python3
"""Teste estritamente em memória da tradução GUI para um plano multidisco."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'live-gui'))
sys.path.insert(0, str(ROOT/'live-gui/preview'))
import wolf_plan
from planner import parse_lsblk, Choices
from vm_bridge import build_vm_plan, BridgeError

GIB = 1024**3

def node(path, kind, size, fs='', maj='1:1', uid='', children=(), **attrs):
    return dict(path=path,type=kind,size=size,fstype=fs,**{'maj:min':maj},uuid=uid,
                mountpoints=[], children=list(children),**attrs)

def fixture():
    home = node('/dev/mapper/vg_monstro-lv_projetos','lvm',1156*GIB,'ext4','253:0','uuid-home')
    data = dict(blockdevices=[
        node('/dev/nvme1n1','disk',931*GIB,maj='259:0', children=[
            node('/dev/nvme1n1p1','part',GIB,'vfat','259:1','uuid-efi'),
            node('/dev/nvme1n1p2','part',930*GIB,'LVM2_member','259:2','uuid-pv1',children=[home])]),
        node('/dev/nvme0n1','disk',465*GIB,maj='259:3',children=[
            node('/dev/nvme0n1p1','part',100*GIB,'ext4','259:4','uuid-root'),
            node('/dev/nvme0n1p2','part',139*GIB,'ntfs','259:5','uuid-windows'),
            node('/dev/nvme0n1p6','part',226*GIB,'LVM2_member','259:6','uuid-pv2',children=[home])])])
    return data

class MultiDisk(unittest.TestCase):
    def build(self, raw=None, mode='reuse', clean=True, home='/dev/mapper/vg_monstro-lv_projetos', formatting=False):
        raw=raw or fixture()
        gui=parse_lsblk(json.dumps(raw),firmware='UEFI')
        disks=wolf_plan.inventory(json.dumps(raw))
        choice=Choices(mode=mode, root='/dev/nvme0n1p1',efi='/dev/nvme1n1p1',home=home,
                       clean_dotfiles=clean if mode=='reuse' else False,
                       format_home=formatting)
        return gui,disks,choice
    def test_cross_disk_lv_plan_19_fields(self):
        gui,disks,choice=self.build()
        doc=build_vm_plan(gui,choice,'wolf','monstro','full',('br','abnt2',''),disks=disks)
        self.assertEqual(doc['storage']['partitions']['home'],'/dev/mapper/vg_monstro-lv_projetos')
        identity=doc['storage']['role_identity']
        self.assertEqual(len(identity['pv_members']),2)
        self.assertEqual(len(identity['physical_disks']),2)
        self.assertEqual(len(wolf_plan.vm_execution_fields(doc,disks=disks,check_device=False)),19)
        self.assertEqual(wolf_plan.vm_execution_fields(doc,disks=disks)[11],'/dev/nvme0n1p1')
    def test_cross_efi_manual(self):
        gui,disks,choice=self.build(mode='manual')
        doc=build_vm_plan(gui,choice,'wolf','monstro','minimal',('br','abnt2',''),disks=disks)
        self.assertEqual(wolf_plan.vm_execution_fields(doc,disks=disks)[12],'/dev/nvme1n1p1')
    def test_lv_format_blocked(self):
        gui,disks,choice=self.build(mode='manual',formatting=True)
        with self.assertRaisesRegex(BridgeError,'LV'):
            build_vm_plan(gui,choice,'wolf','monstro','minimal',('br','abnt2',''),disks=disks)
    def test_pv_never_role(self):
        gui,disks,choice=self.build(home='/dev/nvme1n1p2')
        with self.assertRaises((wolf_plan.PlanError,BridgeError)):
            build_vm_plan(gui,choice,'wolf','monstro','minimal',('br','abnt2',''),disks=disks)
    def test_changed_pv_blocks(self):
        gui,disks,choice=self.build()
        doc=build_vm_plan(gui,choice,'wolf','monstro','minimal',('br','abnt2',''),disks=disks)
        newer=fixture(); newer['blockdevices'][1]['children'][2]['maj:min']='259:99'
        with self.assertRaisesRegex(wolf_plan.PlanError,'diferente'):
            wolf_plan.vm_execution_fields(doc,disks=wolf_plan.inventory(json.dumps(newer)),check_device=False)
    def test_missing_lv_blocks(self):
        gui,disks,choice=self.build()
        doc=build_vm_plan(gui,choice,'wolf','monstro','minimal',('br','abnt2',''),disks=disks)
        newer=fixture()
        newer['blockdevices'][0]['children'][1]['children']=[]
        newer['blockdevices'][1]['children'][2]['children']=[]
        with self.assertRaises(wolf_plan.PlanError):
            wolf_plan.vm_execution_fields(doc,disks=wolf_plan.inventory(json.dumps(newer)),check_device=False)

if __name__=='__main__':
    unittest.main(verbosity=2)
