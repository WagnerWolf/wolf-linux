#!/usr/bin/env python3
"""Regressões da checagem wipefs alpha27: NUNCA gravar em discos reais."""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import ast
import importlib.util
import os
import stat
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('wolf_plan_vm27', root/'live-gui/wolf_plan.py')
wp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wp)
disk = {'path': '/dev/vda', 'size': 64*1024**3, 'maj_min': '252:0', 'model': 'VirtIO',
        'transport': '', 'removable': False, 'partitions': [], 'mountpoints': []}
plan = wp.build_preview(disks=[disk], disk_path='/dev/vda', mode='erase', preset='minimal',
                        stacks=(), hostname='wolf-vm', username='wolf', boot_mode='UEFI',
                        keyboard={'layout': 'br', 'variant': '', 'model': 'abnt2'})
block_stat = SimpleNamespace(st_mode=stat.S_IFBLK | 0o660, st_rdev=os.makedev(252, 0))

def run_with_wipe(result):
    calls = []
    def runner(args, **kwargs):
        calls.append(args)
        if args[0] == 'lsblk':
            assert args == ['lsblk','-nr','-o','TYPE,MOUNTPOINTS','/dev/vda']
            return subprocess.CompletedProcess(args,0,'disk\n','')
        if args[0] == 'wipefs':
            assert args == ['wipefs', '--no-act', '--noheadings', '--output', 'TYPE', '/dev/vda']
            if isinstance(result, Exception):
                raise result
            return result
        if args[0] == 'findmnt':
            assert args == ['findmnt', '--source', '/dev/vda']
            return subprocess.CompletedProcess(args, 1, '', '')
        assert args == ['swapon', '--show=NAME', '--noheadings']
        return subprocess.CompletedProcess(args, 0, '', '')
    with patch.object(wp.Path, 'is_symlink', return_value=False), \
         patch.object(wp.Path, 'exists', return_value=True), \
         patch.object(wp.Path, 'stat', return_value=block_stat), \
         patch.object(wp.subprocess, 'run', side_effect=runner):
        try:
            got = wp.vm_erase_fields(plan, disks=[disk], active_boot='UEFI', check_device=True)
            return got, calls
        except wp.PlanError as ex:
            return str(ex), calls

valid, calls = run_with_wipe(subprocess.CompletedProcess([], 0, '', ''))
assert valid[0] == '/dev/vda' and len(calls) == 4
signed, calls = run_with_wipe(subprocess.CompletedProcess([], 0, 'gpt\n', ''))
assert signed[0] == '/dev/vda' and len(calls) == 4  # assinaturas permitidas no APAGAR DISCO
failure, calls = run_with_wipe(subprocess.CompletedProcess([], 1, '', 'permissão negada'))
assert 'Falha' in failure or 'não conseguiu' in failure
assert 'permissão negada' in failure and len(calls) == 2
exception, calls = run_with_wipe(OSError('wipefs ausente'))
assert 'Falha técnica' in exception and len(calls) == 2

source = (root/'live-gui/main.py').read_text()
tree = ast.parse(source)
assert 'class VmEraseConsentDialog(QDialog)' in source
assert 'self.accept_button.setEnabled(False)' in source
assert 'self.confirm_text.textChanged.connect(' in source
assert 'value == expected' in source
assert 'VmEraseConsentDialog(self, disk).exec() != QDialog.DialogCode.Accepted' in source
assert 'InstallerPty' in source and 'self.console_tab_index' in source

# Verificação real não destrutiva de wipefs sobre arquivo temporário vazio.
with tempfile.TemporaryDirectory() as folder:
    f = Path(folder)/'clean.img'
    with f.open('wb') as h:
        h.truncate(4 * 1024 * 1024)
    check = subprocess.run(['wipefs','--no-act','--noheadings','--output','TYPE',str(f)],
                           capture_output=True,text=True, timeout=8)
    assert check.returncode == 0, check.stderr
    assert not check.stdout.strip(), check.stdout
print('[OK] alpha29: wipefs limpo/assinatura são aceitos para APAGAR; erros técnicos recusados; nenhum disco alterado')
