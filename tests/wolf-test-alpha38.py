#!/usr/bin/env python3
"""Alpha38: mapa fstab/lsblk read-only, EFI em disco distinto, LVM em 2 PVs."""
import ast
import json
from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
LIVE = PROJECT / 'live-gui'
source = (LIVE / 'wolf_storage_map.py').read_text()
assert not any(term in source for term in ['subprocess.', 'os.system(', 'mount ', 'mkfs.', 'wipefs ', 'grub-install '])
sys.path.insert(0, str(LIVE))
from wolf_storage_map import build_map, parent_disks, scan_lsblk_json

source_json = json.dumps({'blockdevices': [
    {'path': '/dev/nvme0n1', 'type': 'disk', 'size': 1000, 'children': [
        {'path': '/dev/nvme0n1p1', 'type': 'part', 'uuid': 'EFI-123', 'fstype': 'vfat'},
        {'path': '/dev/nvme0n1p2', 'type': 'part', 'fstype': 'LVM2_member', 'children': [
            {'path': '/dev/mapper/vg_data-lv_home', 'type': 'lvm', 'fstype': 'ext4', 'uuid': 'HOME-123'}]}]},
    {'path': '/dev/nvme1n1', 'type': 'disk', 'size': 500, 'children': [
        {'path': '/dev/nvme1n1p1', 'type': 'part', 'fstype': 'ext4', 'uuid': 'ROOT-123'},
        {'path': '/dev/nvme1n1p2', 'type': 'part', 'fstype': 'LVM2_member', 'children': [
            {'path': '/dev/mapper/vg_data-lv_home', 'type': 'lvm', 'fstype': 'ext4', 'uuid': 'HOME-123'}]}]}
]})
fstab = '''# Comentários com caminhos trocados não devem ser interpretados
# /dev/nvme0n1p1
UUID=ROOT-123 / ext4 rw,relatime 0 1
# /dev/nvme1n1p1
UUID=EFI-123 /boot/efi vfat rw,relatime 0 2
UUID=HOME-123 /home ext4 rw,relatime 0 2
'''
nodes = scan_lsblk_json(source_json)
assert len(nodes) == 7, len(nodes)
assert parent_disks(nodes, '/dev/mapper/vg_data-lv_home') == (
    ['/dev/nvme0n1', '/dev/nvme1n1'], ['/dev/nvme0n1p2', '/dev/nvme1n1p2'])
report, warnings = build_map(fstab, source_json)
assert 'Dispositivo encontrado: /dev/nvme1n1p1' in report
assert 'Dispositivo encontrado: /dev/nvme0n1p1' in report
assert 'TOPOLOGIA MULTIDISCO' in report
assert 'PVs LVM envolvidos: /dev/nvme0n1p2, /dev/nvme1n1p2' in report
assert 'Instalação física somente pelo executor específico' in report
assert len(warnings) == 2, warnings
unknown, warnings = build_map('UUID=DESCONHECIDO / ext4 defaults 0 1', source_json)
assert 'NÃO CONFIRMADA' in unknown and warnings
malicious, warnings = build_map('UUID=ROOT-123;rm / ext4 defaults 0 1', source_json)
assert 'NÃO CONFIRMADA' in malicious
for f in ('main.py', 'wolf_rescue.py'):
    ast.parse((LIVE/f).read_text())
rescue = (LIVE/'wolf_rescue.py').read_text()
assert "app.setStyle('Fusion')" in rescue
assert 'QTabWidget' in rescue and "setObjectName('warning')" in rescue
assert 'background: #11151d' in rescue and 'background: #0a1019' in rescue
assert 'build_map(' in rescue and 'read_fstab(' in rescue
main = (LIVE/'main.py').read_text()
assert 'ScrollBarAlwaysOff' in main and 'AdjustToMinimumContentsLengthWithIcon' in main
assert 'self.setMinimumSize(680, 490)' in main
assert 'VERSION = "1.8"' in main or 'VERSION = "1.9"' in main or 'VERSION = "2.0"' in main or 'VERSION = "2.1"' in main
stage = (PROJECT/'tests/wolf-stage-live-desktop.sh').read_text()
assert '"$SOURCE/wolf_storage_map.py"' in stage
print('[OK] Alpha38: dark, largura responsiva, fstab por UUID, LVM multidisco, aviso físico atualizado')
