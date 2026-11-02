#!/usr/bin/env python3
"""Regressão sem efeitos colaterais para a identidade da release 2.2.0."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
assert version == '2.2.0', version

installer = (root / 'install/wolf-install.sh').read_text()
identity = installer.split('configure_wolf_identity() {', 1)[1].split('preflight_preserved_home_identity() {', 1)[0]
assert 'WOLF_VERSION="2.2.0"' in installer
assert 'PRETTY_NAME="Wolf Linux 2.2"' in identity
assert 'VERSION_ID="2.2.0"' in identity
assert "grep -Fxq 'PRETTY_NAME=\"Wolf Linux 2.2\"'" in identity
assert 'grep -Fxq "VERSION_ID=' in identity
assert 'WOLF LINUX 2.2 — INSTALAÇÃO CONCLUÍDA' in installer

live = (root / 'tests/wolf-customize-iso-profile.sh').read_text()
assert 'VERSION_ID="2.2.0"' in live
assert 'PRETTY_NAME="Wolf Linux 2.2 Live"' in live
assert 'VARIANT="Wolf Linux 2.2 Live Graphical Installer"' in live
assert 'Wolf Linux 2.2 Graphical Live Installer' in live
assert 'Wolf Linux 2.2 RC1' not in live

preparer = (root / 'preparar_ambiente_wolf_linux.sh').read_text()
assert 'RELEASE-NOTES-2.2.0.md' in preparer
assert (root / 'RELEASE-NOTES-2.2.0.md').is_file()
# O gerador é usado no DevKit e deve ser copiado também ao projeto preparado.
assert 'install -m 0755 "$SELF_DIR/gerar-iso-2.2.0.sh" "$PROJECT/gerar-iso-2.2.0.sh"' in preparer
release_builder = root / 'gerar-iso-2.2.0.sh'
if not release_builder.is_file():
    raise SystemExit(f'[ERRO] Gerador de ISO ausente: {release_builder}. '
                     'Reprepare com o DevKit SmokeFix1 ou copie o gerador do DevKit para a raiz do projeto.')
builder = release_builder.read_text()
assert 'wolf-linux-2.2.0' in builder and '2.2.0-rc1' not in builder
assert '== 2.2.0' in builder
assert 'wolf-test-lxqt-2.2.0.py' in builder
assert not (root / 'gerar-iso-2.2.0-rc1.sh').exists()
print('[OK] Identidade release 2.2.0 coerente em DevKit, Live, destino e gerador')
