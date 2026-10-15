#!/usr/bin/env python3
"""Alpha54: preflight privilegiado somente-leitura + barras responsivas."""
import ast
import os
import stat
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT/'live-gui'))
sys.path.insert(0, str(ROOT/'live-gui/preview'))
import vm_bridge


class Alpha54(unittest.TestCase):
    def _sandbox(self):
        return (patch.object(vm_bridge, '_virt_type', return_value='qemu'),
                patch.object(vm_bridge, '_is_live_archiso', return_value=True),
                patch.object(vm_bridge.wolf_plan, 'inventory', return_value=[{'path':'/dev/vda'}]),
                patch.object(vm_bridge.wolf_plan, 'vm_execution_fields', return_value=('mock',)))

    def test_preflight_is_privileged_and_read_only(self):
        doc={'purpose':'test-preflight', 'marker':54}
        calls=[]
        def fake_run(argv, **kwargs):
            calls.append((argv,kwargs))
            self.assertEqual(argv[:4], ['sudo','-n','wolf-install','--preflight-gui-plan-vm'])
            target=Path(argv[4])
            self.assertEqual(stat.S_IMODE(target.stat().st_mode),0o600)
            self.assertEqual(target.parent.stat().st_mode & 0o777,0o700)
            self.assertEqual(kwargs['timeout'],35)
            self.assertIn('"marker": 54',target.read_text())
            return SimpleNamespace(returncode=0,stdout='[OK]',stderr='')
        from contextlib import ExitStack
        with ExitStack() as stack:
            for p in self._sandbox(): stack.enter_context(p)
            exe=stack.enter_context(patch.object(vm_bridge.subprocess,'run',side_effect=fake_run))
            self.assertTrue(vm_bridge.check_vm_plan(doc))
            self.assertEqual(exe.call_count,1)
        self.assertFalse(Path(calls[0][0][4]).exists())

    def test_denied_preflight_propagates_error(self):
        from contextlib import ExitStack
        with ExitStack() as stack:
            for p in self._sandbox(): stack.enter_context(p)
            stack.enter_context(patch.object(vm_bridge.subprocess,'run',return_value=SimpleNamespace(returncode=2,stdout='',stderr='Plano recusado por tabela divergente')))
            with self.assertRaisesRegex(vm_bridge.BridgeError,'tabela divergente'):
                vm_bridge.check_vm_plan({'marker':54})

    def test_non_live_never_requests_sudo(self):
        with patch.object(vm_bridge,'_virt_type',return_value='none'):
            with patch.object(vm_bridge.subprocess,'run') as runner:
                with self.assertRaises(vm_bridge.BridgeError):
                    vm_bridge.check_vm_plan({})
                runner.assert_not_called()

    def test_layout_guards(self):
        app=(ROOT/'live-gui/preview/app.py').read_text()
        ast.parse(app)
        self.assertIn('QLabel { background: transparent; }',app)
        self.assertIn('left.setFixedWidth(self.sidebar_width)',app)
        self.assertIn('ScrollBarAlwaysOff',app)
        self.assertIn('self.sidebar_width = min(330, max(255, int(width * 0.27)))',app)
        self.assertNotIn('left.setMaximumWidth(265)',app)
        self.assertIn('check_vm_plan(doc)',app)
        self.assertNotIn('wipefs',app)


if __name__=='__main__':
    unittest.main(verbosity=2)
