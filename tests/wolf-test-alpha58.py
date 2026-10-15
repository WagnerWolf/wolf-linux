#!/usr/bin/env python3
"""Regression contracts for single GUI, Vulkan provider sequencing, UEFI ESP safety."""
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
class Alpha58(unittest.TestCase):
    def test_single_gui(self):
        s=(ROOT/'live-gui/preview/app.py').read_text()
        self.assertIn('self.continue_button.hide()  # apenas o botão',s)
        self.assertNotIn("flag = text_label('INSTALAÇÃO REAL",s)
        self.assertNotIn('launch_classic_installer',s)
        stage=(ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
        self.assertNotIn('install -Dm0755 "$SOURCE/wolf-live-installer-classic"',stage)
        self.assertIn('rm -f "$AIROOT/usr/local/bin/wolf-live-installer-classic"',stage)
    def test_space_advisory_only(self):
        s=(ROOT/'live-gui/preview/app.py').read_text()
        for token in ("'minimal': (25, 35)","'test': (40, 60)","'full': (75, 110)", 'def update_profile_space(self):'):
            self.assertIn(token,s)
        self.assertNotIn('raise PreviewError',s[s.index('    def update_profile_space(self):'):s.index('    def update_state(self, *_)')])
    def test_vulkan_before_optional_gaming(self):
        s=(ROOT/'install/wolf-install.sh').read_text()
        self.assertLess(s.index('stage "63b-vulkan" install_preferred_vulkan_provider'),s.index('stage "64-resolver-stacks" install_selected_stack_packages'))
        for a,b in [('virtio','vulkan-virtio'),('intel','vulkan-intel'),('amd','vulkan-radeon'),('virtualbox|generic','vulkan-swrast'),('nvidia-modern','nvidia-utils')]:
            self.assertIn(a+') providers+=('+b,s)
        self.assertIn('stack_selected gaming || return 0',s)
    def test_efi_fallback_respects_existing(self):
        s=(ROOT/'install/wolf-install.sh').read_text()
        self.assertIn("if [[ \"$FORMAT_ESP\" == 'yes' || ! -e \"$fallback_path\" ]]; then",s)
        self.assertIn('--removable',s)
        self.assertIn('[[ -s /mnt/boot/efi/EFI/WolfLinux/grubx64.efi ]]',s)
        self.assertIn('findmnt -rn --mountpoint /mnt/boot/efi',s)
if __name__=='__main__': unittest.main(verbosity=2)
