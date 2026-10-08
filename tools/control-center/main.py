#!/usr/bin/env python3
"""Wolf Control Center 0.1.2 — interface de administração manual para KDE Plasma."""
from __future__ import annotations

import sys
import os
from pathlib import Path

from backend import (
    VERSION, helper_file, status_text, enable_notifier,
    notifier_installed, autosuggestions_status,
    disable_notifier, autosuggestions_runtime_status,
)

try:
    from PySide6.QtCore import Qt, QProcess, QTimer
    from PySide6.QtGui import QIcon
    from PySide6.QtWidgets import (
        QApplication, QHBoxLayout, QVBoxLayout, QMainWindow, QWidget,
        QFrame, QLabel, QPushButton, QListWidget, QStackedWidget,
        QPlainTextEdit, QMessageBox, QScrollArea,
    )
except ImportError:
    print("[ERRO] PySide6 ausente. Instale com: sudo pacman -S --needed pyside6", file=sys.stderr)
    sys.exit(2)

ICON = "/usr/share/icons/hicolor/scalable/apps/wolf-linux-kickoff.svg"


class Center(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(f"Wolf Control Center {VERSION}")
        self.resize(920, 660)
        self.setMinimumSize(710, 510)
        if Path(ICON).exists():
            self.setWindowIcon(QIcon(ICON))
        self.proc: QProcess | None = None
        self.activity_buttons: list[QPushButton] = []
        self._setup_ui()
        self.refresh()

    def _setup_ui(self) -> None:
        self.setStyleSheet("""
          QMainWindow, QWidget#root { background: #16181c; color: #e9ebee; }
          QFrame#card { background: #23262c; border: 1px solid #343941; border-radius: 10px; }
          QLabel#sectionTitle { color: #ffffff; font-size: 21px; font-weight: 650; }
          QLabel#subtitle { color: #bfc5ce; font-size: 13px; }
          QPushButton { padding: 10px 14px; border: 1px solid #606773; border-radius: 6px; background: #363b43; color: #f9fafb; }
          QPushButton:hover { background: #454c55; }
          QPushButton:disabled { color: #80868e; background: #2c3037; }
          QListWidget { background: #202328; color: #e9ebee; border: none; padding: 10px; font-size: 15px; }
          QListWidget::item { padding: 14px 9px; border-radius: 6px; }
          QListWidget::item:selected { background: #505963; color: white; }
          QPlainTextEdit { background: #101215; color: #c9d0d8; border: 1px solid #353a42; border-radius: 6px; font-family: monospace; }
        """)
        root = QWidget(objectName="root")
        self.setCentralWidget(root)
        outer = QHBoxLayout(root)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)
        self.nav = QListWidget()
        self.nav.setFixedWidth(190)
        for title in ("Visão geral", "Monitores", "Controles", "Inicialização", "Sistema"):
            self.nav.addItem(title)
        outer.addWidget(self.nav)
        right = QWidget(objectName="root")
        rlayout = QVBoxLayout(right)
        rlayout.setContentsMargins(26, 20, 26, 20)
        rlayout.setSpacing(14)
        header = QLabel("Wolf Control Center", objectName="sectionTitle")
        rlayout.addWidget(header)
        subtitle = QLabel("Configurações e diagnósticos do Wolf Linux • helpers sob demanda", objectName="subtitle")
        subtitle.setWordWrap(True)
        rlayout.addWidget(subtitle)
        self.pages = QStackedWidget()
        rlayout.addWidget(self.pages, 1)
        self.info_label = QLabel("", objectName="subtitle")
        rlayout.addWidget(self.info_label)
        self.output = QPlainTextEdit()
        self.output.setReadOnly(True)
        self.output.setFixedHeight(140)
        self.output.setPlaceholderText("Saída dos comandos executados... (nenhum helper é monitorado continuamente)")
        rlayout.addWidget(self.output)
        row = QHBoxLayout()
        b_refresh = self._button("Atualizar diagnóstico", self.refresh, activity=False)
        row.addWidget(b_refresh)
        row.addStretch()
        b_clear = self._button("Limpar saída", self.output.clear, activity=False)
        row.addWidget(b_clear)
        rlayout.addLayout(row)
        outer.addWidget(right, 1)
        self._build_pages()
        self.nav.currentRowChanged.connect(self.pages.setCurrentIndex)
        self.nav.setCurrentRow(0)

    def _page(self) -> QVBoxLayout:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        page = QWidget(objectName="root")
        layout = QVBoxLayout(page)
        layout.setContentsMargins(4, 6, 8, 6)
        layout.setSpacing(14)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop)
        scroll.setWidget(page)
        self.pages.addWidget(scroll)
        return layout

    def _card(self, parent: QVBoxLayout, title: str, description: str) -> QHBoxLayout:
        frame = QFrame(objectName="card")
        box = QVBoxLayout(frame)
        box.setContentsMargins(18, 15, 18, 15)
        h = QLabel(title)
        h.setStyleSheet("font-size: 16px; font-weight: bold; color: white;")
        h.setWordWrap(True)
        box.addWidget(h)
        d = QLabel(description, objectName="subtitle")
        d.setWordWrap(True)
        box.addWidget(d)
        actions = QVBoxLayout()
        actions.setSpacing(7)
        box.addLayout(actions)
        parent.addWidget(frame)
        return actions

    def _button(self, title: str, callback, activity: bool = True) -> QPushButton:
        button = QPushButton(title)
        button.clicked.connect(callback)
        if activity:
            self.activity_buttons.append(button)
        return button

    def _build_pages(self) -> None:
        overview = self._page()
        self.system_label = QLabel("", objectName="subtitle")
        self.system_label.setWordWrap(True)
        actions = self._card(overview, "Estado da instalação", "Informações de sessão, versão, plugins e configurações.")
        actions.addWidget(self._button("Exibir relatório", self._show_report))
        overview.addWidget(self.system_label)

        monitors = self._page()
        actions = self._card(monitors, "Painéis por monitor", "Cria painéis ausentes sem modificar o Kickoff existente. Não instala watcher.")
        actions.addWidget(self._button("Consultar estado", lambda: self._helper("monitor", "status")))
        actions.addWidget(self._button("Reconciliar painéis (manual)", self._reconcile))
        actions = self._card(monitors, "Voltar à configuração anterior", "Restaura o último backup salvo pelo helper MultiMonitor. Use somente se houver problema de layout.")
        actions.addWidget(self._button("Restaurar backup", self._restore))
        actions = self._card(monitors, "Identidade do Plasma", "O branding inicial é aplicado apenas uma vez. Você pode consultar seu estado ou reaplicá-lo manualmente.")
        actions.addWidget(self._button("Estado do branding", lambda: self._helper("branding", "status")))
        actions.addWidget(self._button("Reaplicar branding", lambda: self._confirm_helper("branding", "apply", "Reaplicar tema, wallpaper e ícone Kickoff?")))

        game = self._page()
        actions = self._card(game, "Gamepad USB/Bluetooth", "Executa o assistente Wolf existente em um terminal interativo. Nada é configurado sem as escolhas do assistente.")
        actions.addWidget(self._button("Abrir assistente de controles", lambda: self._terminal("gamepad")))

        start = self._page()
        self.octopi_label = QLabel("", objectName="subtitle")
        actions = self._card(start, "Octopi Notifier", "Avisos de atualizações ao entrar no KDE. Não instala atualizações automaticamente.")
        actions.addWidget(self._button("Ativar no login", self._enable_octopi))
        actions.addWidget(self._button("Desativar no próximo login", self._disable_octopi))
        start.addWidget(self.octopi_label)
        self.zsh_label = QLabel("", objectName="subtitle")
        actions = self._card(start, "Zsh Autosuggestions", "Confere plugin, configuração fg=250 e carregamento em uma nova sessão Zsh.")
        actions.addWidget(self._button("Verificar plugin", self._check_zsh))
        start.addWidget(self.zsh_label)

        system = self._page()
        actions = self._card(system, "Gerenciador do GRUB", "Abre o assistente existente em um terminal. Mudanças de boot exigem confirmação e permissões próprias.")
        actions.addWidget(self._button("Abrir GRUB Manager", lambda: self._terminal("grub")))
        actions = self._card(system, "Validação guiada", "Inicia a sequência de diagnóstico Wolf no Konsole, sem aplicar alterações automaticamente.")
        actions.addWidget(self._button("Abrir validador", self._validator))

    def _log(self, value: str) -> None:
        self.output.appendPlainText(value)
        self.output.verticalScrollBar().setValue(self.output.verticalScrollBar().maximum())

    def _warn(self, message: str) -> None:
        self._log("[ERRO] " + message)
        QMessageBox.warning(self, "Wolf Control Center", message)

    def _confirm(self, question: str) -> bool:
        return QMessageBox.question(self, "Confirmar ação", question,
                                     QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                                     QMessageBox.StandardButton.No) == QMessageBox.StandardButton.Yes

    def _run(self, name: str, args: list[str], timeout_ms: int = 90000) -> None:
        if self.proc is not None:
            self._warn("Já existe uma operação em andamento.")
            return
        if not Path(args[0]).exists():
            self._warn("Arquivo de comando ausente: " + args[0])
            return
        self._log("▶ " + name)
        self.proc = QProcess(self)
        self.proc.setProgram(args[0])
        self.proc.setArguments(args[1:])
        self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        for b in self.activity_buttons:
            b.setEnabled(False)
        self.info_label.setText("Operação em andamento...")
        self.proc.readyReadStandardOutput.connect(self._read_proc)
        self.proc.finished.connect(self._finished)
        self.proc.errorOccurred.connect(lambda _e: self._log("[ERRO] " + (self.proc.errorString() if self.proc else "Falha do processo")))
        self.proc.start()
        QTimer.singleShot(timeout_ms, lambda current=self.proc: self._timeout_process(current))

    def _read_proc(self) -> None:
        if self.proc:
            chunk = bytes(self.proc.readAllStandardOutput()).decode("utf-8", "replace").rstrip()
            if chunk:
                self._log(chunk)

    def _finished(self, code: int, _status) -> None:
        self._read_proc()
        self._log(f"[{'OK' if code == 0 else 'ERRO'}] Processo terminou com código {code}")
        for b in self.activity_buttons:
            b.setEnabled(True)
        self.proc = None
        self.info_label.setText("Pronto")
        self.refresh()

    def _timeout_process(self, current: QProcess) -> None:
        if self.proc is current and current.state() != QProcess.ProcessState.NotRunning:
            self._log("[AVISO] Tempo máximo atingido; finalizando processo.")
            current.kill()

    def _helper(self, key: str, action: str) -> None:
        path = helper_file(key)
        if not path.is_file():
            self._warn(f"Helper não instalado: {path}")
            return
        self._run(f"{key}: {action}", [str(path), action])

    def _confirm_helper(self, key: str, action: str, question: str) -> None:
        if self._confirm(question):
            self._helper(key, action)

    def _reconcile(self) -> None:
        self._confirm_helper("monitor", "reconcile", "Reconciliar os painéis disponíveis agora? A ação funciona mesmo após restaurar um backup e não reativa a política automática.")

    def _restore(self) -> None:
        self._confirm_helper("monitor", "restore", "Restaurar o backup anterior de painéis? O Plasma poderá reiniciar.")

    def _terminal(self, key: str) -> None:
        path = helper_file(key)
        if not path.is_file():
            self._warn(f"Helper não instalado: {path}")
            return
        self._open_konsole([str(path)])

    def _validator(self) -> None:
        path = "/usr/local/bin/wolf-validate-helpers"
        if not Path(path).exists():
            self._warn("Validador guiado não encontrado")
            return
        self._open_konsole([path])

    def _open_konsole(self, args: list[str]) -> None:
        if not __import__("shutil").which("konsole"):
            self._warn("Konsole não encontrado")
            return
        # No shell interpolation. User sees all prompts, including sudo, in terminal.
        launch_result = QProcess.startDetached("konsole", ["--hold", "-e", *args])
        started = launch_result[0] if isinstance(launch_result, tuple) else launch_result
        if not started:
            self._warn("Não foi possível abrir o Konsole")
        else:
            self._log("[OK] Assistente aberto no Konsole.")

    def _enable_octopi(self) -> None:
        if not notifier_installed():
            self._warn("Octopi Notifier não instalado: verifique seu pacote Octopi.")
            return
        if not self._confirm("Criar/atualizar o autostart Octopi Notifier deste usuário? Uma cópia anterior será preservada."):
            return
        try:
            target = enable_notifier()
            self._log(f"[OK] Autostart criado: {target}\nValerá a partir do próximo login.")
        except OSError as exc:
            self._warn(str(exc))
        self.refresh()

    def _disable_octopi(self) -> None:
        if not notifier_installed():
            self._warn("Octopi Notifier não instalado.")
            return
        if not self._confirm("Desativar Octopi Notifier no próximo login? O processo atual não será interrompido."):
            return
        try:
            target = disable_notifier()
            self._log(f"[OK] Octopi desativado no login: {target}")
        except (OSError, RuntimeError) as exc:
            self._warn(str(exc))
        self.refresh()

    def _check_zsh(self) -> None:
        self._log("Zsh: " + autosuggestions_status())
        self._log("Zsh runtime: " + autosuggestions_runtime_status())
        self.refresh()

    def _show_report(self) -> None:
        self._log("\n" + status_text())

    def refresh(self) -> None:
        summary = status_text()
        self.system_label.setText(summary.replace("\n", "\n"))
        from backend import notifier_status
        self.octopi_label.setText(notifier_status())
        self.zsh_label.setText(autosuggestions_status())
        self.info_label.setText("Pronto" if self.proc is None else "Operação em andamento...")

    def closeEvent(self, event) -> None:
        if self.proc is not None:
            self.proc.kill()
            self.proc.waitForFinished(2000)
        super().closeEvent(event)


def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName("Wolf Control Center")
    app.setDesktopFileName("wolf-control-center")
    win = Center()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
