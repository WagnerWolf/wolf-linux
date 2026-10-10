#!/usr/bin/env python3
"""Revisão alpha37: Chromium/BlueZ e Rescue somente leitura, sem acessar hardware."""
from pathlib import Path
import ast
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
live = root/'live-gui'
stage = (root/'tests/wolf-stage-live-desktop.sh').read_text()
menu = (live/'home/.config/openbox/menu.xml').read_text()
main = (live/'main.py').read_text()
autostart = (live/'home/.config/openbox/autostart').read_text()
packages = (root/'package-profiles/packages.conf').read_text()
report = (live/'wolf-live-rescue-report').read_text()
rescue = (live/'wolf_rescue.py').read_text()
ET.parse(live/'home/.config/openbox/menu.xml')
ast.parse(rescue)
for pkg in ('chromium','bluez','bluez-utils','blueman','rfkill','efibootmgr'):
    assert pkg in stage, pkg
    if pkg in ('chromium','blueman','rfkill'):
        assert pkg not in packages, f'Live GUI package leaked into installed stacks: {pkg}'
assert "sed -i '/^firefox$/d; /^firefox-i18n-pt-br$/d'" in stage
assert 'firefox' not in menu.lower() and 'firefox' not in main.lower()
assert 'chromium' in menu.lower() and 'chromium' in main.lower()
assert 'blueman-applet' in autostart and 'blueman-manager' in menu and 'blueman-manager' in main
assert 'bluetooth.service' in stage
assert 'wolf-live-rescue' in main and 'wolf-live-rescue' in menu
assert 'wolf-live-rescue-report' in stage
assert 'QPlainTextEdit' in rescue and 'QProcess' in rescue and 'open_fstab' in rescue
assert 'efibootmgr -v' in report
for cmd in ('pvs --readonly','vgs --readonly','lvs --readonly'):
    assert cmd in report
# Exclude commands that perform writes even if function aliases are used.
for token in ('grub-install ', 'grub-mkconfig ', 'mkfs.', 'wipefs ', 'fsck ', 'vgchange ', 'mount -', 'umount ', 'arch-chroot ', 'lvremove ', 'pvremove '):
    assert token not in report.replace('não executa grub-install, fsck, mount ou mkfs', ''), token
browser = (live/'wolf-live-browser').read_text()
assert 'EUID == 0' in browser and '--no-sandbox' not in browser
assert 'usr/bin/chromium' in browser
assert 'sudo pcmanfm-qt' not in main + menu
print('[OK] Alpha37: Chromium sandbox, BlueZ/Blueman, read-only Wolf Rescue, target KDE unchanged')
