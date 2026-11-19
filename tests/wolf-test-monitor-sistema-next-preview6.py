#!/usr/bin/env python3
from pathlib import Path
import re, unittest, subprocess, tempfile, os
ROOT=Path(__file__).resolve().parents[1]
class WolfMonitorTests(unittest.TestCase):
    def test_official_lxqt_package(self):
        data=(ROOT/'package-profiles/packages.conf').read_text()
        pack=re.search(r'LXQT_PACKAGES=\((.*?)\)', data, re.S).group(1)
        self.assertRegex(pack,r'(?m)^\s+gnome-system-monitor\s')
        self.assertNotIn('qps ',pack)
        self.assertIn('btop',data)
    def test_override(self):
        s=(ROOT/'tools/lxqt/99-wolf-system-monitor.gschema.override').read_text()
        self.assertIn('[org.gnome.gnome-system-monitor.proctree]',s)
        self.assertRegex(s,r'(?m)^sort-col=0$')
        self.assertRegex(s,r'(?m)^sort-order=0$')
        self.assertIn('[org.gnome.desktop.interface]', s)
        self.assertRegex(s,r"(?m)^color-scheme='prefer-dark'$")
    def test_install_stage(self):
        s=(ROOT/'install/wolf-install.sh').read_text()
        self.assertIn('arch-chroot /mnt glib-compile-schemas /usr/share/glib-2.0/schemas',s)
        self.assertIn('99-wolf-system-monitor.gschema.override',s)
    def test_helper_syntax_and_safety(self):
        path=ROOT/'tools/lxqt/wolf-monitor-sistema-instalar.sh'
        subprocess.run(['bash','-n',str(path)],check=True)
        s=path.read_text()
        self.assertIn('sudo pacman -S --needed gnome-system-monitor',s)
        self.assertNotIn('pacman -R',s)
        self.assertIn('--restore',s)
        self.assertIn('color-original.conf',s)
        self.assertIn("color-scheme 'prefer-dark'",s)
        self.assertNotIn('GTK_THEME=',s)
    def test_existing_integration_unchanged(self):
        self.assertTrue((ROOT/'tools/lxqt/responsividade/wolf-alt-tab-daemon.py').is_file())
        self.assertTrue((ROOT/'tools/lxqt/wolf-responsividade-instalar.py').is_file())
if __name__=='__main__': unittest.main(verbosity=2)
