#!/usr/bin/env python3
"""Editor visual de monitores para LXQt/X11 com confirmação/rollback XRandR."""
from __future__ import annotations

from dataclasses import replace
from pathlib import Path
import subprocess
import sys

from PySide6.QtCore import Qt, QRectF, QTimer, Signal
from PySide6.QtGui import QPainter, QPen, QColor, QBrush, QFont
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QDialog, QFormLayout, QHBoxLayout, QLabel,
    QMessageBox, QPushButton, QVBoxLayout, QWidget, QGroupBox, QSizePolicy,
)

from monitor_layout import (
    Output, read_outputs, normalized, validate, create_pending, mark_confirmed,
    run_xrandr, xrandr_argv, save_persistent, disable_persistent,
)

COLOR_BG = QColor('#1c242d')
COLOR_ON = QColor('#314961')
COLOR_PRIMARY = QColor('#70b6ef')
COLOR_TEXT = QColor('#f2f6fc')


class MonitorCanvas(QWidget):
    picked = Signal(str)
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.outputs: list[Output] = []
        self.selected = ''
        self.setMinimumHeight(245)
        self.setMouseTracking(True)
        self._drag = None
        self._hit: list[tuple[QRectF,str]] = []
        self._factor = 0.12
        self._offset = (20, 25)

    def set_outputs(self, outputs: list[Output], selected: str):
        self.outputs = outputs
        self.selected = selected
        self.update()

    def _rects(self):
        on = [o for o in self.outputs if o.connected and o.enabled]
        if not on:
            return []
        left = min(o.x for o in on); top = min(o.y for o in on)
        right = max(o.x + o.dims()[0] for o in on)
        bottom = max(o.y + o.dims()[1] for o in on)
        w = max(right-left, 1); h = max(bottom-top, 1)
        f = min((self.width()-55)/w, (self.height()-60)/h, 0.25)
        self._factor = max(f, 0.01)
        self._offset = ((self.width()-w*f)/2, (self.height()-h*f)/2)
        return [(QRectF(self._offset[0]+(o.x-left)*f, self._offset[1]+(o.y-top)*f,
                        o.dims()[0]*f, o.dims()[1]*f), o) for o in on]

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        p.fillRect(self.rect(), COLOR_BG)
        p.setPen(QColor('#738399'))
        p.drawText(16, 18, 'Arraste as telas para reorganizar · sem espelhamento nesta prévia')
        self._hit = []
        for rect, o in self._rects():
            self._hit.append((rect, o.name))
            p.setPen(QPen(COLOR_PRIMARY if o.name == self.selected else QColor('#8b9ba9'), 3 if o.name == self.selected else 1.5))
            p.setBrush(QBrush(COLOR_ON if o.primary else QColor('#293642')))
            p.drawRoundedRect(rect, 7, 7)
            p.setPen(COLOR_TEXT)
            font = QFont(p.font())
            font.setBold(True)
            font.setPointSize(11)
            p.setFont(font)
            p.drawText(rect.adjusted(7, 5, -7, -8), Qt.AlignmentFlag.AlignCenter,
                       f'{o.name}' + (' ★' if o.primary else '') + f'\n{o.mode}')
        p.end()

    def mousePressEvent(self, event):
        if event.button() != Qt.MouseButton.LeftButton:
            return
        for rect, name in reversed(self._hit):
            if rect.contains(event.position()):
                self.selected = name
                self.picked.emit(name)
                item = next(o for o in self.outputs if o.name == name)
                self._drag = (name, event.position().x(), event.position().y(), item.x, item.y)
                self.update()
                break

    def mouseMoveEvent(self, event):
        if not self._drag or not (event.buttons() & Qt.MouseButton.LeftButton):
            return
        name, bx, by, x, y = self._drag
        item = next(o for o in self.outputs if o.name == name)
        factor = max(self._factor, 0.01)
        item.x = int(round((event.position().x()-bx)/factor + x))
        item.y = int(round((event.position().y()-by)/factor + y))
        self.update()

    def mouseReleaseEvent(self, event):
        if not self._drag:
            return
        name = self._drag[0]
        self._drag = None
        item = next(o for o in self.outputs if o.name == name)
        # Snap posições aproximadas às bordas e às linhas de alinhamento (px reais).
        for other in self.outputs:
            if other is item or not other.connected or not other.enabled:
                continue
            iw, ih = item.dims(); ow, oh = other.dims()
            xopts = [other.x, other.x+ow, other.x-iw]
            yopts = [other.y, other.y+oh, other.y-ih]
            nx = min(xopts, key=lambda v: abs(v-item.x))
            ny = min(yopts, key=lambda v: abs(v-item.y))
            if abs(nx-item.x) < 115:
                item.x = nx
            if abs(ny-item.y) < 115:
                item.y = ny
        self.changed.emit()
        self.update()


class ConfirmLayout(QDialog):
    """Confirma o modo aplicado sem cortar mensagens quando há escalonamento de fontes."""

    def __init__(self, parent=None, seconds=19):
        super().__init__(parent)
        self.setWindowTitle('Confirmar configuração dos monitores')
        self.remaining = seconds
        self.setMinimumSize(520, 226)
        self.resize(620, 252)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 18, 20, 18)
        layout.setSpacing(12)

        title = QLabel('As telas estão funcionando corretamente?')
        title.setWordWrap(True)
        title.setStyleSheet('font-weight: 600; font-size: 14px;')
        layout.addWidget(title)

        self.countdown = QLabel()
        self.countdown.setStyleSheet('font-weight: 600; color: #e7ba65;')
        self.countdown.setWordWrap(True)
        layout.addWidget(self.countdown)

        message = QLabel('Se não confirmar, a disposição anterior será restaurada '
                         'automaticamente. Você também pode reverter agora.')
        message.setWordWrap(True)
        message.setSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.MinimumExpanding)
        layout.addWidget(message, 1)

        buttons = QHBoxLayout()
        buttons.setSpacing(12)
        accept = QPushButton('Manter configuração')
        cancel = QPushButton('Reverter agora')
        for button in (accept, cancel):
            button.setMinimumHeight(40)
            button.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        accept.clicked.connect(self.accept)
        cancel.clicked.connect(self.reject)
        buttons.addWidget(accept)
        buttons.addWidget(cancel)
        layout.addLayout(buttons)

        self.clock = QTimer(self)
        self.clock.timeout.connect(self.tick)
        self.clock.start(1000)
        self.tick(first=True)

    def tick(self, first=False):
        if not first:
            self.remaining -= 1
        self.countdown.setText(f'Reversão automática em {max(0, self.remaining)} segundos.')
        if self.remaining <= 0:
            self.reject()


class MonitorEditor(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle('Wolf Linux · Monitores X11')
        # Área inicial mais ampla; nunca excede a área útil da tela que abriu o editor.
        # O XRandR continua responsável apenas pelas configurações dos monitores.
        screen = self.screen() if hasattr(self, 'screen') else None
        available = screen.availableGeometry() if screen else None
        w = min(1080, max(500, available.width() - 72)) if available else 1080
        h = min(795, max(440, available.height() - 72)) if available else 795
        self.resize(w, h)
        self.setMinimumSize(min(750, w), min(590, h))
        self.outputs: list[Output] = []
        self.selected = ''
        self._syncing = False
        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(12)
        self.hint = QLabel('Organize as telas arrastando os retângulos. A configuração só muda após clicar em Aplicar.')
        self.hint.setWordWrap(True)
        layout.addWidget(self.hint)
        self.canvas = MonitorCanvas()
        layout.addWidget(self.canvas, 1)
        controls = QGroupBox('Configuração do monitor selecionado')
        form = QFormLayout(controls)
        self.screen = QComboBox()
        self.screen.currentIndexChanged.connect(self._select_output)
        form.addRow('Saída:', self.screen)
        self.enabled = QCheckBox('Monitor ligado')
        self.enabled.toggled.connect(self._toggle)
        form.addRow('', self.enabled)
        self.mode = QComboBox()
        self.mode.currentIndexChanged.connect(self._mode_changed)
        form.addRow('Resolução:', self.mode)
        self.rate = QComboBox()
        self.rate.currentIndexChanged.connect(self._rate_changed)
        form.addRow('Frequência:', self.rate)
        self.primary = QCheckBox('Monitor principal')
        self.primary.toggled.connect(self._primary_changed)
        form.addRow('', self.primary)
        self.details = QLabel('')
        form.addRow('Posição:', self.details)
        layout.addWidget(controls)
        self.persist = QCheckBox('Salvar layout aprovado para restaurar no próximo login LXQt/X11')
        self.persist.setChecked(False)
        layout.addWidget(self.persist)
        row = QVBoxLayout()
        row.setSpacing(8)
        refresh = QPushButton('Recarregar telas')
        refresh.clicked.connect(self.refresh)
        apply = QPushButton('Aplicar com confirmação')
        apply.clicked.connect(self.apply)
        disable_saved = QPushButton('Desativar restauração no login')
        disable_saved.clicked.connect(self.disable_saved)
        close = QPushButton('Fechar')
        close.clicked.connect(self.reject)
        # A janela anterior tinha todos os comandos numa só linha, truncando
        # nomes de botões com fontes maiores ou escala de interface diferente.
        utilities = QHBoxLayout()
        utilities.setSpacing(10)
        utilities.addWidget(refresh)
        utilities.addStretch(1)
        utilities.addWidget(disable_saved)
        actions = QHBoxLayout()
        actions.setSpacing(10)
        actions.addStretch(1)
        actions.addWidget(apply)
        actions.addWidget(close)
        for button in (refresh, apply, disable_saved, close):
            button.setMinimumHeight(38)
            button.setSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Fixed)
        apply.setMinimumWidth(205)
        row.addLayout(utilities)
        row.addLayout(actions)
        layout.addLayout(row)
        self.canvas.picked.connect(self.pick)
        self.canvas.changed.connect(self._update_position)
        self.refresh()

    def refresh(self):
        try:
            self.outputs = read_outputs()
        except Exception as exc:
            QMessageBox.warning(self, 'Monitores', f'Falha ao consultar XRandR:\n{exc}')
            return
        self._syncing = True
        self.screen.clear()
        connected = [o for o in self.outputs if o.connected]
        for o in connected:
            self.screen.addItem(f'{o.name}  ({"ligado" if o.enabled else "desligado"})', o.name)
        if not any(o.primary and o.enabled for o in connected):
            next((setattr(o, 'primary', True) for o in connected if o.enabled), None)
        self._syncing = False
        self.pick(connected[0].name if connected else '')

    def chosen(self) -> Output | None:
        return next((o for o in self.outputs if o.name == self.selected), None)

    def pick(self, name: str):
        self._syncing = True
        self.selected = name
        index = self.screen.findData(name)
        self.screen.setCurrentIndex(index)
        o = self.chosen()
        self.mode.clear(); self.rate.clear()
        if o:
            self.enabled.setChecked(o.enabled)
            for m in o.modes:
                self.mode.addItem(m.name)
            self.mode.setCurrentIndex(self.mode.findText(o.mode))
            self._populate_rates(o)
            self.primary.setChecked(o.primary)
            self._update_position()
        self._syncing = False
        self.canvas.set_outputs(self.outputs, name)

    def _select_output(self):
        if not self._syncing:
            self.pick(self.screen.currentData())

    def _populate_rates(self, o: Output):
        old = self._syncing
        self._syncing = True
        self.rate.clear()
        chosen_mode = next((m for m in o.modes if m.name == o.mode), None)
        if chosen_mode:
            self.rate.addItems(chosen_mode.rates)
            self.rate.setCurrentIndex(max(0, self.rate.findText(o.rate)))
        self._syncing = old

    def _toggle(self, flag: bool):
        if self._syncing:
            return
        o = self.chosen()
        if not o:
            return
        o.enabled = flag
        if flag:
            if not any(x.primary and x.enabled for x in self.outputs):
                o.primary = True
            if not any(x.enabled and x is not o for x in self.outputs):
                o.x, o.y = 0, 0
            else:
                o.x = max((x.x + x.dims()[0] for x in self.outputs if x.enabled and x is not o), default=0)
                o.y = 0
        elif o.primary:
            o.primary = False
            next((setattr(x, 'primary', True) for x in self.outputs if x.enabled and x is not o), None)
        self.pick(o.name)

    def _mode_changed(self):
        if self._syncing:
            return
        o = self.chosen()
        if o and self.mode.currentText():
            o.mode = self.mode.currentText()
            m = next((m for m in o.modes if m.name == o.mode), None)
            if m and m.rates:
                o.rate = m.rates[0]
            self._populate_rates(o)
            self.canvas.update()

    def _rate_changed(self):
        if not self._syncing and self.chosen() and self.rate.currentText():
            self.chosen().rate = self.rate.currentText()

    def _primary_changed(self, state: bool):
        if self._syncing:
            return
        o = self.chosen()
        if not o:
            return
        if state:
            if not o.enabled:
                self._syncing = True
                self.primary.setChecked(False)
                self._syncing = False
                return
            for x in self.outputs:
                x.primary = x is o
        elif o.primary:
            # Ao desmarcar, só permite trocar escolhendo outra tela principal.
            self._syncing = True
            self.primary.setChecked(True)
            self._syncing = False
        self.canvas.update()

    def _update_position(self):
        o = self.chosen()
        if o:
            self.details.setText(f'X={o.x}  Y={o.y}' + ('' if o.enabled else ' (desligado)'))

    def apply(self):
        try:
            desired = normalized(self.outputs)
            validate(desired)
            original = read_outputs()
            # Não aceita mudança de topologia entre abertura do editor e aplicação.
            if {o.name for o in original if o.connected} != {o.name for o in desired if o.connected}:
                raise ValueError('Conexões de monitores mudaram. Recarregue a lista antes de aplicar.')
            folder = create_pending(original, desired)
            watchdog_script = Path(__file__).resolve().with_name('monitor_layout.py')
            with (folder/'watchdog.log').open('w', encoding='utf-8') as log:
                subprocess.Popen([sys.executable, str(watchdog_script), '--watchdog', str(folder)],
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                 start_new_session=True)
            try:
                run_xrandr(xrandr_argv(desired))
            except Exception:
                try:
                    run_xrandr(xrandr_argv(original))
                    mark_confirmed(folder)
                except Exception:
                    pass  # Watchdog fará nova tentativa
                raise
            confirmed = ConfirmLayout(self).exec() == QDialog.DialogCode.Accepted
            if not confirmed:
                try:
                    run_xrandr(xrandr_argv(original))
                    mark_confirmed(folder)
                except Exception as exc:
                    QMessageBox.warning(self, 'Restauração', f'Falha ao reverter agora: {exc}\n'
                                         'O processo de segurança tentará novamente.')
                self.refresh()
                return
            mark_confirmed(folder)
            # A topologia XRandR mudou: reavaliar os painéis sem watcher.
            # Falha do painel não deve desfazer o layout de vídeo já confirmado.
            try:
                subprocess.run(['/usr/local/bin/wolf-lxqt-monitors'],
                               check=False, timeout=15, capture_output=True)
            except (OSError, subprocess.TimeoutExpired):
                pass
            if self.persist.isChecked():
                desktop = save_persistent(desired)
                QMessageBox.information(self, 'Wolf Linux', 'Monitores aplicados e confirmados.\n'
                    f'Layout salvo para o próximo login:\n{desktop}\n\n'
                    'Os painéis LXQt não foram alterados; confira o layout e use a auditoria Wolf se necessário.')
            else:
                QMessageBox.information(self, 'Wolf Linux', 'Monitores aplicados.\n'
                    'O layout não foi configurado para restaurar no próximo login.\n'
                    'Painéis e atalhos Wolf foram preservados.')
            self.refresh()
        except Exception as exc:
            QMessageBox.warning(self, 'Monitores', str(exc))

    def disable_saved(self):
        if QMessageBox.question(self, 'Monitores',
            'Desativar a restauração automática do layout no próximo login?\n'
            'A disposição atual dos monitores NÃO será alterada.',
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No) != QMessageBox.StandardButton.Yes:
            return
        try:
            disable_persistent()
            self.persist.setChecked(False)
            QMessageBox.information(self, 'Monitores', 'Restauração automática desativada.')
        except Exception as exc:
            QMessageBox.warning(self, 'Monitores', str(exc))



def open_editor(parent=None):
    if __import__('os').environ.get('XDG_SESSION_TYPE') != 'x11':
        QMessageBox.warning(parent, 'Monitores', 'Disponível somente na sessão X11.')
        return
    MonitorEditor(parent).exec()
