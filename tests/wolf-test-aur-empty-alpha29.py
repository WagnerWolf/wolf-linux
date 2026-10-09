#!/usr/bin/env python3
"""Validação do caminho Minimal: nunca chamar pacman/yay com alvo vazio."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'install/wolf-install.sh').read_text()

def function(name):
    head = f'{name}() {{\n'
    start = source.index(head)
    end = source.index('\n}', start) + len('\n}')
    return source[start:end]

with tempfile.TemporaryDirectory() as tmp:
    package_map = root / 'package-profiles/packages.conf'
    log = Path(tmp) / 'resolution.tsv'
    script = f'''#!/usr/bin/env bash
set -Eeuo pipefail
source {str(package_map)!r}
declare -A SELECTED_STACKS=()
PACKAGE_RESOLUTION_LOG={str(log)!r}
ok() {{ printf '[OK] %s\\n' "$*"; }}
warn() {{ printf '[WARN] %s\\n' "$*"; }}
die() {{ printf '[FAIL] %s\\n' "$*" >&2; exit 1; }}
arch-chroot() {{ echo 'pacman/yay NÃO DEVERIAM RODAR no Minimal' >&2; exit 99; }}
{function('stack_selected')}
{function('collect_selected_stack_packages')}
{function('install_selected_stack_packages')}
install_selected_stack_packages
[[ ! -s "$PACKAGE_RESOLUTION_LOG" ]]
'''
    result = subprocess.run(['bash', '-c', script], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr or result.stdout
    assert 'Nenhum pacote opcional' in result.stdout
    assert 'pacman/yay' not in result.stderr

    # Com Extra selecionado, EXTRA_PACKAGES=() não deve criar um pacote de nome vazio.
    # Testamos a rotina de filtragem de pacote por pacote usada na etapa 64.
    extras = script.replace('install_selected_stack_packages\n[[ ! -s "$PACKAGE_RESOLUTION_LOG" ]]', '''
SELECTED_STACKS[extras]=1
counter=0
while IFS= read -r pkg; do
  [[ -n "${pkg//[[:space:]]/}" ]] || continue
  [[ -n "$pkg" ]] || exit 7
  counter=$((counter+1))
done < <(collect_selected_stack_packages)
((counter > 0))
''')
    result = subprocess.run(['bash', '-c', extras], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr or result.stdout

print('[OK] alpha29 AUR: Minimal não chama pacman/yay; entradas vazias em arrays opcionais filtradas')
