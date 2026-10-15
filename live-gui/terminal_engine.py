#!/usr/bin/env python3
"""Interactive pseudo-terminal for the Wolf Live installer.

Only the explicitly enumerated, independently validated install backends can run.
A PTY provides
stdin/stdout/stderr and TTY semantics for Bash confirmations/password prompts.
A plain-text UI is not an xterm emulator: colors/control sequences are filtered.
"""
from __future__ import annotations
import codecs
import errno
import os
import pty
import re
import fcntl
import struct
import termios
import subprocess
from pathlib import Path

# Lista FECHADA: a UI nunca pode usar o PTY para executar flags arbitrárias.
# O modo físico mantém o preflight da GUI e todas as validações independentes
# do Bash/wolf_physical_executor (identidade, UUID, fstab, LVM, Live e UEFI).
ALLOWED_EXECUTION_MODES = frozenset({
    "--execute-gui-plan-vm",
    "--execute-gui-plan-vm-click",
    "--execute-multidisk-lab-vm",
    "--execute-multidisk-physical",
})

ANSI = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[()][AB012]|[78])")


def sanitize(text: str) -> str:
    text = ANSI.sub("", text)
    # Other controls except newline/tab/carriage return: avoid Qt control spoofing.
    return "".join(ch for ch in text if ch in "\n\r\t" or ord(ch) >= 32)


class InstallerPty:
    def __init__(self):
        self.master = None
        self.proc = None
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def start(self, plan: Path, *, mode: str = "--execute-gui-plan-vm") -> int:
        if self.proc is not None:
            raise RuntimeError("Já existe instalação nesta sessão")
        if mode not in ALLOWED_EXECUTION_MODES:
            raise ValueError("Modo de execução PTY não autorizado")
        master, slave = pty.openpty()
        # Tamanho conservador para comandos CLI que consultam TIOCGWINSZ.
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        os.set_blocking(master, False)
        try:
            # No shell=True, no user-controlled arbitrary commands.
            proc = subprocess.Popen(
                ["sudo", "-n", "wolf-install", mode, str(plan)],
                stdin=slave, stdout=slave, stderr=slave,
                start_new_session=True, close_fds=True,
            )
        except BaseException:
            os.close(master)
            raise
        finally:
            os.close(slave)
        self.proc = proc
        self.master = master
        return master

    def read(self) -> tuple[str, bool]:
        if self.master is None:
            return "", True
        data = bytearray()
        ended = False
        for _ in range(64):
            try:
                chunk = os.read(self.master, 65536)
            except BlockingIOError:
                break
            except OSError as exc:
                if exc.errno == errno.EIO:  # Slave side has closed.
                    ended = True
                    break
                raise
            if not chunk:
                ended = True
                break
            data.extend(chunk)
            if len(chunk) < 65536:
                break
        return sanitize(self.decoder.decode(bytes(data), final=ended)), ended

    def send(self, value: str) -> None:
        if self.master is None or self.proc is None or self.proc.poll() is not None:
            raise RuntimeError("A instalação não está ativa")
        if "\x00" in value or "\n" in value or "\r" in value or len(value) > 2048:
            raise ValueError("Entrada inválida")
        os.write(self.master, (value + "\n").encode("utf-8"))

    def poll(self):
        return self.proc.poll() if self.proc else None

    def close_read(self):
        if self.master is not None:
            os.close(self.master)
            self.master = None
