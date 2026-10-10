#!/usr/bin/env python3
"""Testa detecção multidisco/LVM sem operações de disco."""
import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'live-gui'))
import wolf_discovery as wd
from wolf_plan import PRESETS

ROOT_UUID='141fe15b-3552-4e61-a6e6-f46b868cb151'
ESP_UUID='61DC-145A'
HOME_UUID='2f62b284-146a-48b7-8c6d-3d09334fcbc4'
DEVICE_HOME='/dev/mapper/vg_monstro-lv_projetos'
FSTAB=f'''# Os comentários não identificam a partição real
UUID={ROOT_UUID} / ext4 rw,relatime 0 1
UUID={ESP_UUID} /boot/efi vfat rw,relatime 0 2
UUID={HOME_UUID} /home ext4 rw,relatime 0 2
'''

lsblk=json.dumps({'blockdevices':[
 {'path':'/dev/sda','type':'disk','tran':'usb','rm':1,'size':31*1024**3,
  'children':[{'path':'/dev/sda1','type':'part','fstype':'exfat','size':30*1024**3}]},
 {'path':'/dev/nvme0n1','type':'disk','tran':'nvme','size':931*1024**3,'rm':0,'children':[
   {'path':'/dev/nvme0n1p1','type':'part','size':1024**3,'fstype':'vfat','uuid':ESP_UUID,'parttype':'c12a7328-f81f-11d2-ba4b-00a0c93ec93b','maj:min':'259:1'},
   {'path':'/dev/nvme0n1p2','type':'part','size':930*1024**3,'fstype':'LVM2_member','uuid':'pva','maj:min':'259:2',
      'children':[{'path':DEVICE_HOME,'type':'lvm','fstype':'ext4','uuid':HOME_UUID,
      'size':1156*1024**3,'maj:min':'253:0'}]}]},
 {'path':'/dev/nvme1n1','type':'disk','tran':'nvme','size':465*1024**3,'rm':0,'children':[
   {'path':'/dev/nvme1n1p1','type':'part','fstype':'ext4','uuid':ROOT_UUID,'size':100*1024**3,'maj:min':'259:3'},
   {'path':'/dev/nvme1n1p2','type':'part','fstype':'ntfs','uuid':'windows','size':139*1024**3},
   {'path':'/dev/nvme1n1p6','type':'part','fstype':'LVM2_member','uuid':'pvb','size':226*1024**3,
    'children':[{'path':DEVICE_HOME,'type':'lvm','fstype':'ext4','uuid':HOME_UUID,
      'size':1156*1024**3,'maj:min':'253:0'}]}]}
]})


def fails(callable_, label):
    try:
        callable_()
    except wd.DiscoveryError:
        return
    raise AssertionError('Deveria recusar: '+label)


def make(snapshot, **kwargs):
    args=dict(root='/dev/nvme1n1p1', esp='/dev/nvme0n1p1', home=DEVICE_HOME,
              confirmed=True, acknowledge_override=False,
              username='wolf', hostname='wolf-linux', preset='minimal', stacks=PRESETS['minimal'],
              keyboard={'layout':'br','model':'abnt2','variant':''})
    args.update(kwargs)
    return wd.build_plan(snapshot, **args)


def main():
    snap=wd.discover(raw=lsblk, fstab_by_root={'/dev/nvme1n1p1':FSTAB}, boot_mode='UEFI')
    assert snap['execution']=='disabled'
    assert len(snap['candidates']) == 1, snap['candidates']
    cand=snap['candidates'][0]
    assert cand['suggestions']=={'root':'/dev/nvme1n1p1','esp':'/dev/nvme0n1p1','home':DEVICE_HOME}
    plan=make(snap)
    assert wd.validate_plan(plan,snap)==plan
    assert plan['roles']['esp']['parent_disks']==['/dev/nvme0n1']
    assert sorted(plan['roles']['home']['parent_disks'])==['/dev/nvme0n1','/dev/nvme1n1']
    assert len(plan['roles']['home']['lvm_pvs'])==2
    assert plan['actions']=={'root':'format_ext4','esp':'preserve','home':'preserve'}
    assert 'SIMULAÇÃO' in wd.render_plan(plan,simulated=True)
    fails(lambda: make(snap,confirmed=False),'sem confirmação')
    fails(lambda: make(snap,esp=None),'UEFI sem EFI')
    fails(lambda: make(snap,home='/dev/nvme1n1p2'),'NTFS não é home')
    fails(lambda: make(snap,home='/dev/nvme1n1p1'),'reusar raiz no mesmo papel')
    fails(lambda: make(snap,esp='/dev/sda1'),'USB não é EFI')
    fails(lambda: make(snap,home=None),'mudança fstab não autorizada')
    override=make(snap,home=None,acknowledge_override=True)
    assert wd.validate_plan(override,snap)==override
    bad=copy.deepcopy(plan);bad['execution']='enabled'
    fails(lambda:wd.validate_plan(bad,snap),'execução habilitada')
    bad=copy.deepcopy(plan);bad['actions']['esp']='format_vfat'
    fails(lambda:wd.validate_plan(bad,snap),'formatar EFI')
    bad=copy.deepcopy(plan);bad['roles']['home']['uuid']='outro'
    fails(lambda:wd.validate_plan(bad,snap),'adulterar LV')
    changed=wd.discover(raw=lsblk, fstab_by_root={'/dev/nvme1n1p1':FSTAB+'#modificacao\n'},boot_mode='UEFI')
    fails(lambda:wd.validate_plan(plan,changed),'fstab diferente')
    other=wd.discover(raw=lsblk.replace(ROOT_UUID,'other-root'),
       fstab_by_root={'/dev/nvme1n1p1':FSTAB},boot_mode='UEFI')
    assert not other['candidates']
    # BIOS não exige ESP; mas não é permitido carregar ESP no plano BIOS.
    bios=wd.discover(raw=lsblk,fstab_by_root={'/dev/nvme1n1p1':FSTAB},boot_mode='BIOS')
    fails(lambda:make(bios),'BIOS com EFI')
    assert wd.validate_plan(make(bios,esp=None,acknowledge_override=True),bios)
    # Nenhum filesystem foi montado ou alterado nos testes de fixtures.
    print('[OK] alpha39: detecção UUID em SSDs distintos + LVM multipv')
    print('[OK] alpha39: contrato, confirmações, BIOS/UEFI, adulteração e fstab mutável')

if __name__=='__main__':
    main()
