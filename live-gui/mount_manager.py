#!/usr/bin/env python3
"""Wolf Mount Manager — graphical explicit read-only volume access for Live."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys


def run_command(args: list[str], timeout: int = 45) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)


def ui_main() -> int:
    from PySide6.QtCore import Qt
    from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
        QHBoxLayout, QLabel, QPushButton, QTableWidget, QTableWidgetItem,
        QAbstractItemView, QMessageBox)

    app = QApplication(sys.argv[:1])
    app.setApplicationName('Wolf Mount Manager')
    app.setStyle('Fusion')
    app.setStyleSheet('''
        QWidget { background:#11151d; color:#e5eaf2; font-size:11pt; }
        QPushButton { background:#253044; border:1px solid #40516b; border-radius:6px; padding:9px; }
        QPushButton:hover { background:#334963; }
        QTableWidget { background:#18212c; gridline-color:#40516b; }
        QHeaderView::section { background:#253044; color:#e5eaf2; padding:7px; }
    ''')

    class Window(QMainWindow):
        def __init__(self):
            super().__init__()
            self.setWindowTitle('Wolf Linux — Gerenciador de Volumes (somente leitura)')
            self.resize(1020, 600)
            content = QWidget()
            self.setCentralWidget(content)
            outer = QVBoxLayout(content)
            title = QLabel('WOLF MOUNT MANAGER  •  ACESSO SOMENTE LEITURA')
            title.setStyleSheet('font-size:16pt; font-weight:bold; color:#d1e2ff;')
            outer.addWidget(title)
            explain = QLabel(
                'Selecione uma partição ou volume lógico. "Montar" abre somente para leitura, '
                'sem fsck, formatação ou alterações. A mídia Live e volumes já montados não '
                'serão montados novamente. Para salvar arquivos recuperados, use outro destino '
                'que permita gravação, fora deste gerenciador.'
            )
            explain.setWordWrap(True)
            outer.addWidget(explain)
            self.table = QTableWidget(0, 5)
            self.table.setHorizontalHeaderLabels(['Dispositivo', 'Tamanho', 'Sistema', 'Rótulo', 'Montagem'])
            self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
            self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            self.table.horizontalHeader().setStretchLastSection(True)
            self.table.setColumnWidth(0, 260)
            self.table.setColumnWidth(1, 110)
            self.table.setColumnWidth(2, 130)
            self.table.setColumnWidth(3, 165)
            outer.addWidget(self.table)
            row = QHBoxLayout()
            for label, action in (
                ('Atualizar', self.refresh),
                ('Montar somente leitura', self.mount),
                ('Abrir no explorador', self.open_folder),
                ('Desmontar volume Wolf', self.unmount),
            ):
                b = QPushButton(label)
                b.clicked.connect(action)
                row.addWidget(b)
            outer.addLayout(row)
            self.note = QLabel('Nenhum volume é montado automaticamente.')
            self.note.setWordWrap(True)
            outer.addWidget(self.note)
            self.volumes = []
            self.refresh()

        def _error(self, detail: str):
            QMessageBox.warning(self, 'Wolf Mount Manager', detail)
            self.note.setText(detail)

        def selected(self):
            rows = self.table.selectionModel().selectedRows()
            if not rows:
                self._error('Selecione um volume na tabela.')
                return None
            return self.volumes[rows[0].row()]

        def refresh(self):
            selected = None
            rows = self.table.selectionModel().selectedRows()
            if rows and rows[0].row() < len(self.volumes):
                selected = self.volumes[rows[0].row()]['path']
            try:
                result = run_command(['wolf-live-mount-backend', 'list'], 15)
                if result.returncode:
                    raise RuntimeError(result.stderr.strip() or 'Inventário indisponível')
                self.volumes = [v for v in json.loads(result.stdout) if v['type'] in ('part', 'lvm')]
            except (OSError, subprocess.TimeoutExpired, ValueError, RuntimeError) as exc:
                self._error(str(exc))
                return
            self.table.setRowCount(len(self.volumes))
            for row, item in enumerate(self.volumes):
                mounted = ', '.join(item['mountpoints']) if item['mountpoints'] else (
                    'Disponível (somente leitura)' if item['supported'] else 'Não montável diretamente')
                values = (item['path'], f"{item['size'] / (1024**3):.1f} GiB",
                          item['fstype'] or '(sem FS)', item['label'] or '—', mounted)
                for col, label in enumerate(values):
                    self.table.setItem(row, col, QTableWidgetItem(label))
                if item['path'] == selected:
                    self.table.selectRow(row)
            self.note.setText('Dica: LVM2_member é um volume físico; selecione o LV ext4 correspondente.')

        def mount(self):
            item = self.selected()
            if item is None:
                return
            if not item['supported']:
                self._error('Não é uma partição/LV com sistema de arquivos suportado. PV LVM e volumes criptografados não são montados aqui.')
                return
            if item['mountpoints']:
                self._error('Já está montado em: ' + ', '.join(item['mountpoints']))
                return
            if QMessageBox.question(self, 'Montar somente leitura',
                f"Montar {item['path']} ({item['fstype']}) exclusivamente em modo SOMENTE LEITURA?\n"
                'Nenhuma reparação, ativação LVM ou escrita será solicitada.') != QMessageBox.StandardButton.Yes:
                return
            try:
                result = run_command(['sudo', '-n', 'wolf-live-mount-backend', 'mount', item['path']], 60)
                if result.returncode:
                    raise RuntimeError(result.stderr.strip() or result.stdout.strip())
                dest = result.stdout.strip()
                QMessageBox.information(self, 'Montado em leitura', f'Montado com sucesso em:\n{dest}')
                self.refresh()
                subprocess.Popen(['pcmanfm-qt', dest], start_new_session=True)
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
                self._error(str(exc))

        def open_folder(self):
            item = self.selected()
            if item is None:
                return
            paths = item['mountpoints']
            if not paths:
                self._error('Volume não montado. Utilize Montar somente leitura primeiro.')
                return
            # An existing mount may be RW, and is not changed by this application.
            target = paths[0]
            if not target.startswith('/run/media/wolf/wolf-ro-'):
                QMessageBox.warning(self, 'Montagem externa',
                    f'O volume já estava montado em {target}. O Wolf NÃO controla '
                    'suas permissões de escrita. Proceda com cuidado.')
            try:
                subprocess.Popen(['pcmanfm-qt', target], start_new_session=True)
            except OSError as exc:
                self._error(str(exc))

        def unmount(self):
            item = self.selected()
            if item is None:
                return
            if QMessageBox.question(self, 'Desmontar volume',
                    f"Desmontar {item['path']}? Feche antes os arquivos abertos no explorador.") != QMessageBox.StandardButton.Yes:
                return
            try:
                result = run_command(['sudo', '-n', 'wolf-live-mount-backend', 'unmount', item['path']], 45)
                if result.returncode:
                    raise RuntimeError(result.stderr.strip() or result.stdout.strip())
                self.refresh()
            except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
                self._error(str(exc))

    window = Window()
    window.show()
    return app.exec()


if __name__ == '__main__':
    raise SystemExit(ui_main())
