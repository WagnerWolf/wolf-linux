#!/usr/bin/env python3
"""PTY rendering regression tests, no GUI privileges or block devices."""
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'live-gui'))
from terminal_display import TerminalLines


class ProgressRenderer(unittest.TestCase):
    def test_pacman_redraws_in_one_chunk(self):
        t = TerminalLines()
        self.assertEqual(t.feed('pacote 10%\rpacote 60%\rpacote 100%'),
                         ([], 'pacote 100%', True))
        self.assertEqual(t.feed('\r\nPróximo pacote\n'),
                         (['pacote 100%', 'Próximo pacote'], '', True))

    def test_carriage_split_across_chunks(self):
        t = TerminalLines()
        t.feed('baixando 33%\r')
        self.assertEqual(t.feed('baixando 66%')[1], 'baixando 66%')
        self.assertEqual(t.feed('\n')[0], ['baixando 66%'])

    def test_crlf_not_erase_line(self):
        t = TerminalLines()
        self.assertEqual(t.feed('etapa pronta\r\nseguinte\r\n')[0],
                         ['etapa pronta', 'seguinte'])

    def test_normal_incremental_lines(self):
        t = TerminalLines()
        t.feed('parte ')
        finished, current, changed = t.feed('do comando\nPrompt: ')
        self.assertTrue(changed)
        self.assertEqual(finished, ['parte do comando'])
        self.assertEqual(current, 'Prompt: ')
        self.assertEqual(t.feed('')[2], False)

    def test_backspaces_limit_reset(self):
        t = TerminalLines(max_line_length=4)
        self.assertEqual(t.feed('abc\bde123')[1], 'abde')
        t.reset()
        self.assertEqual(t.feed('novo')[1], 'novo')

    def test_gui_stage_wiring(self):
        app = (ROOT/'live-gui/preview/app.py').read_text()
        staging = (ROOT/'tests/wolf-stage-live-desktop.sh').read_text()
        self.assertIn('from terminal_display import TerminalLines', app)
        self.assertIn('self._terminal_lines.feed(output)', app)
        self.assertNotIn("output.replace('\\r', '')", app)
        self.assertIn('terminal_display.py', staging)
        self.assertIn('terminal_display.py', (ROOT/'tests/wolf-test-live-desktop.sh').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
