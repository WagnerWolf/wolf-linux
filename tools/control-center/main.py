#!/usr/bin/env python3
"""Wolf Control Center 0.3 preview — interface desktop-aware LXQt/Plasma."""
from __future__ import annotations

import sys
import os
from pathlib import Path

from backend import (
    VERSION, helper_file, status_text, enable_notifier,
    notifier_installed, autosuggestions_status,
    disable_notifier, autosuggestions_runtime_status, desktop_kind,
)
from lxqt_support import create_snapshot, list_backups, diagnostic_text
from wolf_profile import panel_checks, profile_report, export_report, apply_mime_defaults, mime_checks

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
        self.desktop_kind = desktop_kind()
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
        for title in ("Visão geral", "Monitores", "Aparência e atalhos", "Controles", "Inicialização", "Sistema"):
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
        if self.desktop_kind == "lxqt-x11":
            actions = self._card(monitors, "Monitores LXQt / X11", "Editor Wolf com organização visual, modos XRandR e reversão automática. Não altera os painéis automaticamente.")
            actions.addWidget(self._button("Configurar monitores (Wolf)", self._edit_monitors, activity=False))
            actions = self._card(monitors, "Painéis LXQt", "Reconstrói os painéis após conectar um monitor e registra a lista correta por QSettings (Fix5 validado), com backup e reinício do painel; sem watcher permanente.")
            actions.addWidget(self._button("Verificar painéis e monitores", self._panel_status, activity=False))
            actions.addWidget(self._button("Diagnóstico detalhado das telas e painéis", self._panel_diagnose, activity=False))
            actions.addWidget(self._button("Aplicar painéis aos monitores", self._apply_panels))
            actions.addWidget(self._button("Consultar configuração dos painéis", self._show_lxqt_status, activity=False))
            actions.addWidget(self._button("Salvar snapshot de LXQt e Openbox", self._snapshot_lxqt))
            actions.addWidget(self._button("Listar snapshots", self._list_lxqt_backups, activity=False))
            actions.addWidget(self._button("Auditar painéis e telas Wolf", self._audit_lxqt_panels, activity=False))
            actions = self._card(monitors, "Auditoria do perfil Wolf", "Confere separação por monitor, bandeja, lançadores, Alt+Tab e aplicativos sem alterar a sessão.")
            actions.addWidget(self._button("Verificar perfil completo", self._audit_wolf_profile, activity=False))
            actions.addWidget(self._button("Exportar relatório para arquivo", self._export_wolf_report, activity=False))
            actions = self._card(monitors, "Restaurar configurações", "A restauração é feita fora do LXQt, para evitar que o painel sobrescreva arquivos em execução.")
            actions.addWidget(self._button("Mostrar instruções de restauração", self._restore_instructions, activity=False))
        elif self.desktop_kind == "plasma":
            actions = self._card(monitors, "Painéis Plasma", "Reutiliza o helper Plasma original, apenas nesta sessão. Não instala watcher.")
            actions.addWidget(self._button("Consultar estado", lambda: self._helper("monitor", "status")))
            actions.addWidget(self._button("Reconciliar painéis (manual)", self._reconcile))
            actions = self._card(monitors, "Voltar à configuração anterior", "Restaura o último backup do helper Plasma.")
            actions.addWidget(self._button("Restaurar backup", self._restore))
            actions = self._card(monitors, "Identidade do Plasma", "Branding original usado somente na sessão Plasma.")
            actions.addWidget(self._button("Estado do branding", lambda: self._helper("branding", "status")))
            actions.addWidget(self._button("Reaplicar branding", lambda: self._confirm_helper("branding", "apply", "Reaplicar tema, wallpaper e Kickoff?")))
        else:
            actions = self._card(monitors, "Sessão não compatível", "Integrações específicas exigem LXQt em X11 ou KDE Plasma.")
            actions.addWidget(self._button("Exibir sessão", self._show_report, activity=False))

        appearance = self._page()
        if self.desktop_kind == "lxqt-x11":
            for title, description, executable in (
                ("Aparência LXQt", "Widgets, temas e ícones (não altera automaticamente apps KDE).", "lxqt-config-appearance"),
                ("Atalhos globais LXQt", "Atalhos Super+E, Ctrl+Alt+T e Spectacle.", "lxqt-config-globalkeyshortcuts"),
                ("Janelas Openbox", "Configura foco, decoração e comportamento do gerenciador de janelas.", "obconf-qt"),
                ("Dispositivos de entrada", "Mouse sem aceleração e periféricos.", "lxqt-config-input"),
                ("Associações de arquivos", "Chrome, PCManFM-Qt e LXQt Archiver.", "lxqt-config-file-associations"),
            ):
                actions = self._card(appearance, title, description)
                actions.addWidget(self._button("Abrir configurações", lambda checked=False, cmd=executable: self._open_native(cmd), activity=False))
            actions = self._card(appearance, "Tema Wolf-dark", "Restaura Wolf-dark, estilo Qt Fusion e tema Breeze-Dark para GTK, com XSETTINGS no X11. Reinicie os aplicativos GTK após aplicar.")
            actions.addWidget(self._button("Verificar tema Wolf-dark e GTK", self._theme_status, activity=False))
            actions.addWidget(self._button("Reaplicar Wolf-dark (LXQt + GTK)", self._apply_dark_theme))
            actions = self._card(appearance, "Wolf Alt+Tab", "Alternador por monitor aprovado; não será sobrescrito ou reconfigurado por esta central.")
            actions.addWidget(self._button("Verificar executável", self._check_switcher, activity=False))
            actions = self._card(appearance, "Aplicativos padrão Wolf", "Verifica Chrome, PCManFM-Qt, Kate, MPC-QT, Audacious, Okular e LXQt Archiver. Reaplicação somente com confirmação e snapshot.")
            actions.addWidget(self._button("Conferir associações", self._audit_wolf_mimes, activity=False))
            actions.addWidget(self._button("Reaplicar padrões Wolf", self._apply_wolf_mimes))
        else:
            actions = self._card(appearance, "Configurações do desktop", "As ferramentas LXQt só são apresentadas na sessão LXQt/X11.")
            actions.addWidget(self._button("Mostrar diagnóstico", self._show_report, activity=False))

        game = self._page()
        actions = self._card(game, "Gamepad USB/Bluetooth", "Executa o assistente Wolf existente em um terminal interativo. Nada é configurado sem as escolhas do assistente.")
        actions.addWidget(self._button("Abrir assistente de controles", lambda: self._terminal("gamepad")))

        start = self._page()
        self.package_label = QLabel("", objectName="subtitle")
        actions = self._card(start, "Wolf Package Manager", "Monitor de atualizações na bandeja da sessão, com ações sempre autorizadas pelo usuário.")
        actions.addWidget(self._button("Ativar no login", self._enable_packages))
        actions.addWidget(self._button("Desativar no próximo login", self._disable_packages))
        actions.addWidget(self._button("Abrir gerenciador de pacotes", self._open_package_manager, activity=False))
        start.addWidget(self.package_label)
        self.zsh_label = QLabel("", objectName="subtitle")
        actions = self._card(start, "Zsh Autosuggestions", "Confere plugin, configuração fg=250 e carregamento em uma nova sessão Zsh.")
        actions.addWidget(self._button("Verificar plugin", self._check_zsh))
        start.addWidget(self.zsh_label)

        system = self._page()
        actions = self._card(system, "Gerenciador do GRUB", "Abre o assistente existente em um terminal. Mudanças de boot exigem confirmação e permissões próprias.")
        actions.addWidget(self._button("Abrir GRUB Manager", lambda: self._terminal("grub")))
        if self.desktop_kind == "lxqt-x11":
            actions = self._card(system, "Pastas pessoais em português", "Apresenta as mudanças para Documentos, Imagens, Músicas e Vídeos. A migração é opcional, mantém caminhos personalizados e não sobrescreve arquivos em conflito.")
            actions.addWidget(self._button("Pré-visualizar migração XDG", self._preview_user_dirs, activity=False))
            actions.addWidget(self._button("Migrar diretórios para português", self._migrate_user_dirs))
        if self.desktop_kind == "lxqt-x11":
            actions = self._card(system, "Integrações Wolf e mídias USB",
                "Verifique a extensão da libfm-qt, o formatador USB e as atualizações pendentes."
                " A formatação é oferecida no menu do dispositivo, não dentro das pastas.")
            actions.addWidget(self._button("Verificar integrações Wolf", self._check_integrations, activity=False))
            actions.addWidget(self._button("Abrir formatador USB", self._open_usb_formatter, activity=False))
            actions.addWidget(self._button("Abrir Wolf Package Manager", self._open_package_manager, activity=False))
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

    def _open_native(self, command: str) -> None:
        import shutil
        if self.desktop_kind != "lxqt-x11":
            self._warn("Configuração nativa LXQt disponível somente em LXQt/X11")
            return
        exe = shutil.which(command)
        if not exe:
            self._warn(f"Ferramenta não instalada: {command}")
            return
        result = QProcess.startDetached(exe, [])
        started = result[0] if isinstance(result, tuple) else result
        self._log(("[OK] Aberto: " if started else "[ERRO] Falha ao abrir: ") + command)

    def _edit_monitors(self) -> None:
        if self.desktop_kind != "lxqt-x11":
            self._warn("Editor de monitores disponível somente no LXQt/X11.")
            return
        try:
            from monitor_editor import open_editor
            open_editor(self)
            self._log("Editor Wolf de monitores encerrado; consulte a auditoria para conferir os painéis.")
        except Exception as exc:
            self._warn("Erro ao abrir editor XRandR: " + str(exc))

    def _show_lxqt_status(self) -> None:
        self._log(diagnostic_text())
        conf = Path.home() / ".config/lxqt/panel.conf"
        if conf.is_file():
            self._log("[OK] Painéis em: " + str(conf))
        self._log("Use 'Aplicar painéis aos monitores' para reconstruir o painel secundário; sem watcher automático.")

    def _wolf_lxqt_command(self, executable: str) -> str | None:
        # Não depender de PATH do SDDM/launcher; utilizar binário da instalação.
        from shutil import which
        candidate = Path('/usr/local/bin') / executable
        if candidate.is_file():
            return str(candidate)
        local = Path.home() / '.local/bin' / executable
        if local.is_file():
            return str(local)
        return which(executable)

    def _panel_status(self) -> None:
        command = self._wolf_lxqt_command('wolf-lxqt-monitors')
        if not command:
            self._warn('Utilitário de painéis Wolf ausente. Atualize a integração LXQt.')
            return
        self._run('Diagnóstico de painéis', [command, '--status'], timeout_ms=15000)

    def _panel_diagnose(self) -> None:
        command = self._wolf_lxqt_command('wolf-lxqt-monitors')
        if not command:
            self._warn('Utilitário de painéis Wolf ausente.')
            return
        self._run('Diagnóstico XRandR / Qt / LXQt Panel', [command, '--diagnose'], timeout_ms=20000)

    def _apply_panels(self) -> None:
        if self.desktop_kind != 'lxqt-x11':
            self._warn('Disponível somente em sessão LXQt/X11.')
            return
        command = self._wolf_lxqt_command('wolf-lxqt-monitors')
        if not command:
            self._warn('Utilitário de painéis Wolf ausente. Atualize a integração LXQt.')
            return
        if not self._confirm('Aplicar ou reconstruir os painéis nos monitores atualmente ativos?\n\n'
                             'O painel principal manterá a bandeja; os demais serão simplificados.\n'
                             'A configuração atual será salva em backup e o lxqt-panel poderá reiniciar.\n'
                             'Não altera resolução nem disposição física das telas.'):
            return
        self._run('Reconstrução de painéis LXQt', [command, '--apply', '--force'], timeout_ms=45000)

    def _preview_user_dirs(self) -> None:
        command = self._wolf_lxqt_command('wolf-user-dirs-ptbr')
        if not command:
            self._warn('Utilitário XDG Wolf ausente. Atualize a integração LXQt.')
            return
        self._run('Prévia das pastas XDG', [command], timeout_ms=15000)

    def _migrate_user_dirs(self) -> None:
        command = self._wolf_lxqt_command('wolf-user-dirs-ptbr')
        if not command:
            self._warn('Utilitário XDG Wolf ausente. Atualize a integração LXQt.')
            return
        if not self._confirm('Migrar as pastas padrão em inglês para os nomes em português?\n\n'
                             'Somente pastas XDG padrão serão modificadas. Arquivos existentes '
                             'não serão substituídos e caminhos personalizados serão preservados.\n'
                             'Haverá backup dos arquivos de configuração e registro dos movimentos.\n'
                             'Feche o PCManFM-Qt antes de continuar.'):
            return
        self._run('Migração XDG pt_BR', [command, '--migrate'], timeout_ms=45000)

    def _theme_status(self) -> None:
        command = self._wolf_lxqt_command('wolf-appearance-dark')
        if command:
            self._run('Tema LXQt / GTK', [command, '--check'], timeout_ms=15000)
        else:
            self._warn('Ferramenta Wolf-dark ausente.')

    def _apply_dark_theme(self) -> None:
        command = self._wolf_lxqt_command('wolf-appearance-dark')
        if not command:
            self._warn('Ferramenta Wolf-dark ausente.')
            return
        if self._confirm('Reaplicar Wolf-dark (Qt Fusion) e Breeze-Dark em GTK?\n'
                         'Serão feitos backups e aplicativos abertos precisarão ser reiniciados.'):
            self._run('Reaplicar Wolf-dark + GTK', [command, '--apply'], timeout_ms=30000)

    def _snapshot_lxqt(self) -> None:
        if self.desktop_kind != "lxqt-x11":
            self._warn("Snapshot disponível somente em LXQt/X11.")
            return
        if not self._confirm("Salvar agora um backup das configurações LXQt/Openbox? Não altera a sessão."):
            return
        try:
            self._log("[OK] Snapshot salvo em: " + str(create_snapshot()))
        except (OSError, RuntimeError, ValueError) as exc:
            self._warn(str(exc))
        self.refresh()

    def _audit_lxqt_panels(self) -> None:
        from wolf_profile import xrandr_count
        count = xrandr_count()
        self._log(f"=== Painéis Wolf (monitores XRandR: {count if count is not None else 'indisponível'}) ===")
        for result in panel_checks(monitor_count=count):
            self._log(result.render())
        self._log("Auditoria somente leitura; nenhum painel reiniciado.")

    def _audit_wolf_profile(self) -> None:
        self._log("\n" + profile_report())

    def _export_wolf_report(self) -> None:
        try:
            path = export_report()
            self._log("[OK] Auditoria exportada: " + str(path))
        except (OSError, RuntimeError, ValueError) as exc:
            self._warn("Não foi possível exportar auditoria: " + str(exc))

    def _audit_wolf_mimes(self) -> None:
        self._log("=== Aplicativos padrão Wolf (somente leitura) ===")
        for check in mime_checks():
            self._log(check.render())

    def _apply_wolf_mimes(self) -> None:
        if self.desktop_kind != "lxqt-x11":
            self._warn("Reaplicação de padrões disponível somente no LXQt/X11.")
            return
        if not self._confirm("Reaplicar aplicativos padrão Wolf neste usuário?\n"
                             "Chrome, PCManFM-Qt, Kate, MPC-QT, Audacious, Okular e LXQt Archiver.\n\n"
                             "As associações MIME do usuário podem valer em outros desktops.\n"
                             "Será salvo um snapshot antes de qualquer mudança."):
            return
        try:
            backup = create_snapshot()
            self._log("[OK] Snapshot prévio: " + str(backup))
            for result in apply_mime_defaults():
                self._log(result)
            self._audit_wolf_mimes()
        except (OSError, RuntimeError, ValueError) as exc:
            self._warn("Reaplicação interrompida: " + str(exc))

    def _list_lxqt_backups(self) -> None:
        backups = list_backups()
        self._log("Snapshots LXQt: " + str(len(backups)))
        for path in backups[-12:]:
            self._log(" • " + str(path))

    def _restore_instructions(self) -> None:
        self._log("Saia do LXQt, entre no Plasma ou TTY, e use:")
        self._log("python3 ~/.local/share/wolf-linux/control-center/lxqt_support.py list")
        self._log("python3 ~/.local/share/wolf-linux/control-center/lxqt_support.py restore --snapshot CAMINHO_ABSOLUTO")
        self._log("Não faça restauração com lxqt-panel em execução.")

    def _check_switcher(self) -> None:
        p = Path.home() / ".local/bin/wolf-alt-tab-monitor"
        self._log("Wolf Alt+Tab: " + (f"encontrado em {p}" if p.is_file() else "não encontrado"))
        self._log("Esta central não substitui os atalhos aprovados da Preview 11.")

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

    def _check_integrations(self) -> None:
        path = Path('/usr/local/bin/wolf-integrations-check')
        if not path.is_file():
            self._warn("Verificador de integrações Wolf não instalado.")
            return
        self._run("Integrações Wolf (somente leitura)", ['/usr/bin/python3', str(path)], 15000)

    def _open_usb_formatter(self) -> None:
        path = Path('/usr/local/bin/wolf-format-removable')
        if not path.is_file():
            self._warn("Formatador Wolf não instalado.")
            return
        result = QProcess.startDetached(str(path), ['--browse'])
        started = result[0] if isinstance(result, tuple) else result
        self._log('[OK] Formatador USB aberto.' if started else '[ERRO] Falha ao abrir formatador USB.')

    def _open_package_manager(self) -> None:
        command = "/usr/local/bin/wolf-package-manager"
        if not Path(command).is_file():
            self._warn("Wolf Package Manager não instalado.")
            return
        launched = QProcess.startDetached(command, [])
        started = launched[0] if isinstance(launched, tuple) else launched
        if not started:
            self._warn("Não foi possível iniciar o Wolf Package Manager.")

    def _enable_packages(self) -> None:
        if not notifier_installed():
            self._warn("Wolf Package Manager não instalado.")
            return
        if not self._confirm("Ativar o Wolf Package Manager na inicialização deste usuário? Uma cópia anterior será preservada."):
            return
        try:
            target = enable_notifier()
            self._log(f"[OK] Autostart criado: {target}\nValerá a partir do próximo login.")
        except OSError as exc:
            self._warn(str(exc))
        self.refresh()

    def _disable_packages(self) -> None:
        if not notifier_installed():
            self._warn("Wolf Package Manager não instalado.")
            return
        if not self._confirm("Desativar Wolf Package Manager no próximo login? O processo atual não será interrompido."):
            return
        try:
            target = disable_notifier()
            self._log(f"[OK] Wolf Package Manager desativado no login: {target}")
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
        self.package_label.setText(notifier_status())
        self.zsh_label.setText(autosuggestions_status())
        self.info_label.setText("Pronto" if self.proc is None else "Operação em andamento...")

    def closeEvent(self, event) -> None:
        if self.proc is not None:
            self.proc.kill()
            self.proc.waitForFinished(2000)
        super().closeEvent(event)


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--monitors":
        from wolf_monitors import main as open_monitors
        sys.exit(open_monitors())
    app = QApplication(sys.argv)
    app.setApplicationName("Wolf Control Center")
    app.setDesktopFileName("wolf-control-center")
    win = Center()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
