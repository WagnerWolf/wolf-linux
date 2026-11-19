#!/usr/bin/env python3
from pathlib import Path
import unittest, subprocess
root=Path(__file__).resolve().parents[1]
class MonitorDarkTests(unittest.TestCase):
    def test_override_system_default_only(self):
        s=(root/'tools/lxqt/99-wolf-system-monitor.gschema.override').read_text()
        self.assertIn('[org.gnome.desktop.interface]\ncolor-scheme=\'prefer-dark\'',s)
        self.assertNotIn('gtk-theme=',s)
        self.assertNotIn('GTK_THEME=',s)
    def test_installer_preserves_previous_backup(self):
        s=(root/'tools/lxqt/wolf-monitor-sistema-instalar.sh').read_text()
        self.assertIn('[[ ! -f "$BACKUP_ROOT/sort-original.conf" ]]', s)
        self.assertIn('[[ ! -f "$BACKUP_ROOT/color-original.conf" ]]', s)
        self.assertIn('restore_original',s)
        self.assertIn('ADW_DISABLE_PORTAL=1 gnome-system-monitor',s)
        subprocess.run(['bash','-n',str(root/'tools/lxqt/wolf-monitor-sistema-instalar.sh')],check=True)
    def test_override_installed_and_compiled_during_lxqt_install(self):
        s=(root/'install/wolf-install.sh').read_text()
        self.assertIn('99-wolf-system-monitor.gschema.override',s)
        self.assertIn('arch-chroot /mnt glib-compile-schemas',s)
if __name__=='__main__': unittest.main(verbosity=2)
