import json
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'live-gui' / 'preview'))
from planner import (GIB, Choices, PreviewError, demo_inventory, parse_lsblk,
                     validate_plan, safe_export, human_size, erase_budget, erase_allocation)


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.inv = demo_inventory()
        self.base = Choices(mode='reuse', root='/dev/sda2', efi='/dev/sda1',
                            home='/dev/mapper/volume-home')

    def test_dedupe_lvm_on_two_disks(self):
        inv = self.inv
        self.assertEqual(len([d for d in inv.volumes if d.path=='/dev/mapper/volume-home']),1)
        self.assertEqual(inv.disk_ancestors('/dev/mapper/volume-home'),{'/dev/sdb','/dev/nvme0n1'})

    def test_reuse_cross_disk_preserves_efi_lvm(self):
        ops = validate_plan(self.inv,self.base)
        self.assertEqual([x.action for x in ops],['Formatar / em ext4','Reaproveitar EFI','Preservar /home'])
        self.assertEqual(sum(x.destructive for x in ops),1)
        self.assertNotIn('Apagar unidade inteira', [x.action for x in ops])

    def test_reuse_dotfiles_optional_backup(self):
        self.base.clean_dotfiles=True
        ops = validate_plan(self.inv, self.base)
        self.assertEqual(ops[-1].action,'Remover entradas ocultas')
        self.base.backup_dotfiles=True
        ops = validate_plan(self.inv, self.base)
        self.assertEqual(ops[-1].action,'Salvar backup opcional')

    def test_reuse_dotfiles_requires_home(self):
        self.base.clean_dotfiles=True
        self.base.home=''
        with self.assertRaises(PreviewError):
            validate_plan(self.inv,self.base)

    def test_duplicate_roles(self):
        self.base.home='/dev/sda2'
        with self.assertRaisesRegex(PreviewError,'mesmo volume'):
            validate_plan(self.inv,self.base)

    def test_efi_vfat_required_to_preserve(self):
        self.base.efi='/dev/sda3'
        with self.assertRaises(PreviewError):
            validate_plan(self.inv,self.base)

    def test_erase_does_not_need_partition_roles(self):
        c=Choices(mode='erase',erase_disk='/dev/sda')
        ops=validate_plan(self.inv,c)
        self.assertEqual(ops[0].action,'Apagar unidade inteira')
        self.assertIn('Criar e formatar FAT32',[x.action for x in ops])
        self.assertIn('Remover volume existente',[x.action for x in ops])

    def test_erase_shared_lvm_warns(self):
        ops=validate_plan(self.inv,Choices(mode='erase',erase_disk='/dev/sdb'))
        self.assertTrue(any('múltiplos' in x.target for x in ops))

    def test_manual_independent_options(self):
        c=Choices(mode='manual',root='/dev/sda2',efi='/dev/sda1',
                  home='/dev/mapper/volume-home',format_efi=True,format_home=True)
        ops=validate_plan(self.inv,c)
        self.assertIn('Formatar EFI em FAT32',[x.action for x in ops])
        self.assertIn('Formatar /home em ext4',[x.action for x in ops])

    def test_manual_home_dotfiles_disallowed(self):
        c=Choices(mode='manual',root='/dev/sda2',efi='/dev/sda1',clean_dotfiles=True)
        with self.assertRaises(PreviewError):
            validate_plan(self.inv,c)

    def test_bios_without_efi(self):
        inv=demo_inventory()
        inv.firmware='BIOS'
        c=Choices(mode='manual',root='/dev/sda2',bios_disk='/dev/sda')
        ops=validate_plan(inv,c)
        self.assertEqual([x.action for x in ops[:2]], ['Formatar / em ext4','Instalar bootloader BIOS'])

    def test_export_cannot_be_executed(self):
        doc=safe_export(self.base,self.inv,validate_plan(self.inv,self.base))
        self.assertEqual(doc['execution'],'DISABLED')
        self.assertTrue(doc['schema'].startswith('wolf.interface.preview'))
        self.assertNotIn('execute',doc)

    def test_invalid_and_missing(self):
        with self.assertRaises(PreviewError):
            validate_plan(self.inv,Choices(mode='reuse'))
        with self.assertRaises(PreviewError):
            validate_plan(self.inv,Choices(mode='erase',erase_disk='/dev/sdx'))

    def test_very_small_disk(self):
        inv=parse_lsblk(json.dumps({'blockdevices':[{'path':'/dev/sda','type':'disk','size':12*GIB}]}))
        with self.assertRaises(PreviewError):
            validate_plan(inv,Choices(mode='erase',erase_disk='/dev/sda'))

    def test_inventories_arbitrary_paths(self):
        raw={'blockdevices':[{'name':'vda','path':'/dev/vda','type':'disk','size':100*GIB,
                             'children':[{'path':'/dev/vda1','type':'part','size':100*GIB,'fstype':'ext4'}]}]}
        inv=parse_lsblk(json.dumps(raw),firmware='BIOS')
        self.assertEqual(inv.disks[0].path,'/dev/vda')
        self.assertEqual(inv.volumes[0].path,'/dev/vda1')

    def test_malformed_inventory(self):
        with self.assertRaises(PreviewError):
            parse_lsblk('{bad')

    def test_automatic_partition_budget_uefi(self):
        budget = erase_budget(self.inv, '/dev/sda')
        self.assertEqual((budget.disk_gib, budget.boot_gib, budget.margin_gib, budget.usable_gib),
                         (512, 1, 1, 510))
        size = erase_allocation(self.inv, Choices(mode='erase', erase_disk='/dev/sda',
                                                 erase_root_gib=60, erase_home_separate=True))
        self.assertEqual((size.root_gib, size.home_gib, size.unallocated_gib), (60, 450, 0))

    def test_automatic_manual_home_allocation_remainder(self):
        c = Choices(mode='erase', erase_disk='/dev/sda', erase_root_gib=80,
                    erase_home_separate=True, erase_home_gib=150)
        alloc = erase_allocation(self.inv, c)
        self.assertEqual((alloc.root_gib, alloc.home_gib, alloc.unallocated_gib), (80, 150, 280))
        ops = validate_plan(self.inv, c)
        self.assertEqual([op.impact for op in ops if op.target == 'Espaço não alocado'],
                         ['280 GiB permanecerão livres'])
        self.assertEqual([op.impact for op in ops if op.target == 'Nova partição /home'], ['150 GiB'])

    def test_automatic_root_only_allocations(self):
        c = Choices(mode='erase', erase_disk='/dev/sda', erase_root_gib=510)
        alloc = erase_allocation(self.inv, c)
        self.assertEqual((alloc.root_gib, alloc.home_gib, alloc.unallocated_gib), (510, 0, 0))
        c.erase_root_gib = 110
        self.assertEqual(erase_allocation(self.inv, c).unallocated_gib, 400)

    def test_automatic_enforces_limits(self):
        c = Choices(mode='erase', erase_disk='/dev/sda', erase_root_gib=501,
                    erase_home_separate=True)
        with self.assertRaises(PreviewError):
            validate_plan(self.inv, c)
        c.erase_root_gib = 60
        c.erase_home_gib = 451
        with self.assertRaises(PreviewError):
            validate_plan(self.inv, c)
        c.erase_home_gib = 9
        with self.assertRaises(PreviewError):
            validate_plan(self.inv, c)
        c.erase_home_gib = None
        c.erase_home_separate = False
        c.erase_root_gib = 511
        with self.assertRaises(PreviewError):
            validate_plan(self.inv, c)
        c.erase_root_gib = 40
        c.erase_home_gib = 10
        with self.assertRaises(PreviewError):
            validate_plan(self.inv, c)

    def test_automatic_bios_budget(self):
        inv = demo_inventory()
        inv.firmware = 'BIOS'
        budget = erase_budget(inv, '/dev/sda')
        self.assertEqual((budget.boot_gib, budget.margin_gib, budget.usable_gib), (0, 1, 511))
        c = Choices(mode='erase', erase_disk='/dev/sda', erase_root_gib=511)
        self.assertEqual(erase_allocation(inv, c).unallocated_gib, 0)

    def test_exact_small_uefi_and_home_minimum(self):
        inv = parse_lsblk(json.dumps({'blockdevices':[
            {'path':'/dev/sdz', 'type':'disk', 'size':30*GIB}]}), firmware='UEFI')
        b = erase_budget(inv, '/dev/sdz')
        self.assertEqual(b.usable_gib, 28)
        self.assertEqual(erase_allocation(inv, Choices(mode='erase', erase_disk='/dev/sdz',
                        erase_root_gib=28)).unallocated_gib, 0)
        with self.assertRaises(PreviewError):
            erase_allocation(inv, Choices(mode='erase', erase_disk='/dev/sdz',
                             erase_root_gib=25, erase_home_separate=True))

    def test_format_sizes(self):
        self.assertEqual(human_size(1*GIB), '1.0 GiB')


if __name__ == '__main__':
    unittest.main()
