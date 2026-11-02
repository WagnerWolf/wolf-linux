#!/usr/bin/env python3
"""Regressão isolada da migração Dolphin → PCManFM-Qt; não toca na home real."""
import argparse
import configparser
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/lxqt/configurar.py'
spec = importlib.util.spec_from_file_location('wolf_pcmanfm_setup', SOURCE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def ini(file):
    parser = configparser.RawConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    data = file.read_text(encoding='utf-8')
    if file.name == 'panel.conf' and not data.lstrip().startswith('['):
        data = '[DEFAULT]\n' + data
    parser.read_string(data)
    return parser


def test_shortcut():
    ns = 'http://openbox.org/3.4/rc'
    root = ET.fromstring(f'<openbox_config xmlns="{ns}"><keyboard><keybind key="W-e"><action name="Execute"><command>dolphin</command></action></keybind></keyboard></openbox_config>')
    module.add_shortcut(root, 'W-e', 'pcmanfm-qt')
    module.add_shortcut(root, 'W-e', 'pcmanfm-qt')
    binds = root.findall(f'{{{ns}}}keyboard/{{{ns}}}keybind')
    assert len(binds) == 1
    assert binds[0].find(f'{{{ns}}}action/{{{ns}}}command').text == 'pcmanfm-qt'


def test_configure(with_code):
    with TemporaryDirectory() as temporary:
        home = Path(temporary) / 'wolf'
        home.mkdir()
        config = home / '.config'
        config.mkdir()
        data = home / '.local/share'
        old_kio = data / 'kio/servicemenus/wolf-open-vscode.desktop'
        old_kio.parent.mkdir(parents=True)
        old_text = '[Desktop Entry]\nX-KDE-ServiceTypes=KonqPopupMenu/Plugin\nActions=wolfOpenVSCode;\n'
        old_kio.write_text(old_text)
        mime = config/'mimeapps.list'
        mime.write_text('''[Default Applications]
inode/directory=org.kde.dolphin.desktop;
text/plain=custom-editor.desktop;

[Added Associations]
inode/directory=org.kde.dolphin.desktop;

[Removed Associations]
inode/directory=pcmanfm-qt.desktop;org.kde.dolphin.desktop;
''')
        legacy_action = data / 'file-manager/actions/wolf-open-vscode.desktop'
        legacy_action.parent.mkdir(parents=True)
        legacy_action.write_text('[Desktop Entry]\nProfiles=wolf-vscode;\n')
        folder = Path(temporary) / 'apps'
        folder.mkdir()
        for name in ('pcmanfm-qt.desktop', 'org.kde.konsole.desktop', 'org.kde.kate.desktop', 'google-chrome.desktop'):
            (folder/name).write_text('[Desktop Entry]\nType=Application\nExec=/bin/true\n')
        wallpaper = Path(temporary) / 'wall.png'
        wallpaper.write_bytes(b'fake png')

        def fake_desktop(candidates):
            return next((folder/name for name in candidates if (folder/name).is_file()), None)
        original_which = module.shutil.which
        def which(cmd):
            if cmd == 'code':
                return '/usr/bin/code' if with_code else None
            return original_which(cmd)
        args = argparse.Namespace(screens=1, wallpaper=str(wallpaper), icon=None, alttab_monitor=False)
        with (patch.object(module, 'HOME', home), patch.object(module, 'CONFIG', config),
              patch.object(module, 'DATA', data), patch.object(module, 'BASE', home/'wolf-backups/lxqt'),
              patch.object(module, 'desktop_file', fake_desktop),
              patch.object(module, 'setup_openbox', lambda *a: None),
              patch.object(module.os, 'geteuid', lambda: 1000),
              patch.object(module.shutil, 'which', which)):
            module.configure(args)
        after=ini(mime)
        assert after['Default Applications']['inode/directory']=='pcmanfm-qt.desktop;'
        assert after['Added Associations']['inode/directory']=='pcmanfm-qt.desktop;'
        assert 'pcmanfm-qt.desktop;' not in after['Removed Associations'].get('inode/directory','')
        assert after['Default Applications']['text/plain']=='org.kde.kate.desktop;'
        session=ini(config/'lxqt/session.conf')
        assert session['DefaultApplications']['fileManager']=='pcmanfm-qt'
        shortcut=ini(config/'lxqt/globalkeyshortcuts.conf')
        assert shortcut['Control%2BAlt%2BE.6']['Exec']=='pcmanfm-qt'
        panel=(config/'lxqt/panel.conf').read_text()
        assert 'pcmanfm-qt.desktop' in panel
        assert 'dolphin' not in panel.lower()
        assert not old_kio.exists()
        action = data/'file-manager/actions/wolf-open-vscode.desktop'
        assert action.exists()==with_code
        if with_code:
            assert 'MimeTypes=inode/directory;' in action.read_text()
            assert 'Exec=wolf-open-vscode-monitor %f' in action.read_text()
        backups = sorted((home/'wolf-backups/lxqt').iterdir())
        assert len(backups)==1
        backup = backups[0]
        manifest=json.loads((backup/'manifest.json').read_text())
        assert any(item['path']=='.local/share/kio/servicemenus/wolf-open-vscode.desktop' for item in manifest)
        assert (backup/'original/.local/share/kio/servicemenus/wolf-open-vscode.desktop').read_text()==old_text
        assert (backup/'original/.config/mimeapps.list').is_file()


def main():
    test_shortcut()
    test_configure(True)
    test_configure(False)
    print('[OK] PCManFM-Qt: atalho, painéis, MIME, VS Code condicional e backup /home (com/sem Development)')


if __name__ == '__main__':
    main()
