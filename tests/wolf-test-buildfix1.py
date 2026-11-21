#!/usr/bin/env python3
"""Regressões BuildFix1: sem pacman real, sem root e sem construção de ISO."""
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import subprocess

root = Path(__file__).resolve().parents[1]
prep = root / 'preparar_ambiente_wolf_linux.sh'
iso = root / 'gerar-iso.sh'
for script in (prep, iso):
    assert subprocess.run(['bash', '-n', str(script)], capture_output=True).returncode == 0
assert sorted(x.name for x in root.glob('gerar-iso*.sh')) == ['gerar-iso.sh']
presrc=prep.read_text()
assert presrc.index('sudo pacman -S --needed') < presrc.index('if [[ ! -d "$RELENG"')
assert 'sudo pacman -S --noconfirm archiso' in presrc
assert 'wolf-linux-iso-project=2.3.0-refinos1-buildfix1' in presrc
with TemporaryDirectory(prefix='wolf-buildfix1-') as td:
    td = Path(td)
    good = td / 'prepared project'
    (good / 'tests').mkdir(parents=True)
    (good / 'iso-profile').mkdir()
    (good / '.wolf-iso-project').write_text('wolf-linux-iso-project=2.3.0-refinos1-buildfix1\n')
    (good / 'VERSION').write_text('2.3.0\n')
    (good / 'iso-profile/profiledef.sh').write_text('# example profile\n')
    (good / 'tests/wolf-build-iso.sh').write_text('''#!/bin/bash
printf 'build ran\\n' > "$WOLF_PROJECT/build-stamp"
''')
    os.chmod(good / 'tests/wolf-build-iso.sh', 0o755)
    result = subprocess.run(['bash', str(iso), '--project', str(good)],
                            capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert (good / 'build-stamp').read_text() == 'build ran\n', 'Projeto preparado não foi reutilizado'
    assert (good / '.wolf-iso-project').exists(), 'Marcador desapareceu'
    unknown = td / 'desconhecido'
    unknown.mkdir()
    (unknown / 'important.txt').write_text('keep\n')
    result = subprocess.run(['bash', str(iso), '--project', str(unknown)],
                            capture_output=True, text=True, timeout=15)
    assert result.returncode != 0
    assert (unknown / 'important.txt').read_text() == 'keep\n'
    assert 'não reconhecido' in result.stderr
    # O fluxo de novo projeto com --skip-deps deve diagnosticar releng ausente.
    missing = td / 'new'
    env = os.environ.copy()
    env['WOLF_RELENG'] = str(td / 'missing-releng')
    result = subprocess.run(['bash', str(iso), '--skip-deps', '--project', str(missing)],
                            env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode != 0
    assert 'Retire --skip-deps' in result.stderr
    assert not missing.exists(), 'Projeto não deve ser criado sem releng'
print('[OK] BuildFix1: gerador único, releng após dependências, reuso de projeto preparado e proteção de diretório existente')
