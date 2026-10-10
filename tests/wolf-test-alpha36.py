#!/usr/bin/env python3
"""Alpha36: regressões sem filesystem de hardware, sem montagens reais."""
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
lg=ROOT/'live-gui'
menu=(lg/'home/.config/openbox/menu.xml').read_text()
main=(lg/'main.py').read_text()
stage=(ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
policy=(lg/'wolf-live-udisks-polkit.rules').read_text()
clock=(lg/'wolf-live-time-status').read_text()
ET.parse(lg/'home/.config/openbox/menu.xml')
for src in (menu,main):
    assert 'pcmanfm-qt' in src
    assert 'wolf-live-mount-manager' not in src
    assert 'wolf-live-browser' in src
assert 'pkexec pcmanfm-qt' not in stage+main+menu
assert 'sudo pcmanfm-qt' not in stage+main+menu
assert 'gvfs' in stage and 'udisks2' in stage and 'lxqt-policykit' in stage
assert 'org.freedesktop.udisks2.filesystem-mount' in policy
assert 'org.freedesktop.udisks2.filesystem-mount-system' in policy
assert 'subject.user === "wolf"' in policy and 'subject.active === true' in policy and 'subject.local === true' in policy
for denied in ('polkit.Result.AUTH_ADMIN_KEEP','partition-modify','filesystem-mkfs','lvm2-vg-manage'):
    assert denied not in policy
assert 'systemd-timesyncd.service' in stage
assert 'timedatectl status' in clock
assert 'systemd-timesyncd.service' in clock
assert 'wolf-live-time-status' in main and 'wolf-live-time-status' in stage
assert 'wolf-live-mount-manager' in stage and 'rm -f' in stage  # remove resíduos de staging antigo
print('[OK] alpha36: PCManFM-Qt sem root; UDisks2 mount-only; NTP e remoção do manager legado')
