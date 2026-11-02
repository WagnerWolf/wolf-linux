#!/usr/bin/env python3
"""Teste de identidade da promoção 2.2.0 / Package Manager 0.3.7. Somente leitura."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
for item in ('tools/package-manager/wolfpkg/app.py', 'tools/package-manager/wolfpkg/__init__.py'):
    data = (root / item).read_text()
    assert '0.3.7' in data and '0.3.7-vm-preview' not in data, item
assert (root/'VERSION').read_text().strip() == '2.2.0'
assert (root/'RELEASE-2.2.0-PM-0.3.7.md').is_file()
assert 'IgnorePkg' in (root/'tools/package-manager/wolfpkg/upgrade_guard.py').read_text()
assert 'install_wolf_libfm_usb_package' in (root/'install/wolf-install.sh').read_text()
assert 'release-packages' in (root/'gerar-iso-2.2.0.sh').read_text()
print('[OK] Release 2.2.0 / Package Manager 0.3.7: identidade, documentação e proteção coerentes.')
