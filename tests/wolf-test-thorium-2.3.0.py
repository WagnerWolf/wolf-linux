#!/usr/bin/env python3
"""Regression checks for Stable Thorium/Flutter: local, read-only, no AUR network."""
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import re

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
install = (root / 'install/wolf-install.sh').read_text(encoding='utf-8')
manifest = (root / 'package-profiles/packages.conf').read_text(encoding='utf-8')
profiles = (root / 'tests/wolf-configure-user-defaults.py').read_text(encoding='utf-8')
assert (root / 'VERSION').read_text().strip() == '2.3.1'
assert 'thorium-browser-avx2-bin' in manifest
assert not re.search(r'^\s*google-chrome\s*$', manifest, flags=re.M)
assert re.search(r'DAILY_THIRD_PARTY_PACKAGES=\(\n\s+thorium-browser-avx2-bin\b', manifest)
assert 'export CHROME_EXECUTABLE=/usr/local/bin/wolf-thorium' in install
assert '/usr/local/bin/google-chrome' not in install.split('install_flutter_sdk() {',1)[1].split('\n}',1)[0]
assert 'stage "66-thorium-launcher" install_wolf_thorium_launcher' in install
assert install.index('stage "64-resolver-stacks"') < install.index('stage "66-thorium-launcher"') < install.index('stage "68-android-flutter"')
assert install.index('if stack_selected daily && ! grep -qE') < install.index('    confirm_installation\n') < install.index('stage "10-preparar-disco"')
assert 'PRETTY_NAME="Wolf Linux 2.3.1"' in install
assert 'VERSION_ID="2.3.1"' in install
assert 'grep -Fxq \'PRETTY_NAME="Wolf Linux 2.3.1"\'' in install
assert 'CHROME_EXECUTABLE=/usr/local/bin/wolf-thorium' in (root/'assets/zsh/zshrc').read_text()
assert 'CHROME_EXECUTABLE=/usr/local/bin/wolf-thorium' in (root/'branding-assets/zsh/zshrc').read_text()
assert 'thorium-browser-avx2.desktop' in (root/'tools/control-center/wolf_profile.py').read_text()
assert 'google-chrome.desktop' not in profiles

wrapper = root / 'tools/wolf-thorium'
assert wrapper.is_file() and wrapper.stat().st_mode & 0o111
for cand in ('/usr/bin/thorium-browser-avx2','/usr/bin/thorium-browser','/usr/bin/thorium'):
    assert cand in wrapper.read_text()
assert 'google-chrome-stable' not in wrapper.read_text()
assert subprocess.run(['bash','-n',str(wrapper)],capture_output=True).returncode == 0
assert subprocess.run(['bash','-n',str(root/'gerar-iso.sh')],capture_output=True).returncode == 0

# Check MIME mappings with real/fallback desktop files and without touching user home.
ns = runpy.run_path(str(root/'tests/wolf-configure-user-defaults.py'))
select = ns['thorium_desktop']; apply_mime = ns['apply_mime']
for filename in ('thorium-browser-avx2.desktop','thorium-browser.desktop','thorium.desktop'):
    with tempfile.TemporaryDirectory() as temp:
        r=Path(temp)
        d=r/'usr/share/applications'
        d.mkdir(parents=True)
        (d/filename).write_text('[Desktop Entry]\nName=Thorium\n',encoding='utf-8')
        assert select(r) == filename
        apply_mime(r/'home/wolf/.config/mimeapps.list', True, select(r))
        mime=(r/'home/wolf/.config/mimeapps.list').read_text()
        assert f'x-scheme-handler/http={filename};' in mime
        assert f'x-scheme-handler/https={filename};' in mime
        assert f'text/html={filename};' in mime
        assert 'google-chrome' not in mime
with tempfile.TemporaryDirectory() as temp:
    p=Path(temp)/'mimeapps.list'
    apply_mime(p,False)
    assert 'x-scheme-handler/https' not in p.read_text()

print('[OK] Thorium AUR Daily/Basic/Test/Full, AVX2 preflight, Flutter wrapper, MIME KDE, version/identity, desktop alternativo.')
