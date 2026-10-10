#!/usr/bin/env python3
"""Executor gate for the two disposable alpha41 QEMU disks. Never supports real disks.

The multidisk preview JSON stays execution=disabled. A separate VM-lab-only
command revalidates the complete document before exporting fields to Bash.
"""
import os
from pathlib import Path
import subprocess
import sys

import wolf_discovery as discovery

EXPECTED = {
    'efi': ('WOLF41EFI', 64 * 1024**3, '/dev/vda'),
    'root': ('WOLF41ROOT', 96 * 1024**3, '/dev/vdb'),
}

class LabDenied(ValueError):
    pass


def run(*args):
    p = subprocess.run(list(args), capture_output=True, text=True, timeout=15)
    if p.returncode:
        raise LabDenied(f'Comando de verificação falhou: {args[0]}: {p.stderr[:150]}')
    return p.stdout.strip()


def lab_devices(doc, *, links=None, inventory=None, virtual=None, in_live=None,
                firmware=None, mounted=None):
    """Pure structural gate, with injected observations for offline tests."""
    if virtual not in ('qemu', 'kvm') or not in_live or firmware != 'UEFI':
        raise LabDenied('Executor alpha42 APENAS QEMU/KVM + Live Archiso + UEFI')
    if not isinstance(links, dict) or not isinstance(inventory, dict):
        raise LabDenied('Identidades dos discos não disponíveis')
    for role, (serial, size, disk) in EXPECTED.items():
        x = links.get(role)
        v = inventory.get(disk, {})
        if x != disk or v.get('serial') != serial or v.get('bytes') != size or \
                v.get('type') != 'disk' or v.get('rm') != '0' or v.get('ro') != '0':
            raise LabDenied(f'Disco laboratório {role} não corresponde ao serial/capacidade esperados')
    roles = doc.get('roles', {})
    if not isinstance(roles, dict):
        raise LabDenied('Papéis inválidos')
    root, esp, home = (roles.get(k) for k in ('root', 'esp', 'home'))
    if not all(isinstance(x, dict) for x in (root, esp, home)):
        raise LabDenied('A raiz, a EFI e a /home LVM são obrigatórias no laboratório')
    if (root.get('path'), esp.get('path'), home.get('path')) != \
        ('/dev/vdb1', '/dev/vda1', '/dev/mapper/vg_monstro-lv_projetos'):
        raise LabDenied('Papéis diferentes do laboratório preparado')
    if (root.get('parent_disks'), esp.get('parent_disks'), home.get('parent_disks')) != \
       (['/dev/vdb'], ['/dev/vda'], ['/dev/vda', '/dev/vdb']):
        raise LabDenied('Discos pais alterados')
    if sorted(home.get('lvm_pvs') or []) != ['/dev/vda2', '/dev/vdb3']:
        raise LabDenied('PVs LVM diferentes do laboratório')
    if root.get('type') != 'part' or esp.get('type') != 'part' or home.get('type') != 'lvm':
        raise LabDenied('Tipos dos dispositivos incorretos')
    if doc.get('boot_mode') != 'UEFI' or doc.get('actions') != \
            {'root': 'format_ext4', 'esp': 'preserve', 'home': 'preserve'}:
        raise LabDenied('Ações não autorizadas')
    if doc.get('acknowledge_override') is True:
        raise LabDenied('Laboratório não executa substituições divergentes do fstab')
    if mounted:
        raise LabDenied('Um dispositivo protegido ou /mnt está montado; não executar')
    return root, esp, home


def physical_checks():
    if os.geteuid() != 0:
        raise LabDenied('Preflight/execução exige root')
    virt = run('systemd-detect-virt', '--vm')
    in_live = Path('/run/archiso/airootfs').is_dir()
    firmware = 'UEFI' if Path('/sys/firmware/efi').is_dir() else 'BIOS'
    links = {}
    inventory = {}
    for role, (serial, _size, disk) in EXPECTED.items():
        p = Path('/dev/disk/by-id/virtio-' + serial)
        links[role] = str(p.resolve()) if p.is_symlink() else None
        if links[role] != disk:
            continue
        a = run('lsblk', '-dnro', 'SERIAL,TYPE,RM,RO', disk).split()
        size = int(run('blockdev', '--getsize64', disk))
        if len(a) == 4:
            inventory[disk] = dict(serial=a[0], type=a[1], rm=a[2], ro=a[3], bytes=size)
    mounted = Path('/mnt').is_mount()
    # mountpoints for every protected device; no automatic unmount or activation
    for source in ('/dev/vdb1', '/dev/vda1', '/dev/vda2', '/dev/vdb3',
                   '/dev/mapper/vg_monstro-lv_projetos', '/dev/vdb2'):
        result = subprocess.run(['findmnt', '-rn', '--source', source], capture_output=True, text=True)
        mounted |= (result.returncode == 0 and bool(result.stdout.strip()))
    for part, label in (('/dev/vda1', 'WOLF41_ESP'), ('/dev/vda2', 'WOLF41_PV_A'),
                        ('/dev/vdb1', 'WOLF41_ROOT'), ('/dev/vdb2', 'WOLF41_TEST_KEEP'),
                        ('/dev/vdb3', 'WOLF41_PV_B')):
        if run('lsblk', '-dnro', 'PARTLABEL', part) != label:
            raise LabDenied(f'Partição {part} não pertence ao laboratório')
    # require uniquely identified cross-disk LVM and the lab NTFS test partition
    if run('lsblk', '-dnro', 'FSTYPE', '/dev/vdb2') != 'ntfs':
        raise LabDenied('Partição NTFS de preservação do laboratório ausente')
    if run('lvs', '--readonly', '--noheadings', '-o', 'lv_name', 'vg_monstro').strip() != 'lv_projetos':
        raise LabDenied('LV de teste inesperado')
    return dict(links=links, inventory=inventory, virtual=virt, in_live=in_live,
                firmware=firmware, mounted=mounted)


def verify(path):
    doc = discovery._load_plan(path)
    obs = physical_checks()  # do this BEFORE any attempt to mount or revalidate candidate
    lab_devices(doc, **obs)
    discovery.validate_plan(doc, discovery.discover())
    return doc


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('check', 'export'):
        print('Uso: wolf_lab42.py check|export plano.json', file=sys.stderr)
        return 2
    try:
        doc = verify(sys.argv[2])
        if sys.argv[1] == 'check':
            print('WOLF LAB42: preflight aprovado: apenas /dev/vdb1 será formatada.')
            print('PRESERVAR: /dev/vda1, /dev/vdb2, /dev/vda2, /dev/vdb3 e LV /home.')
        else:
            fields = [doc['roles'][r]['path'] for r in ('root','esp','home')]
            fields += [doc['roles'][r]['uuid'] for r in ('root','esp','home')]
            fields += [doc['identity']['hostname'], doc['identity']['username'],
                       doc['software']['preset'], ','.join(doc['software']['stacks']),
                       doc['keyboard']['layout'], doc['keyboard']['variant']]
            sys.stdout.buffer.write(b'\x00'.join(x.encode() for x in fields) + b'\x00')
        return 0
    except (LabDenied, discovery.DiscoveryError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as exc:
        print('[BLOQUEADO ALPHA42] ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
