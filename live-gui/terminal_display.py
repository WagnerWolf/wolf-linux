#!/usr/bin/env python3
"""Prepare PTY text for a read-only Qt log view.

Tools like pacman redraw their progress bars using carriage returns rather
than newlines. The UI is not a VT emulator: convert each redraw to an update
of the current log line instead of appending overprinted progress frames.

Does not alter subprocess output, execution, PTY input, or the installer log.
"""
from __future__ import annotations


class TerminalLines:
    """Incrementally normalize carriage returns, line breaks and backspaces.

    feed() returns (completed_lines, current_line, changed).  The last line is
    always replaceable by the next chunk; completed lines are immutable.
    """

    def __init__(self, max_line_length: int = 8192):
        self.current = ""
        self._pending_cr = False
        self._max_line_length = max_line_length

    def feed(self, text: str) -> tuple[list[str], str, bool]:
        completed: list[str] = []
        changed = False
        for char in text:
            if self._pending_cr:
                self._pending_cr = False
                if char == "\n":
                    completed.append(self.current)
                    self.current = ""
                    changed = True
                    continue
                # Standalone CR rewinds a progress line. Since the progress bar
                # replaces the *whole* row, discard its previous presentation.
                if self.current:
                    self.current = ""
                    changed = True
            if char == "\r":
                self._pending_cr = True
            elif char == "\n":
                completed.append(self.current)
                self.current = ""
                changed = True
            elif char == "\b":
                if self.current:
                    self.current = self.current[:-1]
                    changed = True
            elif char == "\t" or ord(char) >= 32:
                if len(self.current) < self._max_line_length:
                    self.current += char
                    changed = True
        return completed, self.current, changed

    def reset(self) -> None:
        self.current = ""
        self._pending_cr = False
