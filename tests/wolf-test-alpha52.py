#!/usr/bin/env python3
"""GUI alpha52: read-only, staging, regressions and launcher isolation."""
from pathlib import Path
import ast
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parent.parent
PREVIEW = ROOT / 'live-gui' / 'preview'
MAIN = PREVIEW / 'app.py'
PLANNER = PREVIEW / 'planner.py'

class Alpha52(unittest.TestCase):
    def test_pyside_preview_is_parseable(self):
        ast.parse(MAIN.read_text())
        ast.parse(PLANNER.read_text())

    def test_preview_has_separate_execution_bridge(self):
        s = MAIN.read_text()
        for cmd in ('mkfs.', 'wipefs', 'sgdisk', 'parted --script', '--execute-multidisk-physical'):
            self.assertNotIn(cmd, s)
        self.assertIn("button('Confirmar'", s)
        self.assertIn('check_vm_plan(current)', s)
        self.assertIn('setWordWrap(wrap)', s)
        self.assertIn('availableGeometry()', s)
        self.assertNotIn('launch_classic_installer', s)  # alpha58: único instalador visível

    def test_launcher_points_to_preview_and_classic_is_isolated(self):
        root = ROOT / 'live-gui'
        launcher = (root / 'wolf-live-installer').read_text()
        classic = (root / 'wolf-live-installer-classic').read_text()
        self.assertIn('/preview/app.py', launcher)
        self.assertIn('/gui/main.py', classic)
        self.assertNotIn('/gui/main.py', launcher)

    def test_stager_transports_both_entrypoints(self):
        text = (ROOT / 'tests/wolf-stage-live-desktop.sh').read_text()
        for s in ('preview/app.py', 'preview/planner.py', 'preview/vm_bridge.py'):
            self.assertIn(s, text)
        self.assertNotIn('install -Dm0755 "$SOURCE/wolf-live-installer-classic"', text)
        self.assertIn('wolf-live-installer', (ROOT/'live-gui/home/.config/openbox/autostart').read_text())

    def test_planner_test_is_clean(self):
        result = subprocess.run([sys.executable, str(ROOT/'tests/wolf_test_alpha52_planner.py'), '-q'],
                                cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout[-4000:])

if __name__ == '__main__':
    unittest.main(verbosity=2)
