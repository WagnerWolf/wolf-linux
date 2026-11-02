"""Transações simuladas, sem pacman, sem rede, sem modificar /etc."""
import subprocess
import unittest
from unittest.mock import patch
from wolfpkg import upgrade_guard as G


def cp(args, out='', rc=0):
    return subprocess.CompletedProcess(args, rc, out, '')

class GuardProbeTests(unittest.TestCase):
    def test_custom_guarded(self):
        with patch.object(G, '_run', side_effect=[cp([], 'libfm-qt 2.4.0-4.1\n'), cp([], 'libfm-qt\n'), cp([], 'Repository : extra\nVersion : 2.4.1-1\n')]):
            result = G.probe()
            self.assertTrue(result.wolf_active and result.protected and result.safe_for_system_update)
            self.assertEqual(result.available, '2.4.1-1')
    def test_custom_unprotected_blocks_upgrades(self):
        with patch.object(G, '_run', side_effect=[cp([], 'libfm-qt 2.4.0-4.1'), cp([], '', 1)]):
            result = G.probe()
            self.assertFalse(result.safe_for_system_update)
            self.assertTrue(result.wolf_active)
    def test_missing_pacman_fail_closed(self):
        with patch.object(G, '_run', return_value=None):
            self.assertFalse(G.probe().safe_for_system_update)
    def test_normal_library_no_custom_block(self):
        with patch.object(G, '_run', return_value=cp([], 'libfm-qt 2.4.1-1')):
            self.assertTrue(G.probe().safe_for_system_update)
    def test_detect_repo_newer(self):
        state = G.Protection('2.4.0-4.1', True, True, '2.4.1-1')
        with patch.object(G, '_run', return_value=cp([], '1\n')):
            self.assertTrue(G.newer_repo_available(state))
        with patch.object(G, '_run', return_value=cp([], '-1\n')):
            self.assertFalse(G.newer_repo_available(state))

if __name__ == '__main__':
    unittest.main()
