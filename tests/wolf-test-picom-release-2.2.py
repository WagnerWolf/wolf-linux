#!/usr/bin/env python3
"""Teste de regressão: Picom é o compositor padrão do Wolf LXQt 2.2.0."""
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
configfile=ROOT/'tools/lxqt/configurar.py'
spec=importlib.util.spec_from_file_location('wolf_lxqt_picom_release',configfile)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
installer=configfile.read_text(encoding='utf-8')
appearance=(ROOT/'tools/lxqt/wolf-appearance-dark').read_text(encoding='utf-8')
manifest=(ROOT/'package-profiles/packages.conf').read_text(encoding='utf-8')
assert 'openbox obconf-qt picom' in manifest
assert 'setup_picom_config(inst)' in installer
assert 'setup_picom_autostart(inst)' in installer
assert 'LXQtPanel #BackgroundWidget { background: #242a34; }' in module.THEME_QSS
assert 'runpy.run_path(str(source))' in appearance
assert "'lxqt-panel.qss':colors['THEME_QSS']" in appearance
assert 'backend = "glx";' in module.PICOM_CONF
assert 'vsync = true;' in module.PICOM_CONF
assert 'shadow = false;' in module.PICOM_CONF
assert 'fading = false;' in module.PICOM_CONF
assert 'OnlyShowIn=LXQt;' in module.PICOM_AUTOSTART
assert 'Exec=picom' in module.PICOM_AUTOSTART
assert 'TryExec=picom' in module.PICOM_AUTOSTART

with TemporaryDirectory() as temp:
    home=Path(temp)
    config=home/'.config'
    with patch.object(module,'HOME',home),patch.object(module,'CONFIG',config),patch.object(module,'BASE',home/'wolf-backups/lxqt'):
        inst=module.Installer()
        module.setup_picom_config(inst)
        module.setup_picom_autostart(inst)
        conf=config/'picom/picom.conf'
        auto=config/'autostart/wolf-picom.desktop'
        assert conf.read_text()==module.PICOM_CONF
        assert auto.read_text()==module.PICOM_AUTOSTART
        # Preservar /home reutilizada sem forçar perfil ou autostart novos.
        conf.write_text('# personalizado pelo usuário\nbackend = "xrender";\n')
        auto.write_text('[Desktop Entry]\nType=Application\nExec=false\nHidden=true\n')
        inst2=module.Installer()
        module.setup_picom_config(inst2)
        module.setup_picom_autostart(inst2)
        assert 'xrender' in conf.read_text()
        assert 'Hidden=true' in auto.read_text()
        assert not inst2.manifest
        # Em /home novo o script dá opção de rollback dos arquivos criados.
        inst3=module.Installer()
        conf.unlink();auto.unlink()
        module.setup_picom_config(inst3)
        module.setup_picom_autostart(inst3)
        snapshot=inst3.complete()
        assert snapshot.is_dir()
        assert len(inst3.manifest)==2
print('[OK] Picom release: GLX/VSync + Wolf-dark opaco, autostart LXQt e /home preservada')
