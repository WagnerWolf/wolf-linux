#!/usr/bin/env python3
"""Release: sem operações de disco ou de pacman; valida caminho do menu e controle."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.machinery, importlib.util
from unittest.mock import patch
R=Path(__file__).resolve().parents[1]
def content(rel):return (R/rel).read_text()
formatter=content('tools/lxqt/wolf-format-removable')
assert "group.add_argument('--device'" in formatter
assert "candidate = _find_candidate(args.device)" in formatter
assert "return gui(initial=candidate['device'])" in formatter
assert "'ntfs'" in formatter and 'UDisks2' in formatter
assert "inst.write(DATA/'file-manager/actions/wolf-format-removable.desktop'" not in content('tools/lxqt/configurar.py').split('def setup_removable_media(inst):')[1].split('def setup_lxqt_settings_icon')[0]
assert 'inst.remove_file(old_action)' in content('tools/lxqt/configurar.py')
assert 'rm -- "$ACTION"' in content('atualizar-paineis-pastas-control-center.sh')
assert 'wolf-format-removable --format %f' not in content('install/wolf-install.sh')[content('install/wolf-install.sh').index('install_wolf_libfm_usb_package()'):]
cc=content('tools/control-center/main.py')
assert 'Verificar integrações Wolf' in cc and 'Abrir formatador USB' in cc
assert '_check_integrations' in cc
assert 'install_wolf_libfm_usb_package' in content('install/wolf-install.sh')
assert 'stage "69d3-formato-usb-menu-wolf"' in content('install/wolf-install.sh')
assert 'validar-pacote-usb.sh' in content('gerar-iso-2.2.0.sh')
assert 'release-packages' in content('tests/wolf-customize-iso-profile.sh')
assert "'QT_STYLE_OVERRIDE':'Fusion'" in content('tools/lxqt/configurar.py')
assert '90-wolf-libfm-integration.hook' in content('install/wolf-install.sh')
print('[OK] Release USB: menu exclusivo da unidade, formatador --device, Control Center, hook e ISO com pacote validado')
