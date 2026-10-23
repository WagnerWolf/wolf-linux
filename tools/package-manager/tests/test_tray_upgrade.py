"""Contrato do atalho de atualização da bandeja (sem Qt nem transações)."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from wolfpkg.tray_policy import tray_upgrade_state


class TrayUpgradePolicyTests(unittest.TestCase):
    def test_no_update_disables(self):
        state = tray_upgrade_state(0, True, False)
        self.assertFalse(state.enabled)
        self.assertEqual(state.label, 'Atualizar sistema')

    def test_updates_enable_with_count(self):
        state = tray_upgrade_state(7, True, False)
        self.assertTrue(state.enabled)
        self.assertEqual(state.label, 'Atualizar sistema (7)')

    def test_partial_results_must_not_enable(self):
        self.assertFalse(tray_upgrade_state(7, False, False).enabled)

    def test_check_or_operation_blocks_action(self):
        self.assertFalse(tray_upgrade_state(7, True, True).enabled)

    def test_actual_action_reuses_safe_upgrade_flow(self):
        source=(Path(__file__).resolve().parents[1]/'wolfpkg/app.py').read_text()
        self.assertIn('self.tray_upgrade_action.triggered.connect(self.upgrade_from_tray)', source)
        self.assertIn('self.open_page(0)\n        self.start_upgrade()', source)
        self.assertIn('self._updates_valid = not bool(errors)', source)
        self.assertIn('self._updates_valid = False  # qualquer transação', source)
        self.assertIn('self.checker.finished.connect(self._sync_tray_upgrade_action)', source)
        self.assertIn('upgrade_commands(self.prefs.aur_automatic)', source)

if __name__=='__main__':
    unittest.main()
