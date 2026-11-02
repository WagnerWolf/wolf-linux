#!/usr/bin/env python3
"""Teste não destrutivo da bandeja de rede LXQt; não acessa interfaces reais."""
import configparser
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('wolf_lxqt_network', ROOT/'tools/lxqt/configurar.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_manifest():
    packages = (ROOT/'package-profiles/packages.conf').read_text(encoding='utf-8')
    installer = (ROOT/'install/wolf-install.sh').read_text(encoding='utf-8')
    smoke = (ROOT/'tests/wolf-smoke-test.sh').read_text(encoding='utf-8')
    assert 'networkmanager networkmanager-openvpn' in packages
    assert 'network-manager-applet nm-connection-editor' in packages
    assert 'networkmanager network-manager-applet nm-connection-editor' in installer
    assert '/mnt/usr/bin/nm-applet' in installer
    assert '/mnt/usr/bin/nm-connection-editor' in installer
    assert 'NetworkManager.service bluetooth.service sddm.service' in installer
    assert 'setup_network_tray(inst)' in (ROOT/'tools/lxqt/configurar.py').read_text()
    assert 'wolf-test-network-tray.py' in smoke


def test_xdg_autostart_override():
    with TemporaryDirectory() as temp:
        home = Path(temp)/'wolf'
        config = home/'.config'
        original = config/'autostart/nm-applet.desktop'
        original.parent.mkdir(parents=True)
        # Simula usuario com /home preservado e applet legado desativado.
        legacy = '[Desktop Entry]\nType=Application\nHidden=true\nExec=nm-applet\n'
        original.write_text(legacy, encoding='utf-8')
        with patch.object(module,'HOME',home), patch.object(module,'CONFIG',config), \
             patch.object(module,'DATA',home/'.local/share'), \
             patch.object(module,'BASE',home/'wolf-backups/lxqt'):
            inst = module.Installer()
            module.setup_network_tray(inst)
            backup = inst.complete()
            text = original.read_text(encoding='utf-8')
            parser = configparser.RawConfigParser(interpolation=None)
            parser.read_string(text)
            entry = parser['Desktop Entry']
            assert entry['Exec'] == 'nm-applet --indicator'
            assert entry['TryExec'] == 'nm-applet'
            assert entry['OnlyShowIn'] == 'LXQt;'
            assert entry['X-LXQt-Need-Tray'] == 'true'
            assert entry.get('Hidden', 'false').lower() == 'false'
            assert not (config/'autostart/wolf-nm-applet.desktop').exists()
            # O MESMO basename do autostart do pacote: nao inicia duas copias.
            assert original.name == 'nm-applet.desktop'
            manifest = json.loads((backup/'manifest.json').read_text())
            assert any(x['path']=='.config/autostart/nm-applet.desktop' and x['existed']
                       for x in manifest)
            assert (backup/'original/.config/autostart/nm-applet.desktop').read_text() == legacy
            module.restore(backup)
            assert original.read_text() == legacy


def test_clean_home_and_panel():
    with TemporaryDirectory() as temp:
        home = Path(temp)/'wolf'
        config = home/'.config'
        with patch.object(module,'HOME',home), patch.object(module,'CONFIG',config), \
             patch.object(module,'DATA',home/'.local/share'), \
             patch.object(module,'BASE',home/'wolf-backups/lxqt'), \
             patch.object(module,'desktop_file',lambda x: None):
            inst=module.Installer()
            module.setup_network_tray(inst)
            module.setup_panel(inst,2)
            backup=inst.complete()
            text=(config/'autostart/nm-applet.desktop').read_text()
            assert 'Exec=nm-applet --indicator' in text
            assert 'OnlyShowIn=LXQt;' in text
            panel=(config/'lxqt/panel.conf').read_text()
            assert 'statusnotifier' in panel and 'tray' in panel
            assert 'panel1' in panel and 'panel2' in panel
            module.restore(backup)
            assert not (config/'autostart/nm-applet.desktop').exists()


if __name__ == '__main__':
    test_manifest()
    test_xdg_autostart_override()
    test_clean_home_and_panel()
    print('[OK] Rede LXQt: pacotes oficiais, serviço existente, indicador único, backup e restauração')
