"""Terminal texto PTY via util-linux script, sem privilégio gráfico."""
from __future__ import annotations
import codecs
import shlex
from pathlib import Path
from time import monotonic
from PySide6.QtCore import QObject, QProcess, QProcessEnvironment, Signal

from .terminal_display import AnsiCleaner, sanitize

class TerminalRunner(QObject):
    output = Signal(str)
    finished = Signal(int)
    started = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.process = QProcess(self)
        self.process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.process.readyReadStandardOutput.connect(self._read)
        self.process.finished.connect(self._end)
        self.process.errorOccurred.connect(self._error)
        self._active = False
        self._cleaner = AnsiCleaner()
        self._decoder = codecs.getincrementaldecoder('utf-8')('replace')
        self.last_output = monotonic()
        self.launched_at = monotonic()

    def running(self) -> bool:
        return self._active

    def launch(self, argv: tuple[str, ...]):
        if self._active:
            raise RuntimeError('Já existe uma operação de pacotes')
        self._active = True
        self._cleaner = AnsiCleaner()
        self._decoder = codecs.getincrementaldecoder('utf-8')('replace')
        self.last_output = self.launched_at = monotonic()
        self.process.setProgram('script')
        self.process.setArguments(['-q', '-e', '-f', '-c', shlex.join(argv), '/dev/null'])
        env = QProcessEnvironment.systemEnvironment()
        env.insert('PAGER', 'cat')
        env.insert('GIT_PAGER', 'cat')
        env.insert('TERM', 'dumb')
        env.insert('NO_COLOR', '1')
        env.insert('GIT_TERMINAL_PROMPT', '0')
        # sudo -A usa um processo gráfico separado para solicitar a senha.
        env.insert('SUDO_ASKPASS', str(Path(__file__).resolve().parent / 'askpass.sh'))
        self.process.setProcessEnvironment(env)
        self.process.start()
        if not self.process.waitForStarted(2000):
            self._active = False
            raise RuntimeError(self.process.errorString())
        self.started.emit()

    def send_line(self, value: str):
        if not self._active:
            return
        if any(c in value for c in ('\r', '\n', '\0')) or len(value) > 4096:
            raise ValueError('Entrada inválida no terminal')
        self.process.write((value + '\n').encode('utf-8'))

    def _read(self):
        raw = self._decoder.decode(bytes(self.process.readAllStandardOutput()))
        clean = self._cleaner.feed(raw)
        if clean:
            self.last_output = monotonic()
            self.output.emit(clean)

    def _error(self, _):
        self.output.emit('\n[Erro de processo] ' + self.process.errorString() + '\n')

    def _end(self, code, status):
        self._read()
        self._active = False
        self.finished.emit(code if status == QProcess.ExitStatus.NormalExit else 128)
