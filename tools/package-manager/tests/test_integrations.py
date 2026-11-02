"""Regressões das integrações Wolf: não modifica o sistema."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from wolfpkg import integrations as I


class IntegrationTests(unittest.TestCase):
    def test_not_installed_not_misreported_as_validated(self):
        with tempfile.TemporaryDirectory() as d, patch.object(I, '_pkg_version', return_value='2.2.0-1'):
            status = I.check_libfm(manifest=Path(d)/'missing.json', pending=Path(d)/'pending')
            self.assertEqual(status.status, 'Pendente')

    def test_untrusted_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as d, patch.object(I, '_pkg_version', return_value='2.2.0-1'), patch.object(I, '_owned_by_libfm', return_value=False):
            path=Path(d)/'manifest.json'
            path.write_text(json.dumps({'package':'libfm-qt','installed_version':'2.2.0-1', 'feature':'places-usb-format', 'validated':True,'build_id':'aaaabbbb'}))
            status = I.check_libfm(manifest=path, pending=Path(d)/'pending')
            self.assertEqual(status.status, 'Revisar')

    def test_version_mismatch_blocks_validation(self):
        with tempfile.TemporaryDirectory() as d, patch.object(I, '_pkg_version', return_value='2.2.1-1'), patch.object(I, '_owned_by_libfm', return_value=True):
            path=Path(d)/'manifest.json'
            path.write_text(json.dumps({'package':'libfm-qt','installed_version':'2.2.0-1', 'feature':'places-usb-format', 'validated':True,'build_id':'aaaabbbb'}))
            status = I.check_libfm(manifest=path, pending=Path(d)/'pending')
            self.assertEqual(status.status, 'Revisar')

    def test_pending_hook_blocks_validation(self):
        with tempfile.TemporaryDirectory() as d, patch.object(I, '_pkg_version', return_value='2.2.0-1'), patch.object(I, '_owned_by_libfm', return_value=True):
            path=Path(d)/'manifest.json'
            pending=Path(d)/'pending';pending.write_text('houve atualização')
            path.write_text(json.dumps({'package':'libfm-qt','installed_version':'2.2.0-1', 'feature':'places-usb-format', 'validated':True,'build_id':'aaaabbbb'}))
            status = I.check_libfm(manifest=path, pending=pending)
            self.assertEqual(status.status, 'Revisar')

    def test_precise_validation_without_pending(self):
        with tempfile.TemporaryDirectory() as d, patch.object(I, '_pkg_version', return_value='2.2.0-1'), patch.object(I, '_owned_by_libfm', return_value=True):
            path=Path(d)/'manifest.json'
            path.write_text(json.dumps({'package':'libfm-qt','installed_version':'2.2.0-1', 'feature':'places-usb-format', 'validated':True,'build_id':'aaaabbbb'}))
            status = I.check_libfm(manifest=path, pending=Path(d)/'pending')
            self.assertEqual(status.status, 'Validada')

    def test_hook_writes_only_event_file(self):
        modulepath = (Path(__file__).resolve().parents[3] / 'experimental/integracoes-wolf/wolf_integration_hook.py')
        spec = importlib.util.spec_from_file_location('wolf_integration_hook', modulepath)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as d:
            f=Path(d)/'nested/libfm-qt.changed'
            module.record(f)
            self.assertIn('transação ALPM',f.read_text())
            self.assertEqual(f.stat().st_mode & 0o777, 0o644)


if __name__ == '__main__':
    unittest.main()
