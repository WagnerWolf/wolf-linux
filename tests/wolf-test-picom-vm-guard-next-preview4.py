#!/usr/bin/env python3
"""Não abre Picom. Simula VM, físico e Wayland usando stubs locais."""
from pathlib import Path
import os
import importlib.util
from unittest.mock import patch
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'tools/lxqt/wolf-picom-session.sh'
HOTFIX=ROOT/'experimental/picom/corrigir-autostart-vm.py'
INSTALLER=(ROOT/'install/wolf-install.sh').read_text(encoding='utf-8')
assert 'install -m 0755 "$source/wolf-picom-session.sh"' in INSTALLER
assert 'wolf-picom-session.sh wolf-lxqt-menu.svg' in INSTALLER
assert SCRIPT.is_file() and HOTFIX.is_file()
subprocess.run(['bash','-n',str(SCRIPT)],check=True)
subprocess.run(['python3','-m','py_compile',str(HOTFIX)],check=True)

with tempfile.TemporaryDirectory() as t:
    home=Path(t)/'home'; home.mkdir()
    bin_dir=Path(t)/'bin';bin_dir.mkdir()
    log=Path(t)/'calls.log'
    detector=bin_dir/'systemd-detect-virt'
    detector.write_text('''#!/bin/bash
if [[ "$WOLF_FAKE_VM" == "yes" ]]; then
    if [[ "$*" != *"--quiet"* ]]; then echo qemu; fi
    exit 0
fi
exit 1
''')
    detector.chmod(0o755)
    picom=bin_dir/'picom'
    picom.write_text('''#!/bin/bash
printf '%s\n' "$*" >> "$WOLF_FAKE_LOG"
''')
    picom.chmod(0o755)
    env={**os.environ,'PATH':f'{bin_dir}:'+os.environ['PATH'],'HOME':str(home),'WOLF_FAKE_LOG':str(log)}
    def run(vm='yes',session='x11',mode=None,status=False):
        log.unlink(missing_ok=True)
        e={**env,'WOLF_FAKE_VM':vm,'XDG_SESSION_TYPE':session}
        if mode is not None: e['WOLF_PICOM_VM_MODE']=mode
        else:e.pop('WOLF_PICOM_VM_MODE',None)
        result=subprocess.run([str(SCRIPT)]+(['--status'] if status else []),env=e,
                               text=True,capture_output=True)
        calls=log.read_text().splitlines() if log.is_file() else []
        return result,calls
    result,calls=run(); assert result.returncode==0 and not calls
    result,calls=run(mode='xrender'); assert calls==['--config /dev/null --backend xrender'],calls
    result,calls=run(mode='glx'); assert calls==[f'--config {home}/.config/picom/picom.conf'],calls
    result,calls=run(vm='no'); assert calls==[f'--config {home}/.config/picom/picom.conf'],calls
    result,calls=run(vm='no',session='wayland'); assert not calls and result.returncode==0
    result,calls=run(mode='oops'); assert result.returncode==2 and not calls
    result,calls=run(status=True); assert 'compositor=desativado' in result.stdout and not calls
    result,calls=run(mode='xrender',status=True); assert 'compositor=xrender' in result.stdout and not calls
    result,calls=run(vm='no',status=True); assert 'físico' in result.stdout and not calls

# Hotfix no sistema instalado: migrar o autostart original sem alterar TryExec.
spec=importlib.util.spec_from_file_location('wolf_vm_hotfix',HOTFIX)
hotfix=importlib.util.module_from_spec(spec)
spec.loader.exec_module(hotfix)
with tempfile.TemporaryDirectory() as t:
    h=Path(t)
    a=h/'.config/autostart/wolf-picom.desktop';a.parent.mkdir(parents=True)
    helper=h/'.local/bin/wolf-picom-session'
    a.write_text(hotfix.OLD,encoding='utf-8')
    with patch.object(hotfix,'HOME',h),patch.object(hotfix,'AUTO',a),patch.object(hotfix,'HELPER',helper),patch.object(hotfix.os,'geteuid',return_value=1000):
        hotfix.main()
        after=a.read_text(encoding='utf-8')
        assert 'TryExec=picom\n' in after
        assert f'Exec={helper}\n' in after
        assert helper.is_file() and helper.stat().st_mode & 0o111
        hotfix.main() # reexecutar é seguro
        a.write_text(hotfix.OLD+'Hidden=true\n',encoding='utf-8')
        try:hotfix.main()
        except RuntimeError:pass
        else:raise AssertionError('Autostart desativado não pode ser atualizado')
        assert 'Hidden=true' in a.read_text(encoding='utf-8')

print('[OK] Picom VM guard: VM off/xrender/glx, físico GLX, Wayland off, status e guard do instalador')
