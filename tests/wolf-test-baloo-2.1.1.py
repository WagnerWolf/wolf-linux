#!/usr/bin/env python3
"""Regression contract: install-system-only Baloo override, package manager 0.3.3."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'install/wolf-install.sh').read_text()
assert 'install_baloo_qt_offscreen() {' in s
assert '"/mnt/etc/systemd/user/kde-baloo.service.d"' in s
assert 'Environment=QT_QPA_PLATFORM=offscreen' in s
assert re.search(r'configure_services\(\) \{\s*#.*?\n.*?install_baloo_qt_offscreen',s,re.S)
assert s.count('install_baloo_qt_offscreen') == 2
assert 'Environment=QT_QPA_PLATFORM=offscreen' not in (ROOT/'tests/wolf-customize-iso-profile.sh').read_text()
assert 'QT_QPA_PLATFORM=offscreen' not in (ROOT/'tools/wolf-first-login-plasma.sh').read_text()
assert (ROOT/'tools/package-manager/wolfpkg/__init__.py').read_text().find('0.3.3')>=0
print('[OK] Baloo: override systemd apenas no alvo instalado; Package Manager 0.3.3')
