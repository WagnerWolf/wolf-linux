#!/usr/bin/env python3
"""Regression for the alpha39 Live wolf-install dispatch bug; no disk writes."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
customizer = (root / 'tests/wolf-customize-iso-profile.sh').read_text(encoding='utf-8')
installer = (root / 'install/wolf-install.sh').read_text(encoding='utf-8')
match = re.search(r"cat > \"\$AIROOT/usr/local/bin/wolf-install\" <<'WRAP'\n(.*?)\nWRAP", customizer, re.S)
assert match, 'Archiso wrapper template missing'
wrapper = match.group(1)
assert 'exec /root/wolf-linux/install/wolf-install.sh "$@"' in wrapper
assert '--review-multidisk-plan|--simulate-multidisk-plan' in wrapper
assert 'Opção desconhecida do lançador Wolf:' in wrapper
assert '[[ "${1:-}" == "--review-multidisk-plan"' in installer
assert 'wolf_discovery.py' in installer
help_run = subprocess.run(['bash', str(root / 'install/wolf-install.sh'), '--help'],
                          capture_output=True, text=True, timeout=5)
assert help_run.returncode == 0, help_run.stderr
assert '--review-multidisk-plan F' in help_run.stdout
assert '--simulate-multidisk-plan F' in help_run.stdout

with tempfile.TemporaryDirectory(prefix='wolf-alpha40-') as tmp:
    temp = Path(tmp)
    # Do not execute actual installer: stub records every argument.
    stub = temp / 'target.sh'
    stub.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "$WOLF_CAPTURE"\n')
    stub.chmod(0o755)
    staged_wrapper = temp / 'wolf-install'
    staged_wrapper.write_text(wrapper.replace(
        'exec /root/wolf-linux/install/wolf-install.sh "$@"', 'exec "$WOLF_TEST_TARGET" "$@"'))
    staged_wrapper.chmod(0o755)
    capture = temp / 'capture'
    env = dict(os.environ, WOLF_TEST_TARGET=str(stub), WOLF_CAPTURE=str(capture))

    def check(args, expected=None, code=0):
        capture.unlink(missing_ok=True)
        done = subprocess.run([str(staged_wrapper), *args], capture_output=True, text=True,
                              timeout=5, env=env)
        assert done.returncode == code, (args, done.returncode, done.stdout, done.stderr)
        assert (capture.read_text().splitlines() if capture.exists() else None) == expected, (args, done.stdout, done.stderr)

    for mode in ('--review-multidisk-plan', '--simulate-multidisk-plan',
                 '--review-gui-plan', '--simulate-gui-plan', '--preflight-gui-plan-vm'):
        check([mode, '/tmp/preview.json'], [mode, '/tmp/preview.json'])
    check(['--execute-gui-plan-vm', '/tmp/preview.json'], ['--execute-gui-plan-vm', '/tmp/preview.json'])
    check(['--execute-gui-plan-vm-click', '/tmp/preview.json'], ['--execute-gui-plan-vm-click', '/tmp/preview.json'])
    check(['--reset-state'], ['--reset-state'])
    check(['--help'], ['--help'])
    check(['--install'], ['--install'])
    check(['--vm-install'], ['--vm-install'])
    check(['--unrecognized-operation'], None, 2)
    check(['--review-multidisk-plan', '/tmp/preview.json', '--bad'], None, 2)

# Fail closed when argument is missing: do not enter interactive installer.
for mode in ('--review-multidisk-plan', '--simulate-multidisk-plan'):
    result = subprocess.run(['bash', str(root / 'install/wolf-install.sh'), mode],
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 2, result.stdout
    assert '[ERRO] Informe o JSON de planejamento multidisco' in result.stderr

print('[OK] alpha40: lançamento multidisco review/simulate sem --install')
print('[OK] alpha40: comandos GUI/VM e modos legados preservados')
print('[OK] alpha40: opções desconhecidas não disparam instalação')
print('[OK] alpha40: ajuda Bash documenta os dois modos multidisco')
