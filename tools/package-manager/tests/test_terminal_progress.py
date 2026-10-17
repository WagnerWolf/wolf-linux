"""Pure rendering tests; no Qt needed, no package transactions."""
import unittest
from wolfpkg.terminal_display import TerminalLines, AnsiCleaner

class ProgressDisplay(unittest.TestCase):
    def test_redraw_does_not_grow(self):
        x = TerminalLines()
        for n in range(101):
            full, pending, changed = x.feed(f'linux-zen {n}%\r')
            self.assertEqual(full, [])
            self.assertTrue(changed)
        # finalize pending CR with next non-newline
        full, pending, _ = x.feed('feito\n')
        self.assertEqual(full, ['feito'])
        self.assertEqual(pending, '')

    def test_split_progress_and_crlf(self):
        x = TerminalLines()
        completed = []
        for chunk in ['Total: 33', '%\r', 'Total: 43%', '\r\n', 'Pronto\n']:
            done, pending, _ = x.feed(chunk)
            completed.extend(done)
        self.assertEqual(completed, ['Total: 43%', 'Pronto'])
        self.assertEqual(pending, '')

    def test_ansi_sequences_split_across_reads(self):
        clean = AnsiCleaner()
        chunks = ['\x1b[', '1;31mPR', 'OG 50%\r\x1b', '[0m', 'PROG 100%\n']
        result = ''.join(clean.feed(x) for x in chunks)
        self.assertEqual(result, 'PROG 50%\rPROG 100%\n')
        x = TerminalLines()
        done, pending, _ = x.feed(result)
        self.assertEqual(done, ['PROG 100%'])

    def test_osc_split_and_backspace(self):
        clean = AnsiCleaner()
        self.assertEqual(clean.feed('pac\x1b]0;title'), 'pac')
        self.assertEqual(clean.feed('\x1b\\man\bual\n'), 'man\bual\n')
        x = TerminalLines()
        done, pending, _ = x.feed('abc\bD\n')
        self.assertEqual(done, ['abD'])

    def test_no_trailing_newline_newline_next(self):
        x = TerminalLines()
        full, cur, _ = x.feed('pacman 1%\r')
        self.assertEqual((full, cur), ([], 'pacman 1%'))
        full, cur, _ = x.feed('\n')
        self.assertEqual((full, cur), (['pacman 1%'], ''))

    def test_integration_in_app(self):
        from pathlib import Path
        src = (Path(__file__).parents[1]/'wolfpkg/app.py').read_text()
        runner = (Path(__file__).parents[1]/'wolfpkg/terminal.py').read_text()
        self.assertIn('self._terminal_lines.feed(value)', src)
        self.assertIn('QTextCursor.MoveOperation.StartOfBlock', src)
        self.assertIn('QPlainTextEdit.LineWrapMode.NoWrap', src)
        self.assertNotIn("replace('\\r', '\\n')", runner)
        self.assertIn('self._cleaner.feed(raw)', runner)

if __name__ == '__main__':
    unittest.main()
