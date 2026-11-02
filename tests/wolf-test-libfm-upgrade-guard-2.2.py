#!/usr/bin/env python3
"""Smoke guard: não executa pacman nem modifica o sistema."""
from pathlib import Path
from importlib.util import module_from_spec, spec_from_file_location
from tempfile import TemporaryDirectory
from unittest.mock import patch
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT/'tools/wolf-integration-monitor/wolf-libfm-guard.py'
spec = spec_from_file_location('wolf_libfm_guard', SCRIPT)
module = module_from_spec(spec); spec.loader.exec_module(module)
BASE = '''# Pacman original\n[options]\nArchitecture = auto\nIgnorePkg = linux-lts\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n'''
with TemporaryDirectory() as d:
    conf = Path(d)/'pacman.conf'; conf.write_text(BASE)
    assert module.parse(BASE) == (False, False)
    applied, _ = module.apply(conf, 'install')
    assert applied
    assert module.parse(conf.read_text()) == (True, True)
    assert conf.read_text().count('IgnorePkg = libfm-qt') == 1
    assert 'IgnorePkg = linux-lts' in conf.read_text()
    assert 'Include = /etc/pacman.d/mirrorlist' in conf.read_text()
    again, _ = module.apply(conf, 'install')
    assert not again
    removed, _ = module.apply(conf, 'remove')
    assert removed
    assert module.parse(conf.read_text()) == (False, False)
    assert conf.read_text() == BASE
    assert len(list(Path(d).glob('pacman.conf.wolf-backup-*'))) == 2
    # Mesmo após instalação/remoção, outras entradas IgnorePkg devem permanecer.
    assert 'IgnorePkg = linux-lts' in conf.read_text()
    # Pacman conf não pode ser sobrescrito com seções inesperadas ou symlink.
    try: module.update('[core]\nInclude = x\n', 'install')
    except ValueError: pass
    else: raise AssertionError('seção ausente aceita')
    (Path(d)/'link').symlink_to(conf)
    try: module.apply(Path(d)/'link', 'install')
    except ValueError: pass
    else: raise AssertionError('link simbólico aceito')
text = (ROOT/'tools/package-manager/wolfpkg/app.py').read_text()
assert '_protect_libfm_before_transaction(checked=True)' in text
assert 'explicit=any(p.name == \'libfm-qt\'' in text
assert 'Plano de atualização da integração USB' in text
assert 'install_wolf_libfm_usb_package' in (ROOT/'install/wolf-install.sh').read_text()
assert '--install --config /mnt/etc/pacman.conf' in (ROOT/'install/wolf-install.sh').read_text()
assert (ROOT/'tools/package-manager/tests/test_upgrade_guard.py').is_file()
print('[OK] Pacman.conf idempotente, backup e reversão, pré-verificação GUI e testes isolados.')
