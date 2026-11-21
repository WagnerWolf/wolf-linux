#!/usr/bin/env python3
"""Smoke isolado da versão 2.3.1. Nenhum disco/rede/pacman é acessado."""
from pathlib import Path
import re
import sys
p=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
version=(p/'VERSION').read_text().strip()
assert version=='2.3.1', version
installer=(p/'install/wolf-install.sh').read_text()
custom=(p/'tests/wolf-customize-iso-profile.sh').read_text()
prep=(p/'preparar_ambiente_wolf_linux.sh').read_text()
gen=(p/'gerar-iso.sh').read_text()
for part in (installer, custom):
    assert f'VERSION_ID="{version}"' in part
assert f'WOLF_VERSION="{version}"' in installer
assert f'PRETTY_NAME="Wolf Linux {version}"' in installer
assert f'PRETTY_NAME="Wolf Linux {version} Live"' in custom
assert f'Wolf Linux {version} KDE Graphical Installer' in custom
assert f'[[ "$VERSION" == {version} ]]' in gen
for code in (prep,gen):
    assert 'wolf-linux-2.3.1' in code
    assert 'wolf-linux-iso-project=2.3.1' in code
    assert 'wolf-linux-2.3.0-refinos3-aplicativos' not in code
assert (p/'RELEASE-NOTES-2.3.1.md').is_file()
assert '1.0.0' in (p/'tools/package-manager/wolfpkg/app.py').read_text()
assert (p/'tools/subtitle-downloader/legendas/deploy.py').is_file()
assert 'wolf-sem-suspensao --apply' not in prep+gen
assert 'stage "69c3b-legendas-dolphin"' in installer
assert 'nvidia_modeset' in installer and 'opportunistic_flip_sync=0' in installer
print('[OK] Release 2.3.1: instalador, Live, projeto, ISO, PM, legendas, suspensão opcional e NVIDIA coerentes.')
