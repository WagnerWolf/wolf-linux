#!/usr/bin/env python3
"""Wolf alpha43 regression: user ID preservation + read-only physical preflight."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
def module(path, name):
    spec = importlib.util.spec_from_loader(name, SourceFileLoader(name, str(path)))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

ident = module(ROOT/'live-gui/wolf_home_identity.py', 'wolf_home_identity')
phys = module(ROOT/'live-gui/wolf-physical-preflight', 'wolf_physical_preflight')

def fake_uid(target, uid, gid):
    original = Path.lstat
    def override(p, *args, **kwargs):
        real = original(p, *args, **kwargs)
        if p == target:
            fields = list(real)
            fields[4] = uid; fields[5] = gid
            return os.stat_result(fields)
        return real
    return patch.object(Path, 'lstat', override)

with TemporaryDirectory(prefix='wolf43-test-') as tmp:
    root=Path(tmp); (root/'home').mkdir(); (root/'etc').mkdir()
    target=root/'home/wolf'; target.mkdir()
    (root/'etc/passwd').write_text('root:x:0:0:root:/root:/bin/bash\n')
    # O mock de Path.lstat existe somente neste processo. Um subprocesso
    # enxerga a propriedade REAL do diretório temporário, que pode ser do
    # usuário comum que constrói a ISO (ex.: wolf/1000), não de root.
    with fake_uid(target, 1004, 1005):
        assert ident.inspect(root,'wolf') == ('reuse-uid','1004','1005','1004')
    actual_fields = ident.inspect(root, 'wolf')
    raw = subprocess.run(
        [sys.executable, str(ROOT/'live-gui/wolf_home_identity.py'),
         'inspect', '--root', str(root), '--user', 'wolf'],
        capture_output=True,
    )
    assert raw.returncode == 0, raw.stderr.decode(errors='replace')
    assert raw.stdout == b''.join(field.encode('utf-8') + b'\0' for field in actual_fields), (
        raw.stdout, actual_fields
    )
    with fake_uid(target,0,0):
        assert ident.inspect(root,'wolf')[0] == 'root-owned'
    (root/'etc/passwd').write_text('root:x:0:0:root:/root:/bin/bash\nother:x:1004:1004::/home/other:/bin/bash\n')
    with fake_uid(target,1004,1005):
        try: ident.inspect(root,'wolf')
        except ident.IdentityDenied: pass
        else: raise AssertionError('Conflito UID não bloqueado')
    (root/'etc/passwd').write_text('root:x:0:0:root:/root:/bin/bash\nwolf:x:1003:1003::/home/wolf:/bin/bash\n')
    with fake_uid(target,1004,1005):
        assert ident.inspect(root,'wolf') == ('existing','1004','1005','1003')
    target.rmdir(); target.symlink_to(root/'etc', target_is_directory=True)
    try: ident.inspect(root,'wolf')
    except ident.IdentityDenied: pass
    else: raise AssertionError('Symlink no diretório pessoal foi aceito')

fixture={'blockdevices':[
    {'path':'/dev/sda','type':'disk','size':32*1024**3,'rm':True,'tran':'usb',
        'children':[{'type':'part','fstype':'exfat','mountpoints':['/run/archiso/bootmnt']}]},
    {'path':'/dev/nvme0n1','type':'disk','size':1000*1024**3,'rm':False,'tran':'nvme',
        'children':[{'type':'part','fstype':'vfat'},{'type':'part','fstype':'LVM2_member','children':[{'type':'lvm','fstype':'ext4'}]}]},
    {'path':'/dev/nvme1n1','type':'disk','size':500*1024**3,'rm':False,'tran':'nvme',
        'children':[{'type':'part','fstype':'ext4'},{'type':'part','fstype':'ntfs'}]},
    {'path':'/dev/sdb','type':'disk','size':100*1024**3,'rm':False,'ro':False,'tran':'sata','children':[]},
]}
for disk in fixture['blockdevices'][:3]:
    assert phys.classify(disk)[0] == 'PROTEGER'
assert phys.classify(fixture['blockdevices'][3])[0] == 'INSPECIONAR MANUALMENTE'
report=phys.render(fixture)
assert 'NÃO LIBERA INSTALAÇÃO' in report and '/dev/nvme0n1' in report
with TemporaryDirectory() as tmp:
    p=Path(tmp)/'lsblk.json';p.write_text(json.dumps(fixture))
    result=subprocess.run([sys.executable,str(ROOT/'live-gui/wolf-physical-preflight'),'--input-json',str(p)],capture_output=True,text=True)
    assert result.returncode == 0 and 'PROTEGER' in result.stdout

src=(ROOT/'install/wolf-install.sh').read_text()
assert 'preflight_preserved_home_identity' in src
assert 'reconcile_preserved_home_access' in src
assert 'create_args+=(-u "$PRESERVED_HOME_DESIRED_UID")' in src
assert 'chown --no-dereference "$uid" "$dir"' in src
assert 'AJUSTAR /home/' in src
assert 'arch-chroot /mnt runuser -u "$USERNAME_VALUE"' in src
assert '\n    chown -R ' not in src[src.index('preflight_preserved_home_identity()'):src.index('enable_one_service()')]
staging=(ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
assert 'wolf_home_identity.py' in staging and 'wolf-physical-preflight' in staging
main=(ROOT/'live-gui/main.py').read_text()
assert "'--preflight-multidisk-physical'" in main
assert 'wolf-physical-preflight' not in main  # botão piloto antigo saiu da GUI
assert (ROOT/'VERSION').read_text().strip() in ('2.0.0-alpha44', '2.0.0-alpha45', '2.0.0-alpha46', '2.0.0-alpha47', '2.0.0-alpha48', '2.0.0-alpha49', '2.0.0-alpha50', '2.0.0-alpha51', '2.0.0-alpha52', '2.0.0-alpha53', '2.0.0-alpha54', '2.0.0-alpha55', '2.0.0-alpha56', '2.0.0-alpha57', '2.0.0-alpha58', '2.0.0-alpha59', '2.0.0', '2.1.0-rc1', '2.1.0', '2.1.1-rc1', '2.1.1-rc2', '2.1.1', '2.1.2-rc1', '2.1.2')
print('[OK] alpha43: UID preservado quando livre, colisões e links bloqueados')
print('[OK] alpha43: escrita verificada e correção limitada ao diretório pessoal')
print('[OK] alpha43: diagnóstico físico somente leitura, sem liberação de instalação')
