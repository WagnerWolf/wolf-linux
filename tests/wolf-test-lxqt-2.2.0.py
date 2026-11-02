#!/usr/bin/env python3
from pathlib import Path
import re, ast, subprocess, sys
r=Path(__file__).resolve().parents[1]
installer=(r/'install/wolf-install.sh').read_text()
pkg=(r/'package-profiles/packages.conf').read_text()
assert (r/'VERSION').read_text().strip() == '2.2.0'
assert 'DESKTOP="lxqt"' in installer
# Regression: 2.2 stable identity check must match generated os-release.
identity = installer.split('configure_wolf_identity() {',1)[1].split('preflight_preserved_home_identity() {',1)[0]
assert 'PRETTY_NAME="Wolf Linux 2.2"' in identity
assert 'grep -Fxq' in identity and 'PRETTY_NAME="Wolf Linux 2.2"' in identity
assert 'VERSION_ID=' in identity and '${WOLF_VERSION}' in identity
assert 'Wolf Linux 2.1' not in identity
ui = (r/'live-gui/preview/app.py').read_text()
assert 'Minimal — LXQt essencial' in ui and 'Base LXQt 25–35 GiB' in ui
assert 'Minimal — KDE essencial' not in ui and 'Base KDE' not in ui
assert 'printf \'%s' in installer # preserve packages array routing
assert '"${LXQT_PACKAGES[@]}"' in installer
assert 'stage "63a-kernel-arch" validate_official_arch_kernel' in installer
assert 'stage "69d2-wolf-lxqt" install_wolf_lxqt_profile' in installer
assert 'stage "69c2-lxqt-base" validate_lxqt_base' in installer
assert 'stage "69d-helpers-primeiro-login" install_wolf_helper_bundle' in installer
assert installer.index('stage "69d-helpers-primeiro-login"') < installer.index('stage "69d2-wolf-lxqt"')
assert 'FORMAT_ROOT=yes; FORMAT_ESP=no; FORMAT_HOME=no; CLEAN_HOME_DOTFILES=no' in installer
assert 'preflight_preserved_home_identity' in installer and 'reconcile_preserved_home_access' in installer
assert 'revalidate_gui_physical_target' in installer
assert 'chown -R "$USERNAME_VALUE:$USERNAME_VALUE" "$userhome/.config/openbox"' not in installer
assert 'linux-lts linux-lts-headers linux linux-headers' in pkg
assert 'LXQT_PACKAGES=(' in pkg and 'lxqt-session lxqt-panel' in pkg
assert 'pcmanfm-qt' in pkg and 'dolphin' not in pkg
assert 'network-manager-applet nm-connection-editor' in pkg
assert 'networkmanager network-manager-applet nm-connection-editor' in installer
assert all(x in pkg for x in ('gvfs gvfs-mtp udisks2-lvm2', 'lxqt-archiver'))
assert 'lxqt-archiver' in pkg and 'python-xlib tk' in pkg
assert 'openbox' in pkg and 'pyside6' in pkg
assert 'OnlyShowIn=LXQt;' in installer
assert 'GRUB_TOP_LEVEL=' in installer and 'local main_kernel="linux"' in installer
assert 'kernels=(linux-lts linux)' in installer
assert 'Session=lxqt.desktop' in installer
assert '"${configure[@]}"' in installer
assert 'promover-alt-tab.py' in installer
for fn in ('configurar.py','alt_tab_visual.py','promover-alt-tab.py','super_menu_monitor.py'):
    ast.parse((r/'tools/lxqt'/fn).read_text(), filename=fn)
for fn in ('main.py','backend.py','wolf_profile.py','monitor_editor.py','monitor_layout.py','lxqt_support.py'):
    ast.parse((r/'tools/control-center'/fn).read_text(), filename=fn)
assert "io.github.mpc_qt.mpc-qt.desktop" in (r/'tools/control-center/wolf_profile.py').read_text()
assert "io.github.mpc_qt.mpc-qt.desktop" in (r/'tools/lxqt/configurar.py').read_text()
assert "lxqt-archiver.desktop" in (r/'tools/lxqt/configurar.py').read_text()
for fn in ('tests/wolf-build-iso.sh','tests/wolf-customize-iso-profile.sh','tests/wolf-stage-live-ssh.sh'):
    assert (r/fn).is_file()
assert 'LXQt/X11 Clean Baseline' in (r/'preparar_ambiente_wolf_linux.sh').read_text()
assert 'LXQt/X11 Clean Baseline' in (r/'tests/wolf-customize-iso-profile.sh').read_text()
assert '0.3.5' in (r/'tools/package-manager/README.md').read_text()
print('[OK] Manifesto LXQt + kernel oficial/LTS + Control Center + MIME MPC-QT + /home preservada')
