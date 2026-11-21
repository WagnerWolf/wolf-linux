"""Regressões da separação Plasma/LXQt; não executa Pacman/Yay nem requer Qt."""
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch
from wolfpkg.desktop_profile import is_plasma, needs_libfm_guard
from wolfpkg.upgrade_flow import should_confirm_aur_stage
from wolfpkg import upgrade_guard, integrations, backend

class KDEYayPreviewTests(unittest.TestCase):
    def test_plasma_detects_colon_desktops(self):
        self.assertTrue(is_plasma({'XDG_CURRENT_DESKTOP':'KDE:plasma'}))
        self.assertFalse(needs_libfm_guard({'XDG_CURRENT_DESKTOP':'KDE'}))
    def test_lxqt_keeps_guard(self):
        self.assertTrue(needs_libfm_guard({'XDG_CURRENT_DESKTOP':'LXQt'}))
        self.assertTrue(needs_libfm_guard({}))
    def test_missing_libfm_is_not_an_error(self):
        with patch.object(upgrade_guard, '_run', return_value=subprocess.CompletedProcess([],1,'','error: package not found')):
            self.assertTrue(upgrade_guard.probe().safe_for_system_update)
    def test_unreadable_libfm_remains_failure(self):
        with patch.object(upgrade_guard, '_run', return_value=None):
            self.assertFalse(upgrade_guard.probe().safe_for_system_update)
    def test_kde_integration_page_does_not_probe_lxqt(self):
        with patch.object(integrations, 'is_plasma', return_value=True), \
             patch.object(integrations, 'check_libfm', side_effect=AssertionError('legacy called')), \
             patch.object(integrations, 'check_kde_integrations', return_value=[]) as audit:
            self.assertEqual(integrations.check_all(), [])
            audit.assert_called_once()
    def test_pacman_then_yay_no_sudo_yay(self):
        cmd=backend.upgrade_commands()
        self.assertEqual(cmd[0][:4], ('sudo','-A','pacman','-Syu'))
        self.assertEqual(cmd[1][:3], ('yay','-Sua','--aur'))
        self.assertNotIn('sudo',cmd[1])
    def test_confirmation_is_only_in_update_complete(self):
        txt=(Path(__file__).resolve().parents[2]/'tools/package-manager/wolfpkg/app.py').read_text()
        self.assertIn('should_confirm_aur_stage(self.plan_label, self.stage, len(self.running_plan))', txt)
        self.assertTrue(should_confirm_aur_stage('Atualização completa',0,2))
        self.assertFalse(should_confirm_aur_stage('Instalação de pacotes',0,2))
        self.assertFalse(should_confirm_aur_stage('Atualização completa',1,2))
        self.assertFalse(should_confirm_aur_stage('Atualização completa',0,1))
        self.assertIn("'Atualizar pacotes AUR com yay?'",txt)
        self.assertIn('if not needs_libfm_guard():\n            return True',txt)
        self.assertIn('wolf-package-manager-{"preview-"',txt)
    def test_reversible_system_deploy_has_backup(self):
        txt=(Path(__file__).resolve().parents[1]/'wolf-pm1-deploy-fixture.py').read_text()
        self.assertIn('def backup(',txt)
        self.assertIn('run_undo(',txt)

if __name__=='__main__': unittest.main()
