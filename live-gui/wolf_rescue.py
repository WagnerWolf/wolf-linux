#!/usr/bin/env python3
"""Wolf Rescue 0.2 — diagnóstico e mapa fstab/lsblk, exclusivamente leitura."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from wolf_storage_map import build_map

REPORT = '/usr/local/bin/wolf-live-rescue-report'
LSBLK = ['lsblk', '-J', '-b', '-e', '7', '-o',
         'NAME,PATH,TYPE,FSTYPE,UUID,PARTUUID,SIZE,PKNAME,MODEL,TRAN,MOUNTPOINTS']


def read_fstab(path: Path) -> str:
    """Lê somente arquivos etc/fstab explicitamente selecionados pelo usuário."""
    if path.name != 'fstab' or path.parent.name != 'etc':
        raise ValueError('Selecione o arquivo etc/fstab da instalação existente.')
    if path.stat().st_size > 262144:
        raise ValueError('Arquivo fstab excede o limite de leitura (256 KiB).')
    return path.read_text(encoding='utf-8', errors='replace')


def main() -> int:
    if not Path('/etc/wolf-linux-live-build').is_file() and os.getenv('WOLF_RESCUE_TEST_MODE') != '1':
        print('[ERRO] Wolf Rescue somente na Live Wolf Linux.', file=sys.stderr)
        return 1

    from PySide6.QtCore import QProcess, Qt
    from PySide6.QtGui import QGuiApplication, QFontDatabase
    from PySide6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QLabel,
        QPushButton, QPlainTextEdit, QMessageBox, QFileDialog, QTabWidget, QGridLayout,
    )

    class Rescue(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle('Wolf Rescue 0.2 — Armazenamento e inicialização')
            screen = QGuiApplication.primaryScreen()
            rect = screen.availableGeometry() if screen else None
            self.resize(min(1040, rect.width()-60) if rect else 980,
                        min(700, rect.height()-60) if rect else 650)
            self.setMinimumSize(620, 420)
            self._fstab_source: Path | None = None
            self._fstab_content = ''

            central = QWidget()
            outer = QVBoxLayout(central)
            outer.setContentsMargins(16, 14, 16, 14)
            outer.setSpacing(10)

            heading = QLabel('WOLF RESCUE 0.2')
            heading.setObjectName('heading')
            outer.addWidget(heading)
            subtitle = QLabel('Diagnóstico • Armazenamento • Entradas de boot • Mapa do fstab')
            subtitle.setObjectName('subtitle')
            subtitle.setWordWrap(True)
            outer.addWidget(subtitle)

            warning = QLabel('SOMENTE LEITURA — não executa reparos, montagem, formatação ou alterações em LVM. '
                             'A instalação em hardware físico continua bloqueada.')
            warning.setObjectName('warning')
            warning.setWordWrap(True)
            outer.addWidget(warning)

            tabs = QTabWidget()
            tabs.tabBar().setUsesScrollButtons(True)
            tabs.tabBar().setExpanding(False)
            outer.addWidget(tabs, 1)
            self.tabs = tabs

            report_page = QWidget()
            rv = QVBoxLayout(report_page)
            report_buttons = QGridLayout()
            actions = (
                ('Atualizar diagnóstico', self.run_diagnostics),
                ('Copiar relatório', self.copy_report),
                ('Abrir arquivos', lambda: QProcess.startDetached('pcmanfm-qt', [])),
                ('Abrir terminal', lambda: QProcess.startDetached('qterminal', [])),
            )
            for i, (title, fn) in enumerate(actions):
                button = QPushButton(title)
                button.clicked.connect(fn)
                report_buttons.addWidget(button, i // 2, i % 2)
            rv.addLayout(report_buttons)
            self.output = QPlainTextEdit()
            self.output.setObjectName('console')
            self.output.setReadOnly(True)
            self.output.setLineWrapMode(QPlainTextEdit.LineWrapMode.WidgetWidth)
            self.output.setFont(QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont))
            rv.addWidget(self.output, 1)
            tabs.addTab(report_page, 'Diagnóstico completo')

            map_page = QWidget()
            mv = QVBoxLayout(map_page)
            explanation = QLabel(
                'Selecione o etc/fstab de um Linux já acessível pelo PCManFM-Qt. '
                'O Wolf Rescue correlacionará os UUIDs do fstab com o lsblk atual e '
                'mostrará os discos físicos e PVs LVM envolvidos. Não executa instalação.'
            )
            explanation.setWordWrap(True)
            mv.addWidget(explanation)
            map_actions = QHBoxLayout()
            select = QPushButton('Selecionar etc/fstab')
            select.clicked.connect(self.open_fstab)
            map_actions.addWidget(select)
            update = QPushButton('Atualizar mapa')
            update.clicked.connect(self.refresh_map)
            map_actions.addWidget(update)
            copy_map = QPushButton('Copiar mapa')
            copy_map.clicked.connect(lambda: QGuiApplication.clipboard().setText(self.map_output.toPlainText()))
            map_actions.addWidget(copy_map)
            mv.addLayout(map_actions)
            self.fstab_path = QLabel('Nenhum fstab escolhido')
            self.fstab_path.setWordWrap(True)
            self.fstab_path.setObjectName('subtitle')
            mv.addWidget(self.fstab_path)
            self.map_output = QPlainTextEdit()
            self.map_output.setObjectName('console')
            self.map_output.setReadOnly(True)
            self.map_output.setLineWrapMode(QPlainTextEdit.LineWrapMode.WidgetWidth)
            self.map_output.setFont(QFontDatabase.systemFont(QFontDatabase.SystemFont.FixedFont))
            self.map_output.setPlainText('Selecione o fstab de uma instalação existente para mapear /, /boot/efi e /home.')
            mv.addWidget(self.map_output, 1)
            tabs.addTab(map_page, 'Mapa de volumes')

            self.setCentralWidget(central)
            self.process = QProcess(self)
            self.process.readyReadStandardOutput.connect(self.read_stdout)
            self.process.readyReadStandardError.connect(self.read_stderr)
            self.process.finished.connect(self.report_complete)
            self.run_diagnostics()

        def copy_report(self):
            QGuiApplication.clipboard().setText(self.output.toPlainText())

        def open_fstab(self):
            selected, _ = QFileDialog.getOpenFileName(
                self, 'Selecione /etc/fstab de uma instalação montada',
                '/run/media/wolf', 'fstab (fstab);;Todos os arquivos (*)')
            if not selected:
                return
            try:
                self._fstab_content = read_fstab(Path(selected))
            except (OSError, ValueError) as exc:
                QMessageBox.warning(self, 'Wolf Rescue', f'Não foi possível ler o fstab: {exc}')
                return
            self._fstab_source = Path(selected)
            self.fstab_path.setText(str(self._fstab_source))
            self.refresh_map()
            self.tabs.setCurrentIndex(1)

        def refresh_map(self):
            if not self._fstab_source:
                QMessageBox.information(self, 'Wolf Rescue', 'Selecione primeiro um arquivo etc/fstab.')
                return
            try:
                # Apenas consulta local; nenhum comando que altere discos.
                result = subprocess.run(LSBLK, capture_output=True, text=True,
                                        timeout=10, check=True)
                report, warnings = build_map(self._fstab_content, result.stdout)
                self.map_output.setPlainText(report)
                if warnings:
                    self.map_output.appendPlainText(f'\nTotal de avisos: {len(warnings)}')
            except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError) as exc:
                self.map_output.setPlainText(f'[ERRO] Não foi possível gerar o mapa: {exc}')

        def run_diagnostics(self):
            if self.process.state() != QProcess.ProcessState.NotRunning:
                QMessageBox.information(self, 'Wolf Rescue', 'Consulta anterior em andamento.')
                return
            self.output.setPlainText('Consultando discos, LVM e entradas de boot (somente leitura)...\n')
            self.process.start(REPORT, [])

        def read_stdout(self):
            self.output.insertPlainText(bytes(self.process.readAllStandardOutput()).decode('utf-8', 'replace'))

        def read_stderr(self):
            self.output.insertPlainText(bytes(self.process.readAllStandardError()).decode('utf-8', 'replace'))

        def report_complete(self, exit_code, _status):
            self.read_stdout()
            self.read_stderr()
            if exit_code:
                self.output.appendPlainText(f'\n[AVISO] Relatório retornou código {exit_code}; confira a saída.')

    app = QApplication(sys.argv)
    app.setApplicationName('Wolf Rescue')
    app.setStyle('Fusion')
    app.setStyleSheet('''
        QWidget { background: #11151d; color: #e5eaf2; font: 10pt 'Sans Serif'; }
        QLabel#heading { font-size: 19pt; font-weight: 700; color: #f5f8ff; }
        QLabel#subtitle { color: #a8bdd5; }
        QLabel#warning { color: #ffd49e; background: #33271c;
                         border: 1px solid #b28548; border-radius: 7px; padding: 10px; }
        QTabWidget::pane { border: 1px solid #36465a; }
        QTabBar::tab { background: #253044; border: 1px solid #344356; padding: 9px 14px; }
        QTabBar::tab:selected { background: #405674; color: white; }
        QPushButton { background: #26354a; border: 1px solid #526984;
                      border-radius: 7px; padding: 9px; color: #f0f5fd; }
        QPushButton:hover { background: #385574; }
        QPlainTextEdit#console { background: #0a1019; color: #d5e6f7;
                                 border: 1px solid #40516b; selection-background-color: #3d6084; }
        QScrollBar:vertical { background: #17212e; width: 13px; }
        QScrollBar::handle:vertical { background: #485d77; min-height: 26px; border-radius: 5px; }
    ''')
    window = Rescue()
    window.show()
    return app.exec()


if __name__ == '__main__':
    raise SystemExit(main())
