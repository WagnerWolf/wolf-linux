#!/usr/bin/env python3
"""Regressões estáticas e isoladas para entrada direta do editor de monitores."""
from __future__ import annotations

import importlib.util
import contextlib
import io
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import os
import sys

r = Path(__file__).resolve().parent.parent
installer = (r/'install/wolf-install.sh').read_text()
cc = r/'tools/control-center'
lxqt = (r/'tools/lxqt/configurar.py').read_text()
main = (cc/'main.py').read_text()
launcher = (cc/'wolf-monitors.desktop').read_text()
editor = (cc/'monitor_editor.py').read_text()

assert 'wolf_monitors.py' in installer
assert '/mnt/usr/local/bin/wolf-monitors' in installer
assert '/mnt/usr/share/applications/wolf-monitors.desktop' in installer
assert 'exec /usr/local/bin/wolf-monitors' in installer
assert 'exec /usr/bin/python3 /usr/local/lib/wolf-linux/control-center/main.py' in installer
assert 'if len(sys.argv) == 2 and sys.argv[1] == "--monitors":' in main
assert 'Exec=/usr/local/bin/wolf-control-center --monitors' in launcher
assert 'OnlyShowIn=LXQt;' in launcher
assert 'NoDisplay=true' in lxqt and "DATA/'applications/lxqt-config-monitor.desktop'" in lxqt
assert 'setup_wolf_monitors_menu(inst)' in lxqt
assert 'Abrir configurador nativo LXQt' not in main
assert "native = QPushButton('Ferramenta LXQt')" not in editor

spec = importlib.util.spec_from_file_location('wolf_monitors', cc/'wolf_monitors.py')
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
assert mod.editor_dir() == cc
# Simular uma cópia incompleta da instalação global e cópia completa local.
with TemporaryDirectory() as temp:
    root=Path(temp)
    bad_global = root/'system'
    bad_global.mkdir()
    fake_file=bad_global/'wolf_monitors.py'
    fake_file.write_text('# only launcher')
    xdg = root/'user-data'
    user_dir=xdg/'wolf-linux/control-center'
    user_dir.mkdir(parents=True)
    for f in ('monitor_editor.py','monitor_layout.py'):
        (user_dir/f).write_text('# mock')
    original_file=mod.__file__
    try:
        mod.__file__=str(fake_file)
        with patch.dict(os.environ, {'XDG_DATA_HOME':str(xdg)}):
            assert mod.editor_dir() == user_dir
            (user_dir/'monitor_layout.py').unlink()
            assert mod.editor_dir() is None
    finally:
        mod.__file__=original_file
    # A verificação de ambiente deve encerrar antes de tentar importar Qt.
    with patch.dict(os.environ, {'XDG_SESSION_TYPE':'wayland','DISPLAY':':0'}):
        captured = io.StringIO()
        with contextlib.redirect_stderr(captured):
            assert mod.main()==2
        assert 'somente numa sessão X11' in captured.getvalue()

# O autostart de persistência deve referenciar o módulo de origem, não um
# caminho de instalação local que não existe em uma instalação nova.
sspec=importlib.util.spec_from_file_location('monitor_layout',cc/'monitor_layout.py')
layout=importlib.util.module_from_spec(sspec)
sys.modules[sspec.name]=layout
sspec.loader.exec_module(layout)
with TemporaryDirectory() as temp:
    home=Path(temp)/'test-home'
    home.mkdir()
    out=layout.save_persistent([], home=home)
    saved=(home/'.local/bin/wolf-monitors-apply').read_text()
    assert str((cc/'monitor_layout.py').resolve()) in saved, saved
    assert '$HOME/.local/share/wolf-linux/control-center/monitor_layout.py' not in saved
    assert 'LXQt' in saved and '--apply-saved' in saved
    assert out.exists()

# Confirmar backup/restauração do override .desktop (inclusive /home preservado).
config_path=r/'tools/lxqt/configurar.py'
spec=importlib.util.spec_from_file_location('wolf_lxqt_config',config_path)
config=importlib.util.module_from_spec(spec)
sys.modules[spec.name]=config
spec.loader.exec_module(config)
with TemporaryDirectory() as temp:
    home=Path(temp)/'wolf'
    home.mkdir()
    original_home, original_data, original_base=config.HOME,config.DATA,config.BASE
    try:
        config.HOME=home
        config.DATA=home/'.local/share'
        config.BASE=home/'wolf-backups/lxqt'
        desktop=config.DATA/'applications/lxqt-config-monitor.desktop'
        desktop.parent.mkdir(parents=True)
        desktop.write_text('[Desktop Entry]\nExec=lxqt-config-monitor\nName=Original\n')
        inst=config.Installer()
        config.setup_wolf_monitors_menu(inst)
        backup=inst.complete()
        assert 'NoDisplay=true' in desktop.read_text()
        config.restore(backup)
        assert 'Name=Original' in desktop.read_text()
    finally:
        config.HOME,config.DATA,config.BASE=original_home, original_data, original_base

assert 'for f in main.py backend.py lxqt_support.py wolf_profile.py monitor_editor.py monitor_layout.py wolf_monitors.py' in (cc/'install-local.sh').read_text()
assert 'wolf-monitors.desktop' in (cc/'install-local.sh').read_text()
print('[OK] Monitores: launcher direto, backup LXQt, fallback XDG e autostart com caminho real')
