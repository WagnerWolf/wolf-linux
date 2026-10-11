#!/usr/bin/env python3
"""Alpha48: execução PTY física com sudo falso. Não altera disco algum."""
from __future__ import annotations
import os
from pathlib import Path
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'live-gui'))
from terminal_engine import InstallerPty, ALLOWED_EXECUTION_MODES

EXPECTED = {'--execute-gui-plan-vm', '--execute-multidisk-lab-vm', '--execute-multidisk-physical'}
assert ALLOWED_EXECUTION_MODES == EXPECTED
for mode in ('--install', '--vm-install', '--reset-state', '--preflight-multidisk-physical',
             '--execute-multidisk-physical;mkfs.ext4', '', '--execute-anything'):
    try:
        InstallerPty().start(Path('/tmp/plan-invalido.json'), mode=mode)
    except ValueError as exc:
        assert 'não autorizado' in str(exc)
    else:
        raise AssertionError('PTY aceitou comando não autorizado: ' + mode)

# Fake sudo executa APENAS confirmações de texto. NUNCA invoca o Wolf Installer.
with tempfile.TemporaryDirectory(prefix='wolf-alpha48-test-') as d:
    tmp = Path(d)
    mockbin = tmp / 'bin'
    mockbin.mkdir()
    sudo = mockbin / 'sudo'
    sudo.write_text('''#!/usr/bin/env bash
[[ "$#" == 4 && "$1" == '-n' && "$2" == 'wolf-install' &&
   "$3" == '--execute-multidisk-physical' && "$4" == "$EXPECTED_PLAN" ]] || exit 93
printf 'Digite ACEITO-PERDA-RAIZ: '
read -r response
[[ "$response" == 'ACEITO-PERDA-RAIZ' ]] || exit 94
printf 'Digite FORMATAR /dev/nvme1n1p1: '
read -r response
[[ "$response" == 'FORMATAR /dev/nvme1n1p1' ]] || exit 95
printf '\\nMOCK-OK: nenhum disco foi alterado\\n'
''')
    sudo.chmod(0o700)
    plan = tmp / 'plan.json'
    plan.write_text('isto nao e um plano executavel')
    old_path = os.environ.get('PATH', '')
    old_expected = os.environ.get('EXPECTED_PLAN')
    os.environ['PATH'] = str(mockbin) + os.pathsep + old_path
    os.environ['EXPECTED_PLAN'] = str(plan)
    engine = InstallerPty()
    try:
        engine.start(plan, mode='--execute-multidisk-physical')
        output = ''
        def collect(token: str) -> None:
            global output
            deadline = time.monotonic() + 6
            while token not in output and time.monotonic() < deadline:
                part, ended = engine.read()
                output += part
                if ended:
                    break
                time.sleep(0.01)
            assert token in output, ('Prompt faltou', token, output)

        collect('ACEITO-PERDA-RAIZ:')
        engine.send('ACEITO-PERDA-RAIZ')
        collect('FORMATAR /dev/nvme1n1p1:')
        engine.send('FORMATAR /dev/nvme1n1p1')
        collect('MOCK-OK')
        assert engine.proc.wait(timeout=6) == 0
        assert engine.poll() == 0
    finally:
        engine.close_read()
        os.environ['PATH'] = old_path
        if old_expected is None:
            os.environ.pop('EXPECTED_PLAN', None)
        else:
            os.environ['EXPECTED_PLAN'] = old_expected

ui = (ROOT / 'live-gui/main.py').read_text()
pty = (ROOT / 'live-gui/terminal_engine.py').read_text()
bash = (ROOT / 'install/wolf-install.sh').read_text()
stage = (ROOT / 'tests/wolf-stage-live-desktop.sh').read_text()
assert "mode='--execute-multidisk-physical'" in ui
assert ui.index("'--preflight-multidisk-physical'") < ui.index("mode='--execute-multidisk-physical'")
assert '"sudo", "-n", "wolf-install", mode, str(plan)' in pty
assert '"--execute-multidisk-physical"' in pty
assert 'revalidate_gui_physical_target\n        mkfs.ext4 -F "$ROOT_DEVICE"' in bash
assert 'FORMAT_ROOT=yes; FORMAT_ESP=no; FORMAT_HOME=no; CLEAN_HOME_DOTFILES=no' in bash
assert '"$SOURCE/terminal_engine.py"' in stage
print('[OK] alpha48: PTY físico inicia processo mock, recebe confirmações e retorna 0')
print('[OK] alpha48: conjunto fechado de 3 modos; flags genéricas recusadas')
print('[OK] alpha48: staging inclui PTY corrigido; barreiras Bash preservadas')
