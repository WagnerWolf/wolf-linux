"""Regressões Qt opcionais (puladas em máquinas sem PySide6).

Não chama GParted nem qualquer programa auxiliar.
"""
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'live-gui' / 'preview'))
try:
    from PySide6.QtWidgets import QApplication
    from app import MainWindow
    from planner import demo_inventory
except ImportError:
    QApplication = None


@unittest.skipIf(QApplication is None, 'PySide6 não instalado neste ambiente')
class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
        cls.app = QApplication.instance() or QApplication(['wolf-installer-p02', '-platform', 'offscreen'])

    def setUp(self):
        self.window = MainWindow(demo_inventory())
        self.window.mode_changed('erase')
        combo = self.window.erase_disk
        combo.setCurrentIndex(combo.findData('/dev/sda'))

    def tearDown(self):
        self.window.close()
        self.window.deleteLater()

    def test_erase_defaults_all_to_root(self):
        w = self.window
        self.assertEqual(w.erase_root.value(), 510)
        self.assertEqual(w.erase_root_slider.value(), 510)
        self.assertIn('Sem alocação: 0 GiB', w.erase_budget_summary.text())

    def test_erase_separate_sizes_and_slider_sync(self):
        w = self.window
        w.erase_home.setCurrentIndex(1)
        self.assertEqual(w.erase_root.value(), 60)
        self.assertIn('/home: 450 GiB', w.erase_budget_summary.text())
        w.erase_root_slider.setValue(100)
        self.assertEqual(w.erase_root.value(), 100)
        self.assertIn('/home: 410 GiB', w.erase_budget_summary.text())
        w.erase_auto_home.setChecked(False)
        w.erase_home_size.setValue(190)
        self.assertEqual(w.erase_home_slider.value(), 190)
        self.assertIn('Sem alocação: 220 GiB', w.erase_budget_summary.text())
        # Alpha56: o perfil não é mais escolhido automaticamente. A
        # distribuição de espaço válida NÃO dispensa a escolha explícita.
        self.assertIsNone(w.preset_combo.currentData())
        self.assertFalse(w.continue_button.isEnabled())
        w.preset_combo.setCurrentIndex(w.preset_combo.findData('minimal'))
        self.assertTrue(w.continue_button.isEnabled())

    def test_profile_required_before_review(self):
        w = self.window
        self.assertIsNone(w.preset_combo.currentData())
        self.assertFalse(w.continue_button.isEnabled())
        for preset in ('minimal', 'test', 'full'):
            index = w.preset_combo.findData(preset)
            self.assertGreater(index, 0)
            w.preset_combo.setCurrentIndex(index)
            self.assertTrue(w.continue_button.isEnabled(), preset)
        w.preset_combo.setCurrentIndex(0)
        self.assertFalse(w.continue_button.isEnabled())

    def test_wrap_and_scroll_in_small_window(self):
        w = self.window
        w.resize(800, 600)
        w.show()
        self.app.processEvents()
        self.assertTrue(w.config_stack.currentWidget().widget().layout() is not None)
        self.assertTrue(w.mode_description.wordWrap())
        self.assertTrue(w.validation_label.wordWrap())
        self.assertGreater(w.config_stack.currentWidget().verticalScrollBar().maximum(), 0)

    def test_no_cross_mode_erase_controls(self):
        w = self.window
        w.mode_changed('manual')
        self.assertIs(w.config_stack.currentWidget().widget(), w.manual_page)
        w.mode_changed('reuse')
        self.assertIs(w.config_stack.currentWidget().widget(), w.reuse_page)


if __name__ == '__main__':
    unittest.main()
