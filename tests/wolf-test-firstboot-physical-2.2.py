#!/usr/bin/env python3
"""Regressão não destrutiva: instalação física LXQt, telas, mouse e XDG pt_BR."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import importlib.util
import sys

root=Path(__file__).resolve().parents[1]
def load(name, relative):
    spec=importlib.util.spec_from_file_location(name,root/relative)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[name]=mod
    spec.loader.exec_module(mod)
    return mod

layout=load('wolf_fix_layout','tools/control-center/monitor_layout.py')
setup=load('wolf_fix_lxqt','tools/lxqt/configurar.py')
monitors=load('wolf_fix_monitors','tools/lxqt/wolf_lxqt_monitors.py')
editor=(root/'tools/control-center/monitor_editor.py').read_text()
assert 'for button in (refresh, native' not in editor
assert 'for button in (refresh, apply, disable_saved, close)' in editor
assert "['/usr/local/bin/wolf-lxqt-monitors']" in editor

with TemporaryDirectory() as d:
    home=Path(d)/'wolf';home.mkdir()
    panel_desktop=home/'.config/autostart/wolf-lxqt-monitors.desktop'
    panel_desktop.parent.mkdir(parents=True)
    panel_desktop.write_text('[Desktop Entry]\nExec=/usr/local/bin/wolf-lxqt-monitors --session\n')
    layout.save_persistent([],home=home)
    restored=home/'.config/autostart/wolf-lxqt-layout-restore.desktop'
    assert restored.is_file()
    assert 'wolf-lxqt-monitors --session' in panel_desktop.read_text()
    layout.disable_persistent(home=home)
    assert not restored.exists()
    assert panel_desktop.exists(), 'Desativar layout não pode apagar autostart do painel'
    # Migração de uma restauração antiga que usava o nome reservado dos painéis.
    panel_desktop.write_text('[Desktop Entry]\nExec='+str(home)+ '/.local/bin/wolf-monitors-apply\n')
    layout.save_persistent([],home=home)
    assert not panel_desktop.exists()
    assert restored.exists()
    layout.disable_persistent(home=home)

with TemporaryDirectory() as d:
    home=Path(d)/'wolf';home.mkdir()
    config=home/'.config'
    data=home/'.local/share'
    with patch.object(setup,'HOME',home),patch.object(setup,'CONFIG',config),\
         patch.object(setup,'DATA',data),patch.object(setup,'BASE',home/'backups'),\
         patch.object(setup.shutil,'which',return_value=None):
        inst=setup.Installer()
        assert setup.setup_ptbr_user_dirs(inst)
        assert not setup.setup_ptbr_user_dirs(inst), 'idempotência'
        setup.setup_pcmanfm_places(inst)
        setup.setup_mouse_flat(inst)
        assert (config/'user-dirs.locale').read_text()=='pt_BR\n'
        actual=(config/'user-dirs.dirs').read_text()
        for s in ('XDG_DESKTOP_DIR="$HOME/Área de Trabalho"',
                  'XDG_DOCUMENTS_DIR="$HOME/Documentos"',
                  'XDG_PICTURES_DIR="$HOME/Imagens"',
                  'XDG_MUSIC_DIR="$HOME/Músicas"',
                  'XDG_VIDEOS_DIR="$HOME/Vídeos"'):
            assert s in actual, s
        bookmark=(config/'gtk-3.0/bookmarks').read_text()
        assert 'M%C3%BAsicas Músicas' in bookmark
        assert 'V%C3%ADdeos Vídeos' in bookmark
        assert 'Pictures' not in bookmark and 'Videos' not in bookmark
        assert 'wolf-lxqt-mouse-flat' in (config/'autostart/wolf-lxqt-mouse-flat.desktop').read_text()
        assert not setup.setup_ptbr_user_dirs(inst)
        assert (home/'Músicas').is_dir()
        inst.complete()

with TemporaryDirectory() as d:
    home=Path(d)/'wolf';home.mkdir()
    config=home/'.config';config.mkdir()
    existing=config/'user-dirs.dirs'
    existing.write_text('XDG_PICTURES_DIR="$HOME/MeuVolume/Images"\n')
    with patch.object(setup,'HOME',home),patch.object(setup,'CONFIG',config),\
         patch.object(setup,'BASE',home/'backups'):
        inst=setup.Installer()
        assert not setup.setup_ptbr_user_dirs(inst)
        assert 'MeuVolume/Images' in existing.read_text()
        assert not (home/'Imagens').exists()

raw='panels=panel1\n[panel1]\ndesktop=0\n[panel2]\ndesktop=1\n'
assert monitors.monitors('Monitors: 2\n 0: +DP-0 1920/500x1080/300+0+0 DP-0\n 1: +*HDMI-0 1920/500x1080/300+1920+0 HDMI-0')==(1,0)
assert monitors.adjust(raw,1,0).startswith('panels=panel1,panel2\n')
assert 'for attempt in range(5)' in (root/'tools/lxqt/wolf_lxqt_monitors.py').read_text()

manifest=(root/'package-profiles/packages.conf').read_text()
installer=(root/'install/wolf-install.sh').read_text()
assert 'xorg-xinput' in manifest and 'xorg-xinput' in installer
assert '50-wolf-lxqt-mouse-flat.conf' in installer
assert 'Option "AccelProfile" "flat"' in installer
assert 'MatchIsTouchpad "off"' in installer
assert 'install -m 0755 "$source/wolf-mouse-flat.sh"' in installer
assert 'install -m 0755 "$source/wolf-user-dirs-ptbr.py"' in installer
mouse=(root/'tools/lxqt/wolf-mouse-flat.sh').read_text()
assert 'libinput Accel Profile Enabled' in mouse and 'libinput Tapping Enabled' in mouse
print('[OK] Primeiro boot: editor sem NameError, restauração separada, 2 monitores, mouse flat e XDG pt_BR')

# Um diretório inglês com dados é renomeado somente em migração explícita.
xdgfix=load('wolf_xdg_migrate','tools/lxqt/wolf-user-dirs-ptbr.py')
with TemporaryDirectory() as d:
    home=Path(d); (home/'.config').mkdir()
    (home/'Pictures').mkdir(); (home/'Pictures/arquivo.png').write_bytes(b'dado')
    (home/'.config/user-dirs.dirs').write_text('XDG_PICTURES_DIR="$HOME/Pictures"\n'
                                                     'XDG_MUSIC_DIR="$HOME/BibliotecaPersonalizada"\n')
    plan=xdgfix.migrate(home,apply=False)
    assert any('RENOMEAR' in line for line in plan)
    assert (home/'Pictures/arquivo.png').is_file()
    xdgfix.migrate(home,apply=True)
    assert (home/'Imagens/arquivo.png').is_file()
    assert not (home/'Pictures').exists()
    assert 'BibliotecaPersonalizada' in (home/'.config/user-dirs.dirs').read_text()
    assert (home/'wolf-backups/xdg-ptbr').is_dir()

assert (root/'corrigir-lxqt-instalado-2.2.0.sh').is_file()
