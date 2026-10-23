#!/usr/bin/env python3
"""Garantias de consistência da identificação da versão final."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
version=(ROOT/'VERSION').read_text().strip()
assert re.fullmatch(r'2\.1\.3(?:-rc[1-9]\d*)?',version)
assert (ROOT/f'RELEASE-NOTES-{version}.md').is_file()
installer=(ROOT/'install/wolf-install.sh').read_text()
custom=(ROOT/'tests/wolf-customize-iso-profile.sh').read_text()
stager=(ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
app=(ROOT/'live-gui/preview/app.py').read_text()
assert f'WOLF_VERSION="{version}"' in installer
assert '[[ -r "$PROJECT_DIR/VERSION" ]] && WOLF_VERSION=' in installer
assert 'PRETTY_NAME="Wolf Linux 2.1"' in installer
assert f'VERSION_ID="{version}"' in installer
assert 'PRETTY_NAME="Wolf Linux 2.1 Live"' in custom
assert f'VERSION_ID="{version}"' in custom
assert 'VERSION_FILE="$PROJECT/VERSION"' in custom
assert 'rm -f "$AIROOT/usr/local/bin/wolf-live-installer-classic"' in stager
assert 'self.continue_button.hide()  # apenas o botão' in app
assert (ROOT/'CHANGELOG.md').exists() and (ROOT/'RELEASE-NOTES-2.0.0.md').exists() and (ROOT/'RELEASE-NOTES-2.1.0.md').exists()
preparer=(ROOT/'preparar_ambiente_wolf_linux.sh').read_text()
assert 'cp -f "$SELF_DIR/CHANGELOG.md" "$PROJECT/CHANGELOG.md"' in preparer
assert 'cp -f "$SELF_DIR/RELEASE-NOTES-2.0.0.md" "$PROJECT/RELEASE-NOTES-2.0.0.md"' in preparer
assert 'cp -f "$SELF_DIR/RELEASE-NOTES-2.1.0.md" "$PROJECT/RELEASE-NOTES-2.1.0.md"' in preparer
for file in ('README.md', 'docs/WOLF-LIVE-GUI.md', 'live-gui/README.md'):
    content=(ROOT/file).read_text()
    assert 'somente demonstração' not in content
    assert 'execução REAL apenas em máquinas virtuais' not in content
for test in ('wolf-test-alpha43.py','wolf-test-alpha45.py','wolf-test-alpha49.py','wolf-test-alpha50.py','wolf-test-alpha56.py'):
    assert "'2.1.1'" in (ROOT/'tests'/test).read_text()
print(f'[OK] Versão {version}: versão única, Live, sistema instalado, arquivos e testes')
