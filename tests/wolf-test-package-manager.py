#!/usr/bin/env python3
"""Integration tests for Wolf Package Manager (no pacman calls or disk changes)."""
from pathlib import Path
import ast
import subprocess
import sys
root=Path(__file__).resolve().parents[1]
installer=(root/'install/wolf-install.sh').read_text()
packages=(root/'package-profiles/packages.conf').read_text()
source=root/'tools/package-manager'
assert 'octopi' not in '\n'.join(line for line in packages.splitlines() if not line.lstrip().startswith('#'))
assert 'pacman-contrib' in packages and 'pyside6' in packages
assert installer.count('install_wolf_package_manager') >= 2
assert installer.index('install_wolf_package_manager\n    ok') > installer.index('find /mnt/etc/xdg/autostart')
assert 'Exec=/usr/local/bin/wolf-package-manager --tray' in installer
assert 'exec /usr/bin/python3 /usr/local/lib/wolf-linux/package-manager/main.py' in installer
assert 'if ( ensure_yay ); then' in installer
assert (source/'wolfpkg/askpass.sh').is_file()
for name in ('app.py','backend.py','search_service.py','worker.py','terminal.py'):
    ast.parse((source/'wolfpkg'/name).read_text())
assert '--tray' in (source/'wolfpkg/app.py').read_text()
assert 'yay' in (source/'wolfpkg/backend.py').read_text()
assert 'octopi' not in (root/'tools/control-center/main.py').read_text().lower()
assert 'octopi' not in (root/'tools/control-center/backend.py').read_text().lower()
proc=subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py'],cwd=str(source),capture_output=True,text=True,timeout=60)
assert proc.returncode == 0, proc.stdout + '\n' + proc.stderr
print('[OK] Wolf Package Manager instalado no sistema, autostart, menu, yay, Control Center e testes upstream')
