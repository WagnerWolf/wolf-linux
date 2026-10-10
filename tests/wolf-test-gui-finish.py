#!/usr/bin/env python3
"""Teste não destrutivo do encerramento alpha28: utiliza sudo simulado."""
from __future__ import annotations
import ast
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
ui = (root / 'live-gui/main.py').read_text(encoding='utf-8')
wrapper = root / 'live-gui/wolf-live-execute-vm-plan'
assert 'class InstallFinishedDialog(QDialog)' in ui
assert 'self.console_finish.show()' in ui and 'if rc == 0:' in ui
assert 'self.console_info.setText' in ui
assert 'self._installer_pty = None' in ui
assert 'self._vm_result_poll.timeout.connect(self.check_vm_install_result)' in ui
assert 'self._installer_pty is not None' in ui
assert 'sudo", "-n", "systemctl", "reboot' in ui
assert '"/etc/wolf-linux-live-build"' in ui
ast.parse(ui)

with tempfile.TemporaryDirectory() as temp:
    p = Path(temp)
    bin_dir = p / 'bin'; bin_dir.mkdir()
    sudo = bin_dir / 'sudo'
    sudo.write_text('#!/bin/bash\n'
                    '[[ "$1" == "wolf-install" && "$2" == "--execute-gui-plan-vm" ]] || exit 90\n'
                    'exit "${WOLF_MOCK_EXIT_CODE:-0}"\n')
    sudo.chmod(0o755)
    plan = p / 'plan.json'
    plan.write_text('{"dummy":true}\n')
    env = dict(os.environ)
    env['PATH'] = str(bin_dir) + ':' + os.environ['PATH']
    for code, expected in ((0, 'success'), (42, 'failed 42')):
        result = p / f'{code}.status'
        result.touch(mode=0o600)
        env['WOLF_MOCK_EXIT_CODE'] = str(code)
        finished = subprocess.run(['bash', str(wrapper), str(plan), str(result)],
                                  input='\n', capture_output=True, text=True,
                                  env=env, timeout=10)
        assert finished.returncode == code, (finished.returncode, finished.stderr)
        assert result.read_text().strip() == expected, result.read_text()
        assert ('Instalação concluída com sucesso.' in finished.stdout) == (code == 0)
    # Não aceitar arquivo de resultado ausente ou symlink; nenhum reboot.
    missing = p / 'missing.status'
    denied = subprocess.run(['bash', str(wrapper), str(plan), str(missing)],
                            input='\n', capture_output=True, text=True, env=env, timeout=10)
    assert denied.returncode == 2
    target = p / 'target'
    target.touch()
    alias = p / 'alias'
    alias.symlink_to(target)
    denied = subprocess.run(['bash', str(wrapper), str(plan), str(alias)],
                            input='\n', capture_output=True, text=True, env=env, timeout=10)
    assert denied.returncode == 2

print('[OK] Alpha28: Bash 0 -> success, Bash 42 -> failed; recusas de marcador; nenhum disco/reboot alterado')
