#!/usr/bin/env python3
"""Alpha45: inspeção ext4 sem journal replay, formatação, fsck ou escrita."""
from __future__ import annotations
import json
from pathlib import Path
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'live-gui'))
import wolf_discovery as wd

ROOT_PATH = '/dev/vdb1'
ROOT_UUID = '25b65327-0cbf-4d61-8068-7fdf0d5bd4a5'
ESP_UUID = 'E568-637F'
HOME_UUID = '57797855-6b14-4be6-b955-12d2b273fc41'

LSBLK = json.dumps({'blockdevices': [
    {'path':'/dev/vda', 'type':'disk', 'size':64*1024**3, 'children':[
      {'path':'/dev/vda1','type':'part','fstype':'vfat','uuid':ESP_UUID,
       'size':1024**3,'parttype':'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'},
      {'path':'/dev/vda2','type':'part','fstype':'LVM2_member','size':63*1024**3,
       'children':[{'path':'/dev/mapper/vg_monstro-lv_projetos','type':'lvm',
       'fstype':'ext4','uuid':HOME_UUID,'size':111*1024**3}]}]},
    {'path':'/dev/vdb', 'type':'disk', 'size':96*1024**3, 'children':[
      {'path':ROOT_PATH, 'type':'part', 'fstype':'ext4','size':40*1024**3,
       'uuid':ROOT_UUID,'partuuid':'test-root'},
      {'path':'/dev/vdb2','type':'part','fstype':'ntfs','size':8*1024**3},
      {'path':'/dev/vdb3','type':'part','fstype':'LVM2_member','size':48*1024**3,
       'children':[{'path':'/dev/mapper/vg_monstro-lv_projetos','type':'lvm',
       'fstype':'ext4','uuid':HOME_UUID,'size':111*1024**3}]}]},
]})
FSTAB = (f'UUID={ROOT_UUID} / ext4 rw 0 1\n'
         f'UUID={ESP_UUID} /boot/efi vfat defaults 0 2\n'
         f'UUID={HOME_UUID} /home ext4 defaults 0 2\n')

REPORT = '''tune2fs 1.47.4
Filesystem UUID: 25b65327-0cbf-4d61-8068-7fdf0d5bd4a5
Filesystem state: clean
Filesystem features: has_journal ext_attr orphan_file extent needs_recovery metadata_csum orphan_present
'''

health = wd.parse_ext4_health(REPORT)
assert health['pending'] == ['needs_recovery','orphan_present']
assert health['state'] == 'clean'
assert 'orphan_file' not in health['pending']  # feature suportada ≠ recuperação pendente
assert wd.parse_ext4_health(REPORT.replace('needs_recovery', '').replace('orphan_present', ''))['pending'] == []
assert wd.parse_ext4_health('Filesystem features: has_journal\nFilesystem state: clean\n')['pending'] == []

# O scanner jamais executa e2fsck / mkfs. Em caso de flags presentes,
# deve REJEITAR a montagem e emitir diagnóstico detalhado.
class BlockStats:
    st_mode = stat.S_IFBLK | 0o600

calls = []
def fake_run(argv, **kwargs):
    calls.append(list(argv))
    if argv[0] == 'tune2fs':
        return subprocess.CompletedProcess(argv, 0, REPORT, '')
    raise AssertionError('Com recuperação pendente, nem mount nem fsck devem ser chamados!')

with patch.object(wd.os, 'geteuid', return_value=0), \
     patch.object(wd.os, 'stat', return_value=BlockStats()), \
     patch.object(wd.subprocess, 'run', side_effect=fake_run):
    try:
        wd._read_candidate_root(ROOT_PATH, {'mountpoints': []})
    except wd.DiscoveryError as exc:
        msg = str(exc)
        assert all(word in msg for word in ('EXT4 COM RECUPERAÇÃO PENDENTE','needs_recovery',
                                           'orphan_present', ROOT_PATH, 'e2fsck -f -n'))
    else:
        raise AssertionError('Deveria recusar ext4 com journal pendente')
assert calls == [['tune2fs','-l',ROOT_PATH]]

# Se o mount readonly falhar SEM flags de recuperação, não silenciar a falha.
with TemporaryDirectory() as temp:
    class TempCtx:
        def __enter__(self): return temp
        def __exit__(self, *args): return False
    def failed_mount(argv, **kwargs):
        if argv[0] == 'tune2fs':
            return subprocess.CompletedProcess(argv, 0, REPORT.replace('needs_recovery','').replace('orphan_present',''), '')
        if argv[0] == 'mount':
            assert 'ro,noload,nosuid,nodev,noexec' in argv
            return subprocess.CompletedProcess(argv, 32, '', 'cannot read superblock')
        raise AssertionError('Comando inesperado '+str(argv))
    with patch.object(wd.os, 'geteuid', return_value=0), \
         patch.object(wd.os, 'stat', return_value=BlockStats()), \
         patch.object(wd.tempfile, 'TemporaryDirectory', return_value=TempCtx()), \
         patch.object(wd.subprocess, 'run', side_effect=failed_mount):
        try:
            wd._read_candidate_root(ROOT_PATH, {'mountpoints': []})
        except wd.DiscoveryError as exc:
            assert 'cannot read superblock' in str(exc)
            assert 'e2fsck -f -n' in str(exc)
        else:
            raise AssertionError('Mount falhado não deve ser silencioso')

# Descoberta sem FSTAB não deve aceitar candidatos; erros de ext4 chegam à GUI.
with patch.object(wd, '_read_candidate_root', side_effect=wd.DiscoveryError('EXT4 COM RECUPERAÇÃO PENDENTE (needs_recovery)')):
    snapshot = wd.discover(raw=LSBLK, boot_mode='UEFI')
    assert not snapshot['candidates']
    assert snapshot['errors'] and 'needs_recovery' in snapshot['errors'][0]
    assert snapshot['execution'] == 'disabled'

healthy = wd.discover(raw=LSBLK, fstab_by_root={ROOT_PATH: FSTAB}, boot_mode='UEFI')
assert len(healthy['candidates']) == 1
assert healthy['candidates'][0]['root'] == ROOT_PATH
assert healthy['candidates'][0]['suggestions']['esp'] == '/dev/vda1'
assert healthy['candidates'][0]['suggestions']['home'] == '/dev/mapper/vg_monstro-lv_projetos'

ui = (ROOT / 'live-gui/main.py').read_text()
assert 'self.md_diagnostics = QPlainTextEdit()' in ui
assert 'self.md_diagnostics.setPlainText(' in ui
assert 'Nenhum bloqueio de leitura ext4 detectado' in ui
assert "shellcheck disable=SC2016" in (ROOT / 'install/wolf-install.sh').read_text()
assert (ROOT / 'VERSION').read_text().strip() in ('2.0.0-alpha45', '2.0.0-alpha46', '2.0.0-alpha47', '2.0.0-alpha48', '2.0.0-alpha49', '2.0.0-alpha50', '2.0.0-alpha51', '2.0.0-alpha52', '2.0.0-alpha53', '2.0.0-alpha54', '2.0.0-alpha55', '2.0.0-alpha56', '2.0.0-alpha57', '2.0.0-alpha58', '2.0.0-alpha59', '2.0.0')

print('[OK] alpha45: flags needs_recovery/orphan_present identificadas, sem mount ou fsck')
print('[OK] alpha45: erro de montagem ro,noload explícito; inventário e GUI recebem diagnóstico')
print('[OK] alpha45: root íntegra segue elegível, EFI cross-disk e /home multi-PV preservadas')
