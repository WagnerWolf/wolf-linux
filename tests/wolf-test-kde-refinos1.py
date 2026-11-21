#!/usr/bin/env python3
"""Wolf KDE 2.3.0 Refinos1: testes isolados, sem discos, internet ou pacman."""
from pathlib import Path
import ast
import json
import runpy
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
install = (ROOT/'install/wolf-install.sh').read_text(encoding='utf-8')
prefs = (ROOT/'tests/wolf-configure-user-defaults.py').read_text(encoding='utf-8')
assert (ROOT/'VERSION').read_text().strip() == '2.3.1'
assert 'stage "69c3a-helpers-kde" install_wolf_kde_refinement_helpers' in install
assert 'install -m 0755 "$kde_tools/wolf-format-removable" /mnt/usr/local/bin/wolf-format-removable' in install
assert 'install -m 0755 "$kde_tools/wolf-open-vscode-kde" /mnt/usr/local/bin/wolf-open-vscode-kde' in install
assert 'options nvidia_modeset opportunistic_flip_sync=0' in install
assert 'if [[ "$wolf_nvidia_driver_version" == 620.* ]]; then' in install
assert 'arch-chroot /mnt mkinitcpio -P' in install
assert install.index('options nvidia_modeset opportunistic_flip_sync=0') < install.index('stage "69b2-validar-nvidia-dkms"')
assert '/mnt/etc/modprobe.d/90-wolf-nvidia-wayland-multimonitor.conf' in install
assert 'options nvidia_drm modeset=1' in install
assert 'Session=plasma.desktop' in install
assert 'DisplayServer=wayland' not in install
assert 'PointerAccelerationProfile", "1")' in prefs
assert '"source": "/usr/share/wolf-linux/fastfetch/wolf-tux-tty.txt"' in prefs
assert 'fastfetch-wolf-tux-tty.txt' in install
for target in ['install/wolf-install.sh','gerar-iso.sh']:
    assert subprocess.run(['bash','-n',str(ROOT/target)],capture_output=True).returncode == 0
for target in ['tests/wolf-configure-user-defaults.py','tools/kde/wolf-open-vscode-kde','tools/kde/wolf-format-removable']:
    ast.parse((ROOT/target).read_text(encoding='utf-8'))
    assert (ROOT/target).is_file()

fn = runpy.run_path(str(ROOT/'tests/wolf-configure-user-defaults.py'))
configure = fn['configure']
with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp)
    (root/'etc').mkdir(); (root/'etc/passwd').write_text('wolf:x:1000:1000:Wolf:/home/wolf:/bin/zsh\n')
    home=root/'home/wolf'; home.mkdir(parents=True)
    app=root/'usr/share/applications';app.mkdir(parents=True)
    app.joinpath('thorium-browser-avx2.desktop').write_text('''[Desktop Entry]
Type=Application
Name=Thorium
Exec=thorium-browser-avx2 %U
StartupWMClass=thorium
[Desktop Action NewWindow]
Name=Nova janela
Exec=thorium-browser-avx2 --new-window
''')
    configure(root, 'wolf', ROOT/'assets', True, True)
    desktop=home/'.local/share/applications/thorium-browser-avx2.desktop'
    rendered=desktop.read_text()
    assert rendered.count('StartupWMClass=Thorium-browser') == 1
    assert 'StartupWMClass=thorium\n' not in rendered
    assert '[Desktop Action NewWindow]' in rendered
    assert 'Exec=thorium-browser-avx2 --new-window' in rendered
    tty=json.loads((home/'.config/fastfetch/config-tty.jsonc').read_text())
    assert tty['logo']['source'] == '/usr/share/wolf-linux/fastfetch/wolf-tux-tty.txt'
    assert '/usr/share/wolf-linux/fastfetch/wolf-linux.txt' in (home/'.config/fastfetch/config.jsonc').read_text()
    assert '[Mouse]\n' in (home/'.config/kcminputrc').read_text()
    assert 'PointerAccelerationProfile=1' in (home/'.config/kcminputrc').read_text()
    assert 'MultiScreenMode=1' in (home/'.config/kwinrc').read_text()
    shortcuts=(home/'.config/kglobalshortcutsrc').read_text()
    # All 20 numbered desktops and every other KWin workspace navigation / move action.
    assert '[kwin]' in shortcuts
    shortcut_lines = shortcuts.split('[kwin]', 1)[1].split('\n[', 1)[0]
    entries = dict(line.split('=', 1) for line in shortcut_lines.splitlines() if '=' in line)
    for desktop_number in range(1, 21):
        assert entries[f'Switch to Desktop {desktop_number}'].startswith('none,'), desktop_number
        assert entries[f'Window to Desktop {desktop_number}'].startswith('none,'), desktop_number
    for key in (
        'Switch to Next Desktop', 'Switch to Previous Desktop',
        'Switch One Desktop Up', 'Switch One Desktop Down',
        'Switch One Desktop to the Left', 'Switch One Desktop to the Right',
        'Walk Through Desktops', 'Walk Through Desktops (Reverse)',
        'Walk Through Desktop List', 'Walk Through Desktop List (Reverse)',
        'Window to Next Desktop', 'Window to Previous Desktop',
        'Window One Desktop Up', 'Window One Desktop Down',
        'Window One Desktop to the Left', 'Window One Desktop to the Right',
        'Window On All Desktops', 'ShowDesktopGrid',
    ):
        assert key in entries and entries[key].startswith('none,'), key
    assert 'Ctrl+F4' not in [val.split(',')[0] for val in entries.values()]
    assert entries.get('Walk Through Windows', 'Alt+Tab').startswith(('Alt+Tab', 'none,'))
    assert 'Close=Ctrl+W; Ctrl+F4' in (home/'.config/kdeglobals').read_text()
    solid=home/'.local/share/solid/actions/wolf-format-usb.desktop'
    assert "StorageDrive.bus == 'Usb' AND StorageDrive.hotpluggable == true" in solid.read_text()
    assert '--browse' in solid.read_text()
    assert not (home/'.local/share/kio/servicemenus/wolf-format-usb.desktop').exists()
    assert not (home/'.local/share/applications/wolf-format-removable.desktop').exists()
    vscode=home/'.local/share/kio/servicemenus/wolf-open-vscode.desktop'
    assert vscode.exists()
    assert 'Exec=/usr/local/bin/wolf-open-vscode-kde %f' in vscode.read_text()
    for p in [desktop,solid,vscode,home/'.config/kcminputrc',home/'.config/kdeglobals']:
        assert p.stat().st_uid == 1000 and p.stat().st_gid == 1000, str(p)
    # Reapplication must not duplicate Thorium keys or services.
    configure(root, 'wolf', ROOT/'assets', True, True)
    assert desktop.read_text().count('StartupWMClass=Thorium-browser') == 1
    print('[OK] Perfil Daily+Development: Thorium, mouse, Fastfetch, Solid USB, Dolphin VS Code, ownership e idempotencia.')
with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp);(root/'etc').mkdir();(root/'etc/passwd').write_text('wolf:x:1000:1000:Wolf:/home/wolf:/bin/bash\n')
    home=root/'home/wolf';home.mkdir(parents=True)
    configure(root,'wolf',ROOT/'assets',False,False)
    assert not (home/'.local/share/applications/thorium-browser-avx2.desktop').exists()
    assert not (home/'.local/share/kio/servicemenus/wolf-open-vscode.desktop').exists()
    assert (home/'.local/share/solid/actions/wolf-format-usb.desktop').is_file()
    assert 'PointerAccelerationProfile=1' in (home/'.config/kcminputrc').read_text()
    keymap=(home/'.config/kglobalshortcutsrc').read_text()
    assert 'Switch to Desktop 4=none,Ctrl+F4,Switch to Desktop 4' in keymap
    assert 'Switch to Desktop 20=none,none,Switch to Desktop 20' in keymap
    assert 'Walk Through Desktops=none,none,Walk Through Desktops' in keymap
    assert 'Close=Ctrl+W; Ctrl+F4' in (home/'.config/kdeglobals').read_text()
    print('[OK] Perfil Minimal: sem navegador/VSCode, mouse Flat e acao USB presentes.')
# Backend de formatação: só descobre partições USB, nunca discos inteiros ou internos.
formatter = runpy.run_path(str(ROOT/'tools/kde/wolf-format-removable'))
valid = [
    {'type':'disk','tran':'sata','path':'/dev/sda','children':[{'type':'part','path':'/dev/sda1','mountpoints':[]}]},
    {'type':'disk','tran':'usb','path':'/dev/sdb','children':[{'type':'part','path':'/dev/sdb1','size':'32G','maj:min':'8:17','mountpoints':[]}]},
    {'type':'disk','tran':'usb','path':'/dev/sdc','children':[{'type':'part','path':'/dev/sdc1','mountpoints':['/home/wolf']}]},
    {'type':'disk','tran':'usb','path':'/dev/sdd','children':[{'type':'disk','path':'/dev/sdd1','mountpoints':[]}]},
]
candidates=list(formatter['_eligible_partitions'](valid))
assert len(candidates)==1 and candidates[0]['device']=='/dev/sdb1',candidates
assert formatter['_validate_lsblk'](valid,'/dev/sdb1')=='/dev/sdb1'
for forbidden in ['/dev/sda1','/dev/sdc1','/dev/sdd','/dev/sdd1']:
    try: formatter['_validate_lsblk'](valid,forbidden)
    except formatter['UnsafeTarget']: pass
    else: raise AssertionError('Alvo inseguro foi aceito: '+forbidden)
print('[OK] Formatador USB: disco interno, USB montado fora de midias e disco inteiro recusados.')
assert (ROOT/'assets/zsh/fastfetch-wolf-tux-tty.txt').read_text() == (ROOT/'branding-assets/zsh/fastfetch-wolf-tux-tty.txt').read_text()
assert (ROOT/'assets/zsh/fastfetch-wolf-tux-tty.txt').read_text().strip().endswith('WOLF LINUX')
print('[OK] NVIDIA R620 condicionado, kernel+LTS, SDDM/Xorg preservado, sintaxe e DevKit Refinos1.')
