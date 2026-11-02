#!/usr/bin/env python3
"""Regressoes nao destrutivas: bandeja na VM, multi-monitor e locais PCManFM-Qt."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import importlib.util
import configparser

ROOT=Path(__file__).resolve().parents[1]
def load(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
setup=load('wolf_panel_places',ROOT/'tools/lxqt/configurar.py')
dyn=load('wolf_monitors',ROOT/'tools/lxqt/wolf_lxqt_monitors.py')
# QSettings é validado em execução no LXQt; o teste não usa bibliotecas Qt reais.
qt_state={'names':['panel1']}
dyn._qt_panels=lambda panel: (qt_state['names'], 'list')
def fake_write(panel, ids): qt_state['names']=[f'panel{i}' for i in range(1,len(ids)+1)]
dyn._qt_write_panels=fake_write

with TemporaryDirectory() as directory:
    home=Path(directory)/'wolf'
    config=home/'.config'
    data=home/'.local/share'
    # /home preservado: favorito externo e item velho Dolphin no quicklaunch.
    bookmarks=config/'gtk-3.0/bookmarks'
    bookmarks.parent.mkdir(parents=True,exist_ok=True)
    bookmarks.write_text('file:///mnt/share Compartilhamento\n',encoding='utf-8')
    (config/'user-dirs.dirs').write_text('XDG_DOCUMENTS_DIR="$HOME/Documentos"\n'
                                       'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n'
                                       'XDG_PICTURES_DIR="$HOME/Imagens"\n'
                                       'XDG_MUSIC_DIR="$HOME/Música"\n'
                                       'XDG_VIDEOS_DIR="$HOME/Vídeos"\n',encoding='utf-8')
    panel=config/'lxqt/panel.conf'
    panel.parent.mkdir(parents=True,exist_ok=True)
    panel.write_text('panels=panel1,panel2\n[panel1]\nplugins=quick1\n[quick1]\napps\\1\\desktop=/usr/share/applications/org.kde.dolphin.desktop\n',encoding='utf-8')
    with patch.object(setup,'HOME',home),patch.object(setup,'CONFIG',config),\
         patch.object(setup,'DATA',data),patch.object(setup,'BASE',home/'wolf-backups/lxqt'),\
         patch.object(setup,'desktop_file',lambda names: (Path('/usr/share/applications')/names[0]) if names[0]=='pcmanfm-qt.desktop' else None),\
         patch.object(setup.shutil,'which',return_value=None):
        inst=setup.Installer()
        setup.setup_panel(inst,1)
        setup.setup_monitor_autostart(inst)
        setup.setup_pcmanfm_places(inst)
        saved=inst.complete()
        raw=panel.read_text(encoding='utf-8')
        assert raw.startswith('panels=panel1\n'),raw[:100]
        assert 'plugins=menu1,quick1,tasks1,status1,tray1,volume1,clock1,showdesktop1' in raw
        assert '[panel2]' in raw and 'plugins=menu2,quick2,tasks2,clock2,showdesktop2' in raw
        assert 'type=statusnotifier' in raw and 'type=tray' in raw
        assert 'org.kde.dolphin.desktop' not in raw
        assert 'pcmanfm-qt.desktop' in raw
        assert '--session' in (config/'autostart/wolf-lxqt-monitors.desktop').read_text()
        lines=bookmarks.read_text(encoding='utf-8').splitlines()
        assert lines==[
            'file://'+str(home)+'/Documentos Documentos',
            'file://'+str(home)+'/Downloads Downloads',
            'file://'+str(home)+'/Imagens Imagens',
            'file://'+str(home)+'/M%C3%BAsica Músicas',
            'file://'+str(home)+'/V%C3%ADdeos Vídeos',
            'file:///mnt/share Compartilhamento',
        ],lines
        assert all((home/p).is_dir() for p in ('Documentos','Downloads','Imagens','Música','Vídeos'))
        assert dyn.monitors('Monitors: 1\n 0: +*Virtual-1 800/200x600/150+0+0 Virtual-1')==(0,None)
        assert dyn.monitors('Monitors: 2\n 0: +DP-0 1920/500x1080/300+0+0 DP-0\n 1: +*HDMI-0 1920/500x1080/300+1920+0 HDMI-0')==(1,0)
        assert dyn.apply(panel,counts=(0,None)) is False
        assert dyn.apply(panel,counts=(1,0)) is True
        dual=panel.read_text()
        assert dual.startswith('panels=panel1,panel2\n')
        assert dyn.root_panels_entries(dual)==['panel1,panel2']
        assert '[panel1]\n' in dual and 'desktop=1' in dual
        assert '[panel2]\n' in dual and 'desktop=0' in dual
        assert dyn.apply(panel,counts=(1,0)) is False, 'idempotencia'
        assert dyn.apply(panel,counts=(0,None)) is True
        assert panel.read_text().startswith('panels=panel1\n')
        setup.setup_pcmanfm_places(inst)
        assert bookmarks.read_text(encoding='utf-8').splitlines()==lines
        assert (saved/'original/.config/lxqt/panel.conf').is_file()

installer=(ROOT/'install/wolf-install.sh').read_text()
assert '--telas 1 --wallpaper' in installer
assert 'wolf_lxqt_monitors.py' in installer and '/mnt/usr/local/bin/wolf-lxqt-monitors' in installer
print('[OK] Painel principal com tray, desktop primario, favoritos XDG, backup e idempotencia')
