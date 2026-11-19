#!/usr/bin/env python3
"""Contratos de persistência do Alt+Tab 0.3 e Keeper 0.2, sem tocar no host."""
from pathlib import Path
import importlib.util
from tempfile import TemporaryDirectory
import shutil
import ast

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'tools/lxqt'
SRC = BASE/'responsividade'
INSTALL = BASE/'wolf-responsividade-instalar.py'
spec=importlib.util.spec_from_file_location('wolf_next5',INSTALL)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

for fn in ('wolf-alt-tab-monitor','wolf-alt-tab-daemon.py','wolf_alt_common.py',
           'wolf_alt_core.py','wolf-window-keeper.py'):
    ast.parse((SRC/fn).read_text(encoding='utf-8'))
keeper=(SRC/'wolf-window-keeper.py').read_text()
daemon=(SRC/'wolf-alt-tab-daemon.py').read_text()
assert 'select.select([reader.dpy]' in keeper
assert 'flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)' in keeper
assert 'aguardando XRandR' in keeper
assert 'self.gui.tk.createfilehandler' in daemon
assert "['--serve']" in INSTALL.read_text()
assert "['--fix']" in INSTALL.read_text()
assert 'OnlyShowIn=LXQt;' in INSTALL.read_text()
assert '--no-start' in INSTALL.read_text()

with TemporaryDirectory(prefix='wolf-next5-test-') as d:
    home=Path(d)/'user';home.mkdir()
    conf=home/'.config/openbox';conf.mkdir(parents=True)
    (conf/'lxqt-rc.xml').write_text('''<?xml version="1.0"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
 <keyboard><keybind key="A-Tab"><action name="Execute"><command>
 /home/demo/.local/bin/wolf-alt-tab-monitor
 </command></action></keybind></keyboard></openbox_config>''')
    old=home/'.local/bin/wolf-alt-tab-monitor';old.parent.mkdir(parents=True)
    legacy=(BASE/'alt_tab_visual.py').read_bytes();old.write_bytes(legacy)
    # Base 2.2, sem daemon: instala tudo e preserva seletor anterior como contingência.
    backup=mod.install(home,SRC,start=False)
    assert backup and (backup/'manifest.json').is_file()
    assert (home/'.local/lib/wolf-alt-tab/legacy_alt_tab.py').read_bytes()==legacy
    assert 'OnlyShowIn=LXQt' in (home/'.config/autostart/wolf-window-keeper.desktop').read_text()
    assert '--fix' in (home/'.config/autostart/wolf-window-keeper.desktop').read_text()
    assert '--serve' in (home/'.config/autostart/wolf-alt-tab-daemon.desktop').read_text()
    assert mod.install(home,SRC,start=False) is None, 'reaplicação deve ser idempotente'
    # Reverter somente arquivos alterados, sem tocar nas teclas Openbox.
    mod.restore(home, backup)
    assert old.read_bytes()==legacy
    assert not (home/'.config/autostart/wolf-window-keeper.desktop').exists()
    assert 'wolf-alt-tab-monitor' in (conf/'lxqt-rc.xml').read_text()
    # Simular o sistema físico já com o 0.3 e sua cópia de contingência.
    old.write_bytes((SRC/'wolf-alt-tab-monitor').read_bytes())
    lib=home/'.local/lib/wolf-alt-tab';lib.mkdir(parents=True, exist_ok=True)
    original_fallback=b'# legacy Wolf\nprint("original")\n'
    (lib/'legacy_alt_tab.py').write_bytes(original_fallback)
    backup=mod.install(home,SRC,start=False)
    assert backup and (lib/'legacy_alt_tab.py').read_bytes()==original_fallback
    assert mod.install(home,SRC,start=False) is None

installer=(ROOT/'install/wolf-install.sh').read_text()
assert 'wolf-responsividade-instalar.py --no-start' in installer
assert installer.index('promover-alt-tab.py ||') < installer.index('wolf-responsividade-instalar.py --no-start ||')
assert '"$dest/responsividade"' in installer
assert 'wolf-window-keeper.py' in installer
print('[OK] Next Preview 5: persistência, autostart, único daemon, backups e idempotência')
