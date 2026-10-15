#!/usr/bin/env python3
"""Alpha49: testes não destrutivos da seleção /home e revisão de interface."""
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch
import runpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'live-gui'))
import wolf_home_cleanup as hc
import wolf_discovery as wd
import wolf_physical_executor as phy

assert hc.validate_spec(None) == {'items': [], 'backup': False}
assert hc.validate_spec({'items':['.config','.local/share/Steam'], 'backup': False})['items'] == ['.config', '.local/share/Steam']
for bad in [{'items':['../Documents'], 'backup':False},
            {'items':['.local'], 'backup':False},
            {'items':['/home/wolf/.ssh'], 'backup': False},
            {'items':['.local/share/../Steam'], 'backup':False},
            {'items':['.config', '.config'], 'backup':False},
            {'items':['.cache'], 'backup':'no'},
            {'items':[], 'backup':True},
            {'items':['.config'], 'backup':False, 'format_home':True}]:
    try: hc.validate_spec(bad)
    except hc.CleanupDenied: pass
    else: raise AssertionError('Aceitou seleção insegura: ' + str(bad))

with tempfile.TemporaryDirectory(prefix='wolf49-cleanup-test-') as tmp:
    base = Path(tmp)
    user = base / 'wolf'; user.mkdir()
    (user / 'Documentos').mkdir(); (user / 'Documentos' / 'importante.txt').write_text('ficar')
    (user / '.config').mkdir(); (user / '.config' / 'old.conf').write_text('antigo')
    (user / '.cache').mkdir(); (user / '.cache' / 'temp.cache').write_text('cache')
    (user / '.ssh').mkdir(); (user / '.ssh' / 'id_ed25519').write_text('chave')
    (user / '.local' / 'share' / 'Steam').mkdir(parents=True)
    (user / '.local' / 'share' / 'Steam' / 'game.bin').write_text('JOGO')
    (user / '.local' / 'share' / 'other').mkdir()
    (user / '.local' / 'share' / 'other' / 'x').write_text('other')
    (user / '.mozilla').symlink_to(user / 'Documentos', target_is_directory=True)
    paths = {v['path'] for v in hc.candidate_info(base,'wolf')}
    assert '.config' in paths and '.cache' in paths
    assert '.local/share/Steam' in paths and '.local/share/other' in paths
    assert '.local' not in paths and '.mozilla' not in paths
    with patch.object(hc, '_mount_guard'), patch.object(hc, '_no_nested_mounts'):
        count, backup = hc.perform(base, '/dev/fake', 'wolf', {'items':['.config'], 'backup':False})
        assert count == 1 and not backup
        assert not (user / '.config').exists()
        assert (user / '.local' / 'share' / 'Steam' / 'game.bin').read_text() == 'JOGO'
        assert (user / '.ssh' / 'id_ed25519').exists()
        assert (user / 'Documentos' / 'importante.txt').exists()
        count, backup = hc.perform(base, '/dev/fake','wolf', {'items':['.cache'], 'backup':True})
        assert count == 1 and backup
        assert Path(backup,'wolf','.cache','temp.cache').read_text() == 'cache'
        assert not (user / '.cache').exists()
        assert (user / '.local' / 'share' / 'Steam' / 'game.bin').exists()

fixture = runpy.run_path(str(ROOT/'tests/wolf-test-alpha39.py'))
raw = json.loads(fixture['lsblk'])
for disk in raw['blockdevices']:
    for part in disk.get('children', []):
        if part.get('path') == '/dev/nvme1n1p1':
            part['parttype'] = '0fc63daf-8483-4772-8e79-3d69d8477de4'
snap = wd.discover(raw=json.dumps(raw),fstab_by_root={'/dev/nvme1n1p1':fixture['FSTAB']},boot_mode='UEFI')
plan = fixture['make'](snap)
plan['home_cleanup'] = {'items':['.cache','.config'], 'backup':False}
assert wd.validate_plan(plan,snap) == plan
assert 'Backup dos itens: NÃO' in wd.render_plan(plan)
with patch.object(phy.Path,'is_dir',return_value=True):
    assert len(phy.export_fields(plan,snap)) == 12
bad = dict(plan); bad['home_cleanup'] = {'items':['../../windows'],'backup':False}
try: wd.validate_plan(bad,snap)
except (wd.DiscoveryError, hc.CleanupDenied): pass
else: raise AssertionError('Backend aceitou limpeza perigosa')

bash = (ROOT/'install/wolf-install.sh').read_text()
ui = (ROOT/'live-gui/main.py').read_text()
staging = (ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
assert 'confirm_preserved_home_cleanup' in bash
assert "'LIMPAR SELECIONADOS'" in bash
assert 'PHYSICAL_PLAN_SHA256' in bash
assert 'revalidate_gui_physical_target\n        mkfs.ext4 -F "$ROOT_DEVICE"' in bash
assert '"$PROJECT_DIR/live-gui/wolf_home_cleanup.py" apply' in bash
assert 'os.environ.get(\'WOLF_SHOW_VM_LAB\')' in ui
assert "self.storage_mode.addItem(\"Reutilizar instalação existente" in ui
assert 'self.home_cleanup_button' in ui and 'self.home_cleanup_spec' in ui
assert '"$SOURCE/wolf_home_cleanup.py"' in staging
assert (ROOT/'VERSION').read_text().strip() in ('2.0.0-alpha49', '2.0.0-alpha50', '2.0.0-alpha51', '2.0.0-alpha52', '2.0.0-alpha53', '2.0.0-alpha54', '2.0.0-alpha55', '2.0.0-alpha56', '2.0.0-alpha57', '2.0.0-alpha58', '2.0.0-alpha59', '2.0.0', '2.1.0-rc1', '2.1.0')
print('[OK] alpha49: seleção estrita, backup opcional, Steam/SSH preservados por padrão')
print('[OK] alpha49: simulação de limpeza + backup, sem acesso a dispositivos físicos')
print('[OK] alpha49: contrato físico, validação SHA, PTY/EFI/LVM preservados, interface simplificada')
