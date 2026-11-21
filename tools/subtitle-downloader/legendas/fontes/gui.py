#!/usr/bin/env python3
"""Native Qt interface for Wolf Subtitle Downloader."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PySide6.QtCore import QProcess, QStandardPaths, Qt
from PySide6.QtWidgets import (QApplication, QComboBox, QFileDialog, QFormLayout,
    QHBoxLayout, QLabel, QLineEdit, QMainWindow, QMessageBox, QProgressBar, QGroupBox,
    QPushButton, QTabWidget, QTableWidget, QTableWidgetItem, QVBoxLayout,
    QWidget, QHeaderView, QAbstractItemView)

APPDIR = Path(__file__).resolve().parent
VENV_PYTHON = APPDIR / '.venv' / 'bin' / 'python'
VIDEO_FILTER = 'Vídeos (*.mkv *.mp4 *.avi *.mov *.webm *.m4v *.wmv *.mpg *.mpeg *.ts);;Todos os arquivos (*)'


class Window(QMainWindow):
    def __init__(self, filename=''):
        super().__init__()
        self.setWindowTitle('Wolf Subtitle Downloader 0.3-preview3')
        self.resize(1000, 750)
        self.setMinimumSize(760, 590)
        self.setAcceptDrops(True)
        self.awaiting = ''
        self.autodownload = False
        self.results = []
        self.buffer = bytearray()
        self.worker = QProcess(self)
        self.worker.setProgram(str(VENV_PYTHON))
        self.worker.setArguments([str(APPDIR / 'backend.py'), '--rpc'])
        self.worker.readyReadStandardOutput.connect(self.read_output)
        self.worker.readyReadStandardError.connect(self.read_errors)
        self.worker.finished.connect(self.worker_finished)
        self.worker.errorOccurred.connect(self.worker_failed)
        self.build_ui()
        if filename:
            self.choose_file(filename)
        if not VENV_PYTHON.exists():
            self.show_status('Dependências ausentes: execute novamente ./install.sh', True)
            self.search_btn.setEnabled(False)
            self.best_btn.setEnabled(False)
            return
        self.show_status('Inicializando o mecanismo de legendas…')
        self.worker.start()

    def build_ui(self):
        root = QWidget()
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setSpacing(12)
        heading = QLabel('Wolf Subtitle Downloader')
        font = heading.font()
        font.setPointSize(font.pointSize() + 5)
        font.setBold(True)
        heading.setFont(font)
        layout.addWidget(heading)
        layout.addWidget(QLabel('Pesquisa livre por palavras ou busca por arquivo/hash. Legendas salvas em .srt.'))
        self.tabs = QTabWidget()
        tab_file = QWidget()
        f_layout = QFormLayout(tab_file)
        row_file = QHBoxLayout()
        self.file_edit = QLineEdit()
        self.file_edit.setPlaceholderText('Selecione um vídeo ou arraste-o para esta janela')
        self.file_edit.textChanged.connect(self.clear_results)
        browse = QPushButton('Escolher…')
        browse.clicked.connect(self.browse_file)
        row_file.addWidget(self.file_edit, 1)
        row_file.addWidget(browse)
        f_layout.addRow('Arquivo:', row_file)
        f_layout.addRow('', QLabel('O vídeo é analisado por nome, metadados e hash quando disponíveis.'))
        tab_title = QWidget()
        t_layout = QFormLayout(tab_title)
        self.title_edit = QLineEdit()
        self.title_edit.setPlaceholderText('Ex.: avengers, Interstellar, The Office S02E01 — ano opcional')
        self.title_edit.textChanged.connect(self.clear_results)
        t_layout.addRow('Título:', self.title_edit)
        row_folder = QHBoxLayout()
        self.folder_edit = QLineEdit(QStandardPaths.writableLocation(QStandardPaths.StandardLocation.DownloadLocation) or str(Path.home()))
        self.folder_edit.textChanged.connect(self.clear_results)
        choose_dir = QPushButton('Pasta…')
        choose_dir.clicked.connect(self.browse_folder)
        row_folder.addWidget(self.folder_edit, 1)
        row_folder.addWidget(choose_dir)
        t_layout.addRow('Salvar em:', row_folder)
        self.tabs.addTab(tab_file, 'Tenho o vídeo')
        self.tabs.addTab(tab_title, 'Buscar pelo nome')
        self.tabs.currentChanged.connect(self.clear_results)
        layout.addWidget(self.tabs)
        self.account = QGroupBox('OpenSubtitles.com — credenciais armazenadas no chaveiro do sistema')
        account_layout = QFormLayout(self.account)
        login_row = QHBoxLayout()
        self.os_user = QLineEdit()
        self.os_user.setPlaceholderText('Usuário OpenSubtitles.com')
        self.os_password = QLineEdit()
        self.os_password.setPlaceholderText('Senha (salva somente no chaveiro, se solicitado)')
        self.os_password.setEchoMode(QLineEdit.EchoMode.Password)
        login_row.addWidget(self.os_user)
        login_row.addWidget(self.os_password)
        account_layout.addRow('Login:', login_row)
        self.os_apikey = QLineEdit()
        self.os_apikey.setEchoMode(QLineEdit.EchoMode.Password)
        self.os_apikey.setPlaceholderText('Opcional: chave pessoal da API (Subliminal já inclui a própria)')
        account_layout.addRow('API key:', self.os_apikey)
        self.credentials_hint = QLabel('Verificando o chaveiro…')
        self.credentials_hint.setWordWrap(True)
        account_layout.addRow('Chaveiro:', self.credentials_hint)
        save_row = QHBoxLayout()
        self.save_creds_btn = QPushButton('Salvar no chaveiro')
        self.save_creds_btn.clicked.connect(self.save_credentials)
        self.remove_creds_btn = QPushButton('Excluir credenciais salvas')
        self.remove_creds_btn.clicked.connect(self.remove_credentials)
        save_row.addWidget(self.save_creds_btn)
        save_row.addWidget(self.remove_creds_btn)
        save_row.addStretch(1)
        account_layout.addRow('', save_row)
        self.credentials_note = QLabel('Após salvar, os campos ficam vazios. O login salvo é usado automaticamente '
                                       'pela pesquisa e pelo menu de contexto. Para um login temporário, '
                                       'preencha usuário e senha e pesquise sem salvar.')
        self.credentials_note.setWordWrap(True)
        account_layout.addRow('', self.credentials_note)
        for edit in (self.os_user, self.os_password, self.os_apikey):
            edit.textChanged.connect(self.clear_results)
        layout.addWidget(self.account)
        top = QHBoxLayout()
        top.addWidget(QLabel('Idioma:'))
        self.lang_combo = QComboBox()
        self.lang_combo.addItem('Português (Brasil)', 'pt-BR')
        self.lang_combo.addItem('Português (Portugal)', 'pt-PT')
        self.lang_combo.addItem('Inglês', 'en')
        self.lang_combo.currentIndexChanged.connect(self.clear_results)
        top.addWidget(self.lang_combo)
        top.addWidget(QLabel('Fonte:'))
        self.provider_combo = QComboBox()
        self.provider_combo.addItem('Todas', 'all')
        self.provider_combo.addItem('Podnapisi', 'podnapisi')
        self.provider_combo.addItem('OpenSubtitles.com', 'opensubtitlescom')
        self.provider_combo.currentIndexChanged.connect(self.clear_results)
        top.addWidget(self.provider_combo)
        top.addStretch(1)
        self.search_btn = QPushButton('Buscar legendas')
        self.search_btn.clicked.connect(lambda: self.search(False))
        self.best_btn = QPushButton('Baixar melhor legenda')
        self.best_btn.clicked.connect(self.best)
        top.addWidget(self.search_btn)
        top.addWidget(self.best_btn)
        layout.addLayout(top)
        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(['Filme / série', 'Ano', 'Provedor', 'Versão / detalhes', 'Afinidade'])
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Interactive)
        self.table.setColumnWidth(0, 205)
        self.table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        self.table.horizontalHeader().setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        self.table.itemSelectionChanged.connect(self.update_buttons)
        self.table.doubleClicked.connect(self.download_selected)
        layout.addWidget(self.table, 1)
        bottom = QHBoxLayout()
        self.status = QLabel('Pronto para pesquisar.')
        self.status.setWordWrap(True)
        bottom.addWidget(self.status, 1)
        self.progress = QProgressBar()
        self.progress.setFixedWidth(100)
        self.progress.setRange(0, 0)
        self.progress.hide()
        bottom.addWidget(self.progress)
        self.download_btn = QPushButton('Baixar selecionada')
        self.download_btn.clicked.connect(self.download_selected)
        bottom.addWidget(self.download_btn)
        layout.addLayout(bottom)
        self.update_buttons()

    def show_status(self, message, is_error=False):
        self.status.setText(message)
        self.status.setStyleSheet('color: #df6d6d;' if is_error else '')

    def clear_results(self, *_):
        self.results = []
        self.table.setRowCount(0)
        self.update_buttons()

    def choose_file(self, path):
        self.tabs.setCurrentIndex(0)
        self.file_edit.setText(path)

    def browse_file(self):
        path, _ = QFileDialog.getOpenFileName(self, 'Selecionar vídeo', str(Path.home()), VIDEO_FILTER)
        if path:
            self.choose_file(path)

    def browse_folder(self):
        path = QFileDialog.getExistingDirectory(self, 'Selecionar destino', self.folder_edit.text())
        if path:
            self.folder_edit.setText(path)

    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() and any(url.isLocalFile() for url in event.mimeData().urls()):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dropEvent(self, event):
        files = [u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile()]
        if files:
            self.choose_file(files[0])
            event.acceptProposedAction()

    def set_busy(self, busy):
        self.progress.setVisible(busy)
        self.search_btn.setEnabled(not busy and self.worker.state() == QProcess.ProcessState.Running)
        self.best_btn.setEnabled(not busy and self.worker.state() == QProcess.ProcessState.Running)
        self.download_btn.setEnabled(not busy and bool(self.results) and self.table.currentRow() >= 0)

    def update_buttons(self):
        self.download_btn.setEnabled(not bool(self.awaiting) and bool(self.results) and self.table.currentRow() >= 0)

    def dispatch(self, payload):
        if self.worker.state() != QProcess.ProcessState.Running:
            QMessageBox.warning(self, 'Mecanismo indisponível', 'O serviço de busca não está em execução. Reinstale as dependências.')
            return False
        self.worker.write((json.dumps(payload, ensure_ascii=False) + '\n').encode('utf-8'))
        return True

    def search(self, auto=False):
        if self.awaiting:
            return
        self.clear_results()
        lang = self.lang_combo.currentData()
        if self.tabs.currentIndex() == 0:
            path = self.file_edit.text().strip()
            if not Path(path).is_file():
                QMessageBox.warning(self, 'Arquivo inexistente', 'Escolha um vídeo que exista no computador.')
                return
            payload = {'action': 'search', 'source': 'file', 'path': path, 'language': lang}
        else:
            title = self.title_edit.text().strip()
            if not title:
                QMessageBox.warning(self, 'Título vazio', 'Digite o nome do filme ou episódio.')
                return
            folder = self.folder_edit.text().strip()
            if not Path(folder).is_dir():
                QMessageBox.warning(self, 'Destino inválido', 'Escolha uma pasta existente para salvar.')
                return
            payload = {'action': 'search', 'source': 'title', 'title': title, 'output_dir': folder, 'language': lang}
        # Nonempty fields override keyring only for this search; never put
        # credentials in command-line args or a local settings file.
        payload['provider'] = self.provider_combo.currentData()
        if self.os_user.text().strip() or self.os_password.text() or self.os_apikey.text().strip():
            payload['username'] = self.os_user.text().strip()
            payload['password'] = self.os_password.text()
            payload['apikey'] = self.os_apikey.text().strip()
        self.autodownload = auto
        if self.dispatch(payload):
            self.awaiting = 'search'
            self.set_busy(True)
            self.show_status('Consultando provedores. Título parcial é permitido; o resultado depende do acervo e do serviço.')

    def save_credentials(self):
        if self.awaiting:
            return
        username = self.os_user.text().strip()
        password = self.os_password.text()
        if not username or not password:
            QMessageBox.warning(self, 'Credenciais incompletas',
                                'Preencha usuário e senha antes de salvar no chaveiro.')
            return
        payload = {'action': 'credentials_save', 'username': username,
                   'password': password, 'apikey': self.os_apikey.text().strip()}
        if self.dispatch(payload):
            self.awaiting = 'credentials_save'
            self.set_busy(True)
            self.credentials_hint.setText('Armazenando no chaveiro…')

    def remove_credentials(self):
        if self.awaiting:
            return
        answer = QMessageBox.question(self, 'Excluir credenciais',
            'Deseja excluir do chaveiro as credenciais do OpenSubtitles.com usadas por este aplicativo?')
        if answer != QMessageBox.StandardButton.Yes:
            return
        if self.dispatch({'action': 'credentials_remove'}):
            self.awaiting = 'credentials_remove'
            self.set_busy(True)
            self.credentials_hint.setText('Removendo credenciais do chaveiro…')

    def set_credentials_status(self, msg):
        if msg.get('error'):
            self.credentials_hint.setText('Chaveiro indisponível: ' + str(msg['error']))
            self.remove_creds_btn.setEnabled(False)
        elif msg.get('stored'):
            self.credentials_hint.setText('Credenciais salvas para: ' + str(msg.get('username') or 'conta'))
            self.remove_creds_btn.setEnabled(True)
        else:
            self.credentials_hint.setText('Nenhum login acessível (não salvo ou chaveiro bloqueado). O Podnapisi funciona sem conta.')
            self.remove_creds_btn.setEnabled(False)

    def best(self):
        if self.results:
            if self.tabs.currentIndex() == 1 and self.ambiguous_title_results():
                QMessageBox.information(self, 'Escolha o filme',
                    'A pesquisa retornou títulos/anos diferentes. Selecione manualmente a legenda correta.')
                return
            self.download_index(0)
        else:
            self.search(auto=True)

    def ambiguous_title_results(self):
        """Avoid auto-downloading an arbitrary sequel from a broad query."""
        return len({(r.get('title', '').casefold(), r.get('year', '')) for r in self.results}) > 1

    def download_selected(self, *_):
        if self.table.currentRow() >= 0:
            self.download_index(self.table.currentRow())

    def download_index(self, index):
        if self.awaiting or not self.results:
            return
        if self.dispatch({'action': 'download', 'index': self.results[index]['index']}):
            self.awaiting = 'download'
            self.set_busy(True)
            self.show_status('Baixando e salvando legenda…')

    def read_output(self):
        self.buffer.extend(bytes(self.worker.readAllStandardOutput()))
        while b'\n' in self.buffer:
            line, _, remaining = self.buffer.partition(b'\n')
            self.buffer = bytearray(remaining)
            try:
                msg = json.loads(line.decode('utf-8'))
            except (ValueError, UnicodeDecodeError):
                continue
            self.handle_response(msg)

    def read_errors(self):
        # Read to avoid filling the child's stderr pipe; detailed errors stay in its console logs.
        data = bytes(self.worker.readAllStandardError()).decode('utf-8', errors='replace')
        if data:
            print('[wolf-subtitle-backend]', data, file=sys.stderr, end='')

    def handle_response(self, msg):
        event = msg.get('event')
        if event == 'ready':
            if not self.awaiting:
                self.show_status('Pronto. Fontes: Podnapisi + OpenSubtitles.com; busca livre aceita termos incompletos.')
                self.set_busy(False)
                self.dispatch({'action': 'credentials_status'})
        elif event == 'credentials_status':
            self.set_credentials_status(msg)
        elif event in ('credentials_saved', 'credentials_removed'):
            self.awaiting = ''
            self.set_busy(False)
            # Don't keep account password in Qt input controls after persisting.
            self.os_password.clear()
            self.os_user.clear()
            self.os_apikey.clear()
            self.set_credentials_status(msg)
            if event == 'credentials_saved':
                self.show_status('Credenciais armazenadas no chaveiro. O menu de contexto já poderá reutilizá-las.')
            else:
                self.show_status('Credenciais do OpenSubtitles.com excluídas do chaveiro.')
        elif event == 'results':
            self.awaiting = ''
            self.results = msg.get('entries', [])
            self.table.setRowCount(len(self.results))
            for row, item in enumerate(self.results):
                for col, value in enumerate((item.get('title', ''), item.get('year', ''), item['provider'], item['release'], ('HASH' if item.get('hash_match') else str(item['score'])))):
                    cell = QTableWidgetItem(str(value))
                    if col == 4:
                        cell.setTextAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
                    self.table.setItem(row, col, cell)
            if self.results:
                self.table.selectRow(0)
                self.show_status(f'{len(self.results)} resultados. Confira filme, ano e versão antes de baixar. Afinidade não é porcentagem.' + (' Avisos: ' + ' | '.join(msg.get('warnings', [])) if msg.get('warnings') else ''))
            else:
                self.show_status('Nenhuma legenda encontrada. ' + ('Falhas: ' + ' | '.join(msg.get('warnings', [])) if msg.get('warnings') else 'Experimente outro termo, idioma ou provedor.'))
            self.set_busy(False)
            if self.results and self.autodownload:
                self.autodownload = False
                if self.tabs.currentIndex() == 1 and self.ambiguous_title_results():
                    QMessageBox.information(self, 'Escolha o filme',
                        'Foram encontrados vários filmes. Selecione o título e ano corretos antes de baixar.')
                else:
                    self.download_index(0)
        elif event == 'saved':
            self.awaiting = ''
            self.set_busy(False)
            self.show_status('Legenda salva: ' + str(msg.get('path', '')))
            QMessageBox.information(self, 'Legenda salva', 'Download concluído:\n' + str(msg.get('path', '')))
        elif event == 'error':
            was_credentials = self.awaiting.startswith('credentials_')
            self.awaiting = ''
            self.autodownload = False
            self.set_busy(False)
            message = str(msg.get('message', 'Erro desconhecido'))
            self.show_status(message, True)
            if was_credentials:
                self.dispatch({'action': 'credentials_status'})
            QMessageBox.warning(self, 'Operação não concluída', message)

    def worker_finished(self, code, _status):
        self.awaiting = ''
        self.progress.hide()
        self.search_btn.setEnabled(False)
        self.best_btn.setEnabled(False)
        self.download_btn.setEnabled(False)
        self.show_status(f'Mecanismo encerrado (código {code}). Reinicie o aplicativo.', True)

    def worker_failed(self, _error):
        self.show_status('Não foi possível iniciar o mecanismo de legendas.', True)

    def closeEvent(self, event):
        if self.worker.state() != QProcess.ProcessState.NotRunning:
            self.worker.kill()
            self.worker.waitForFinished(1500)
        super().closeEvent(event)


def main():
    app = QApplication(sys.argv)
    app.setApplicationName('Wolf Subtitle Downloader')
    app.setDesktopFileName('wolf-subtitle-downloader')
    win = Window(sys.argv[1] if len(sys.argv) > 1 else '')
    win.show()
    return app.exec()


if __name__ == '__main__':
    sys.exit(main())
