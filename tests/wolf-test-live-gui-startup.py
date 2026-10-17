#!/usr/bin/env python3
"""Evita falhas de importação que derrubam a janela antes do primeiro frame."""
from pathlib import Path
import ast
import unittest
ROOT = Path(__file__).resolve().parents[1]


class LiveGuiStartup(unittest.TestCase):
    def test_qtextcursor_is_imported_from_qtgui(self):
        source = (ROOT / 'live-gui/preview/app.py').read_text(encoding='utf8')
        tree = ast.parse(source)
        imports = {
            item.module: {alias.name for alias in item.names}
            for item in ast.walk(tree) if isinstance(item, ast.ImportFrom)
            and item.module and item.module.startswith('PySide6.')
        }
        self.assertIn('QTextCursor', imports.get('PySide6.QtGui', set()))
        self.assertNotIn('QTextCursor', imports.get('PySide6.QtWidgets', set()))

    def test_gui_has_non_destructive_runtime_selftest(self):
        source = (ROOT / 'live-gui/preview/app.py').read_text(encoding='utf8')
        self.assertIn("parser.add_argument('--self-test'", source)
        self.assertIn('window = MainWindow(demo_inventory())', source)
        self.assertIn("window.windowTitle() == 'Wolf Linux | Instalador'", source)

    def test_startup_log_and_live_imports(self):
        startup = (ROOT / 'live-gui/home/.config/openbox/autostart').read_text()
        build = (ROOT / 'tests/wolf-build-iso.sh').read_text()
        self.assertIn('.local/state/wolf-linux/live-installer.log', startup)
        self.assertIn('wolf-live-installer --self-test', build)
        self.assertIn('QT_QPA_PLATFORM=offscreen', build)
        self.assertIn('wolf-live-installer', startup)

if __name__ == '__main__':
    unittest.main(verbosity=2)
