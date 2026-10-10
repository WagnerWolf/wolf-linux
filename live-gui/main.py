#!/usr/bin/env python3
"""Wolf Installer GUI 2.0 — BIOS/MBR na VM e console PTY integrado.

Execução real somente em VM descartável, via backend Bash, após confirmação
dupla do disco. Reutilização, manual e apagar são restritos a VM; nunca executar em hardware físico.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from terminal_engine import InstallerPty
import wolf_plan
import wolf_discovery

VERSION = "2.1"
STACKS = ("daily", "gaming", "development", "android", "containers", "extras")
PRESETS = {
    "Minimal": (),
    "Test": ("daily", "gaming", "development", "extras"),
    "Full": STACKS,
}

# Layouts XKB válidos e conhecidos; nunca usar texto livre como parâmetro.
# Cada entrada possui (nome, layout, modelo, variante). O ThinkPad brasileiro
# é a variante br(thinkpad), não o modelo físico "thinkpad" do XKB.
KEYBOARD_LAYOUTS = (
    ("Português (Brasil) — ABNT2", "br", "abnt2", ""),
    ("Português (Brasil) — ThinkPad (IBM/Lenovo)", "br", "abnt2", "thinkpad"),
    ("English (US)", "us", "pc105", ""),
    ("Português (Portugal)", "pt", "pc105", ""),
    ("Español", "es", "pc105", ""),
    ("Français", "fr", "pc105", ""),
    ("Deutsch", "de", "pc105", ""),
    ("Italiano", "it", "pc105", ""),
)


def keyboard_command(layout: str, model: str, variant: str = "") -> list[str]:
    if not any((layout, model, variant) == (item[1], item[2], item[3])
               for item in KEYBOARD_LAYOUTS):
        raise ValueError("Layout de teclado fora da lista permitida")
    argv = ["setxkbmap", "-model", model, "-layout", layout]
    if variant:
        argv.extend(["-variant", variant])
    argv.extend(["-option", ""])
    return argv


def apply_keyboard_layout(layout: str, model: str, variant: str = "") -> tuple[bool, str]:
    argv = keyboard_command(layout, model, variant)
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)
    if result.returncode != 0:
        return False, (result.stderr.strip() or result.stdout.strip() or "Falha ao aplicar teclado")
    return True, f"Layout {layout} aplicado nesta sessão Live."



def safe_run(argv: list[str], timeout: int = 5) -> str:
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def disk_inventory(raw: str | None = None) -> list[dict[str, object]]:
    # Fonte única para inventário GUI e revisão independente do backend.
    return wolf_plan.inventory(raw)


def format_size(size: int) -> str:
    return f"{size / (1024 ** 3):.1f} GiB" if size >= 1024 ** 3 else f"{size / (1024 ** 2):.1f} MiB"


def build_summary(disk: str, storage_mode: str, selected_stacks: tuple[str, ...],
                  hostname: str, username: str, paths: set[str]) -> str:
    if disk and disk not in paths:
        raise ValueError("Disco selecionado não pertence ao inventário atual")
    if storage_mode not in ("erase", "reuse", "manual"):
        raise ValueError("Modo de armazenamento inválido")
    if any(s not in STACKS for s in selected_stacks):
        raise ValueError("Stack inválida")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]*", username):
        raise ValueError("Usuário inválido")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,62}", hostname):
        raise ValueError("Hostname inválido")
    storage = {
        "erase": "APAGAR disco inteiro (inclui partições existentes)",
        "reuse": "Reutilizar partições existentes (preservar EFI e /home)",
        "manual": "Avançado/manual (partições escolhidas)",
    }[storage_mode]
    return "\n".join([
        "WOLF LINUX — REVISÃO DAS ESCOLHAS DA GUI",
        "", f"Disco selecionado: {disk or 'não selecionado'}",
        f"Armazenamento: {storage}",
        f"Hostname: {hostname}", f"Usuário: {username}",
        f"Stacks: {', '.join(selected_stacks) if selected_stacks else 'nenhuma (minimal)'}",
        "", "ATENÇÃO:",
        "- Nenhuma partição foi modificada.",
        "- A execução VM usa as escolhas validadas independentemente pelo Bash.",
        "- Não use este resumo como autorização para apagar discos.",
    ])


def format_intent_warning(role: str, home_layout: str, partition: str | None) -> str:
    """Texto de confirmação, específico à partição e ao risco real de apagamento."""
    selected = partition or "(nenhuma partição selecionada)"
    if role == "root":
        home_risk = ("Como /home ficará dentro de /, os arquivos pessoais antigos "
                     "nessa mesma partição também serão perdidos."
                     if home_layout == "in-root" else
                     "Os dados da partição /home separada NÃO são cobertos por esta formatação, "
                     "mas os dados de / serão apagados.")
        return (f"Você está solicitando FORMATAR a raiz /: {selected}.\n\n"
                "Formatar essa partição remove TODOS os arquivos atualmente armazenados nela.\n"
                f"{home_risk}\n\n"
                "Nos modos MANUAL e REUTILIZAR VM, a raiz / SERÁ FORMATADA em ext4, "
                "mediante validação e confirmação.\n\n"
                "Deseja manter essa seleção de formatação?")
    if role == "esp":
        return (f"Você está solicitando FORMATAR a EFI {selected} em FAT32.\n\n"
                "TODOS os arquivos e carregadores de boot atuais nesta partição serão apagados, "
                "inclusive de outros sistemas como Windows.\n"
                "Para manter os arquivos de boot existentes, use REUTILIZAR e deixe EFI sem formatação.\n\n"
                "CONFIRMAR a formatação desta EFI no manual VM?")
    if role == "home":
        return (f"Você está solicitando FORMATAR /home {selected} em ext4.\n\n"
                "TODOS os arquivos pessoais desta partição serão apagados.\n"
                "Para manter os arquivos existentes, use REUTILIZAR.\n\n"
                "CONFIRMAR a formatação desta /home no manual VM?")
    raise ValueError("Papel de partição inválido")


def detect_hardware() -> dict[str, str]:
    try:
        build = Path("/etc/wolf-linux-live-build").read_text(encoding="utf-8").strip()
    except OSError:
        build = "Wolf Linux Live (ambiente de desenvolvimento)"
    gpu = "Não identificada"
    for line in safe_run(["lspci", "-nn"]).splitlines():
        if any(word in line.lower() for word in ("vga", "3d controller", "display controller")):
            gpu = line.split(": ", 1)[-1][:100]
            break
    return {
        "Versão": build,
        "Firmware": "UEFI" if Path("/sys/firmware/efi").exists() else "BIOS/Legacy",
        "GPU": gpu,
        "Sessão": "Wolf Linux Live (Openbox)",
    }


def launch(argv: list[str]) -> tuple[bool, str]:
    if not argv or not shutil.which(argv[0]):
        return False, f"Aplicativo ausente: {argv[0] if argv else '?'}"
    try:
        subprocess.Popen(argv, start_new_session=True)
    except OSError as exc:
        return False, str(exc)
    return True, "Aplicativo iniciado."


def qt_main() -> int:
    from PySide6.QtCore import Qt, QTimer, QSocketNotifier
    from PySide6.QtGui import QTextOption, QTextCursor
    from PySide6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QFormLayout,
        QLabel, QPushButton, QFrame, QMessageBox, QTabWidget, QComboBox, QLineEdit,
        QPlainTextEdit, QCheckBox, QScrollArea, QDialog, QDialogButtonBox, QSpinBox, QSlider, QSizePolicy, QInputDialog,
    )

    app = QApplication(sys.argv[:1])
    app.setApplicationName("Wolf Installer")
    app.setStyle("Fusion")
    app.setStyleSheet("""
        QWidget { background: #11151d; color: #e5eaf2; font: 11pt 'Sans Serif'; }
        QTabWidget::pane { border: 1px solid #344356; }
        QTabBar::tab { background: #253044; padding: 10px 22px; border: 1px solid #344356; }
        QTabBar::tab:selected { background: #3b526e; }
        QFrame#card { background: #1a202b; border: 1px solid #303b4c; border-radius: 10px; }
        QPushButton { background: #253044; border: 1px solid #40516b;
                      padding: 10px; border-radius: 8px; }
        QPushButton:hover { background: #334963; }
        QLineEdit, QComboBox, QPlainTextEdit { background: #18212c; border: 1px solid #40516b; padding: 5px; }
    """)

    class KeyboardDialog(QDialog):
        """Solicita o layout antes da janela principal do instalador."""

        def __init__(self):
            super().__init__()
            self.setWindowTitle("Wolf Linux — Configuração do teclado")
            self.resize(500, 310)
            container = QVBoxLayout(self)
            heading = QLabel("SELECIONE O LAYOUT DO TECLADO")
            heading.setStyleSheet("font-size: 15pt; font-weight: bold")
            container.addWidget(heading)
            note = QLabel("Escolha o teclado usado nesta Live. O layout padrão é Português (Brasil) — ABNT2.")
            note.setWordWrap(True)
            container.addWidget(note)
            self.layouts = QComboBox()
            for name, layout, model, variant in KEYBOARD_LAYOUTS:
                self.layouts.addItem(name, (layout, model, variant))
            container.addWidget(self.layouts)
            self.status = QLabel("")
            self.status.setWordWrap(True)
            container.addWidget(self.status)
            self.test_input = QLineEdit()
            self.test_input.setPlaceholderText("Teste: ç ã á é / ? @ \\ ...")
            container.addWidget(self.test_input)
            buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok)
            buttons.button(QDialogButtonBox.StandardButton.Ok).setText("Continuar para o instalador")
            buttons.accepted.connect(self.accept)
            container.addWidget(buttons)
            self.layouts.currentIndexChanged.connect(self.apply_selected)
            self.apply_selected()

        def apply_selected(self):
            layout, model, variant = self.layouts.currentData()
            ok, message = apply_keyboard_layout(layout, model, variant)
            self.status.setText(message)
            self.status.setStyleSheet("color:#a8dfb7" if ok else "color:#ffb3b3")
            self.test_input.clear()
            self.test_input.setFocus()

    class VmEraseConsentDialog(QDialog):
        """Confirmação inegociável e visível antes de abrir o terminal.

        O botão de continuar nasce DESABILITADO e só habilita quando o usuário
        informa exatamente o disco selecionado. O backend repetirá a confirmação.
        """

        def __init__(self, parent, disk: str):
            super().__init__(parent)
            self.setWindowTitle("WOLF LINUX — CONFIRMAÇÃO DE APAGAMENTO")
            self.setModal(True)
            self.resize(630, 350)
            layout = QVBoxLayout(self)
            heading = QLabel("ATENÇÃO: PERDA TOTAL DE DADOS")
            heading.setWordWrap(True)
            heading.setStyleSheet("color:#ff9999;font-size:16pt;font-weight:bold")
            layout.addWidget(heading)
            description = QLabel(
                f"O alvo é {disk}. CONFIRA o modo escolhido e as partições listadas "
                "na revisão. No modo APAGAR DISCO, todas as partições serão excluídas; "
                "no MANUAL, somente as partições explicitamente marcadas serão formatadas.\n\n"
                "Use SOMENTE uma VM DESCARTÁVEL. O Bash fará outra validação e confirmação. "
                "A saída aparecerá na ABA Instalação, dentro desta janela."
            )
            description.setWordWrap(True)
            layout.addWidget(description)
            expected = "APAGAR"
            instruction = QLabel(f"Para liberar a abertura do terminal, digite exatamente:\n{expected}")
            instruction.setWordWrap(True)
            instruction.setStyleSheet("font-weight:bold;color:#ffcf91")
            layout.addWidget(instruction)
            self.confirm_text = QLineEdit()
            self.confirm_text.setPlaceholderText(expected)
            layout.addWidget(self.confirm_text)
            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
            )
            self.accept_button = buttons.button(QDialogButtonBox.StandardButton.Ok)
            self.accept_button.setText("Ir para a aba Instalação")
            self.accept_button.setEnabled(False)
            buttons.button(QDialogButtonBox.StandardButton.Cancel).setText("Cancelar")
            self.confirm_text.textChanged.connect(
                lambda value: self.accept_button.setEnabled(value == expected)
            )
            buttons.accepted.connect(self.accept)
            buttons.rejected.connect(self.reject)
            layout.addWidget(buttons)
            self.confirm_text.setFocus()

    class InstallFinishedDialog(QDialog):
        """Oferece reinicialização somente após sucesso informado pelo Bash.

        Não reinicia automaticamente; o usuário precisa escolher expressamente.
        """

        def __init__(self):
            super().__init__()
            self.setWindowTitle("Wolf Linux — Instalação concluída")
            self.setModal(True)
            self.resize(600, 300)
            layout = QVBoxLayout(self)
            heading = QLabel("Wolf Linux instalado com sucesso!")
            heading.setStyleSheet("color:#a8dfb7;font-size:18pt;font-weight:bold")
            heading.setWordWrap(True)
            layout.addWidget(heading)
            message = QLabel(
                "O instalador Bash terminou sem erros. Agora você pode reiniciar "
                "para iniciar o Wolf Linux instalado.\n\n"
                "Antes de reiniciar, remova a ISO/mídia de instalação ou ajuste "
                "a ordem de boot da VM para iniciar pelo disco instalado."
            )
            message.setWordWrap(True)
            layout.addWidget(message)
            buttons = QHBoxLayout()
            stay = QPushButton("Continuar na Live")
            stay.clicked.connect(self.reject)
            reboot = QPushButton("Reiniciar agora")
            reboot.setStyleSheet("background:#28563a;color:white;border:1px solid #72bd89")
            reboot.clicked.connect(self.reboot_now)
            buttons.addWidget(stay)
            buttons.addWidget(reboot)
            layout.addLayout(buttons)

        def reboot_now(self):
            # Proteção extra: essa operação só pertence à mídia Wolf Live.
            if not Path("/etc/wolf-linux-live-build").is_file():
                QMessageBox.warning(self, "Wolf Linux", "Reinicialização disponível somente na Wolf Live.")
                return
            try:
                done = subprocess.run(
                    ["sudo", "-n", "systemctl", "reboot"],
                    capture_output=True, text=True, timeout=12, check=False,
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                QMessageBox.warning(self, "Reinicialização falhou", str(exc))
                return
            if done.returncode:
                QMessageBox.warning(
                    self, "Reinicialização falhou",
                    done.stderr.strip() or done.stdout.strip() or "systemctl reboot retornou erro.",
                )
                return
            self.accept()

    class Window(QMainWindow):
        def __init__(self, selected_keyboard):
            super().__init__()
            self.keyboard = selected_keyboard
            self.setWindowTitle("Wolf Linux — Installer GUI 2.2 — físico controlado")
            # Não ultrapassar o espaço disponível da Live (incluindo janelas 1024x768).
            screen = app.primaryScreen()
            available = screen.availableGeometry() if screen else None
            self.resize(max(690, min(1020, available.width()-70)) if available else 980,
                        max(500, min(730, available.height()-75)) if available else 680)
            self.setMinimumSize(680, 490)
            self.disks = disk_inventory()
            self._installer_pty = None
            self._pty_notifier = None
            self._installer_log = None
            self._installer_finished = False
            self._vm_result_poll = QTimer(self)
            self._vm_result_poll.setInterval(400)
            self._vm_result_poll.timeout.connect(self.check_vm_install_result)
            wrapper = QWidget()
            layout = QVBoxLayout(wrapper)
            layout.setContentsMargins(20, 18, 20, 18)
            headline = QLabel("WOLF LINUX 2.0   /   INSTALADOR GRÁFICO")
            headline.setStyleSheet("font-size:19pt;font-weight:700;color:#ffffff")
            layout.addWidget(headline)
            warning = QLabel("EXECUÇÃO VM HOMOLOGADA; EXECUÇÃO FÍSICA SOMENTE POR CONTRATO MULTIDISCO PROTEGIDO: "
                             "Apagar disco inteiro, Manual UEFI/GPT ou BIOS/MBR, e Reutilizar /home dedicada. "
                             "No Reutilizar, apenas a raiz / será formatada; EFI e /home permanecem. "
                             "Limpeza de configurações ocultas exige autorização separada. "
                             "Ações destrutivas exigem confirmação; o modo físico só aceita raiz+EFI em NVMe distintos e /home LVM multi-PV.")
            warning.setWordWrap(True)
            warning.setStyleSheet("color:#ffcf91;border:1px solid #766039;padding:10px")
            layout.addWidget(warning)
            tabs = QTabWidget()
            tabs.tabBar().setUsesScrollButtons(True)
            tabs.tabBar().setExpanding(False)
            tabs.setElideMode(Qt.TextElideMode.ElideRight)
            layout.addWidget(tabs, 1)

            home = QWidget()
            hv = QVBoxLayout(home)
            for key, val in detect_hardware().items():
                label = QLabel(f"{key}: {val}")
                label.setWordWrap(True)
                hv.addWidget(label)
            live_desc = QLabel("Live: Chromium, Bluetooth, Wolf Rescue, PCManFM-Qt, QTerminal e GParted. "
                               "Os volumes podem permitir escrita; confira sempre o dispositivo.")
            live_desc.setWordWrap(True)
            hv.addWidget(live_desc)
            wifi_help = QLabel("Wi-Fi: clique no ícone de rede no canto superior direito para escolher a rede e informar a senha. O botão de redes também abre as configurações avançadas.")
            wifi_help.setWordWrap(True)
            hv.addWidget(wifi_help)
            for title, argv in (
                ("Abrir terminal", ["qterminal"]),
                ("Arquivos e dispositivos", ["pcmanfm-qt"]),
                ("Chromium", ["wolf-live-browser"]),
                ("Bluetooth", ["blueman-manager"]),
                ("Wolf Rescue — Mapear EFI e LVM", ["wolf-live-rescue"]),
                ("Relógio e sincronização NTP", ["qterminal", "-e", "wolf-live-time-status"]),
                ("GParted — Particionador", ["wolf-live-gparted"]),
                ("Configurar Wi-Fi / redes", ["wolf-live-network"]),
                ("Diagnóstico", ["qterminal", "-e", "wolf-live-diagnostics"]),
                ("Topologia de discos e LVM",
                 ["qterminal", "-e", "sudo", "wolf-live-storage-topology"]),
                ("Pré-diagnóstico para hardware físico (somente leitura)",
                 ["qterminal", "-e", "wolf-physical-preflight"]),
            ):
                btn = QPushButton(title)
                btn.clicked.connect(lambda checked=False, args=argv: self.run_command(args))
                hv.addWidget(btn)
            cleanup_btn = QPushButton("Recuperar tentativa anterior — desmontar /mnt")
            cleanup_btn.clicked.connect(self.open_cleanup_assistant)
            hv.addWidget(cleanup_btn)
            kb_btn = QPushButton("Alterar layout do teclado")
            kb_btn.clicked.connect(self.change_keyboard)
            hv.addWidget(kb_btn)
            hv.addStretch()
            tabs.addTab(self.scrollable(home), "Bem-vindo")

            storage = QWidget()
            sv = QVBoxLayout(storage)
            sv.addWidget(QLabel("Inventário de dispositivos (leitura apenas) — confirme também pelo lsblk no terminal."))
            self.disk_combo = QComboBox()
            # Não permitir que modelo/dispositivo comprido force largura horizontal.
            self.disk_combo.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToMinimumContentsLengthWithIcon)
            self.disk_combo.setMinimumContentsLength(14)
            self.disk_combo.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Fixed)
            self.disk_combo.addItem("Selecione um disco", "")
            for disk in self.disks:
                self.disk_combo.addItem(
                    f"{disk['path']} — {format_size(disk['size'])} — {disk['model']}" +
                    (" [REMOVÍVEL]" if disk['removable'] else ""), disk["path"])
            self.disk_combo.currentIndexChanged.connect(self.refresh_disk)
            self.disk_combo.currentIndexChanged.connect(self.update_erase_bounds)
            self.disk_combo.currentIndexChanged.connect(self.refresh_summary)
            sv.addWidget(self.disk_combo)
            self.disk_detail = QPlainTextEdit()
            self.disk_detail.setReadOnly(True)
            self.disk_detail.setLineWrapMode(QPlainTextEdit.LineWrapMode.WidgetWidth)
            self.disk_detail.setMinimumHeight(165)
            sv.addWidget(self.disk_detail)
            self.storage_mode = QComboBox()
            self.storage_mode.addItem("Apagar TODO o disco (remove partições e dados)", "erase")
            self.storage_mode.addItem("Reutilizar partições existentes", "reuse")
            self.storage_mode.addItem("Avançado/manual (criar no GParted e atribuir montagens)", "manual")
            sv.addWidget(QLabel("Escolha como instalar o sistema:"))
            sv.addWidget(self.storage_mode)
            self.storage_mode.currentIndexChanged.connect(self.refresh_summary)
            self.storage_mode.currentIndexChanged.connect(self.update_storage_controls)
            # Fluxo multidisco exclusivo de revisão/simulação. NÃO é aceito no
            # executor VM nem habilita instalação física.
            self.md_snapshot = None
            md_header = QLabel("REUTILIZAR — DETECÇÃO MULTIDISCO/LVM (SOMENTE PLANEJAMENTO)")
            md_header.setStyleSheet("color:#b6dcff;font-weight:700;padding:8px;border:1px solid #40516b")
            sv.addWidget(md_header)
            md_hint = QLabel(
                "Busca instalações existentes lendo o fstab de partições raiz ext4 com montagem "
                "temporária SOMENTE LEITURA (ro,noload). Permite escolher EFI e /home em OUTROS SSDs "
                "ou em volume LVM. Não formata nem instala. No modo Reutilizar, "
                "após a detecção, a revisão usa o mapa multidisco, não a seleção de disco único acima.")
            md_hint.setWordWrap(True)
            sv.addWidget(md_hint)
            self.md_scan_btn = QPushButton("Detectar instalações em TODOS os discos (inclui LVM)")
            self.md_scan_btn.clicked.connect(self.scan_installations)
            sv.addWidget(self.md_scan_btn)
            self.md_status = QLabel("Detecção não executada. Selecione Reutilizar e clique em Detectar.")
            self.md_status.setWordWrap(True)
            sv.addWidget(self.md_status)
            self.md_diagnostics = QPlainTextEdit()
            self.md_diagnostics.setReadOnly(True)
            self.md_diagnostics.setLineWrapMode(QPlainTextEdit.LineWrapMode.WidgetWidth)
            self.md_diagnostics.setPlaceholderText("Diagnósticos da detecção (somente leitura).")
            self.md_diagnostics.setMaximumHeight(120)
            self.md_diagnostics.setMinimumHeight(72)
            sv.addWidget(self.md_diagnostics)
            self.md_candidate = QComboBox()
            self.md_candidate.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Fixed)
            self.md_candidate.currentIndexChanged.connect(self.choose_detected_installation)
            sv.addWidget(QLabel("Instalação encontrada — origem do fstab e da partição raiz /:"))
            sv.addWidget(self.md_candidate)
            self.md_roles = {}
            for role, label in (("esp", "EFI /boot/efi (pode estar em outro disco)"),
                                ("home", "/home separada (pode ser volume lógico LVM)")):
                sv.addWidget(QLabel(label))
                combo = QComboBox()
                combo.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Fixed)
                combo.currentIndexChanged.connect(self.md_choices_changed)
                self.md_roles[role] = combo
                sv.addWidget(combo)
            self.md_confirm = QCheckBox("CONFIRMO as partições identificadas para o pré-plano (não instala)")
            self.md_confirm.stateChanged.connect(self.refresh_summary)
            sv.addWidget(self.md_confirm)
            self.md_override = QCheckBox("CONFIRMO divergências em relação ao fstab original")
            self.md_override.stateChanged.connect(self.refresh_summary)
            sv.addWidget(self.md_override)
            self.md_warning = QLabel("Nenhuma operação no SSD físico será autorizada nesta revisão.")
            self.md_warning.setWordWrap(True)
            self.md_warning.setStyleSheet("color:#ffcf91;border:1px solid #766039;padding:8px")
            sv.addWidget(self.md_warning)
            refresh_btn = QPushButton("Atualizar lista de discos")
            refresh_btn.clicked.connect(self.reload_disks)
            sv.addWidget(refresh_btn)
            part_tool = QPushButton("Abrir GParted — Particionador (ferramenta independente)")
            part_tool.clicked.connect(lambda: self.run_command(["wolf-live-gparted"]))
            sv.addWidget(part_tool)
            advanced_info = QLabel(
                "APAGAR DISCO: remove tudo; UEFI cria EFI FAT32 de 1 GiB e BIOS cria MBR sem EFI. Você escolhe /home integrada ou separada e os tamanhos das partições. "
                "MANUAL VM: UEFI requer GPT + EFI; BIOS requer MBR/DOS e NÃO usa EFI. Selecione / e /home opcional. "
                "Marque individualmente quais formatar; a EFI selecionada terá seu tipo GPT ESP configurado automaticamente. "
                "REUTILIZAR VM: formatar somente a raiz /; preservar /home separada e, em UEFI, a EFI. "
                "GParted pode alterar o disco quando suas operações são confirmadas. "
                "ATENÇÃO: EFI em outro SSD e /home em LVM ainda NÃO são suportados pela GUI: use diagnóstico de topologia, sem instalar.")
            advanced_info.setWordWrap(True)
            sv.addWidget(advanced_info)
            guide = QLabel(
                "PARTIÇÕES NECESSÁRIAS (UEFI): partição EFI de 512 MiB a 1 GiB (FAT32 após formatar); a flag GPT esp é aplicada automaticamente pelo instalador; "
                "raiz / ext4, mínimo 20 GiB (recomendado 40 GiB ou mais), contendo o sistema. "
                "Opcional: /home separada ext4 para arquivos pessoais; o restante do espaço pode ser dedicado a ela. "
                "BIOS/Legacy: partição raiz ext4 + /home opcional; requer tabela MBR/DOS neste piloto. "
                "BIOS+GPT exige bios_grub e permanece bloqueado para manual/reutilizar."
            )
            guide.setWordWrap(True)
            guide.setStyleSheet("color:#c8d9ea;border:1px solid #344356;padding:10px")
            sv.addWidget(guide)
            sv.addWidget(QLabel("Selecione a partição RAIZ / (obrigatória), a EFI e, se desejar, /home dedicada:"))
            self.home_layout = QComboBox()
            self.home_layout.addItem("/home dentro da partição raiz / (sem partição dedicada)", "in-root")
            self.home_layout.addItem("/home em partição dedicada", "separate")
            self.home_layout.currentIndexChanged.connect(self.update_storage_controls)
            self.home_layout.currentIndexChanged.connect(self.refresh_summary)
            sv.addWidget(self.home_layout)
            # Barras e campos compartilham o limite real da unidade escolhida.
            # 0 = 'restante do disco'. O backend recalcula o mesmo limite.
            self.erase_root_gib = QSpinBox()
            self.erase_root_gib.setRange(0, 0)
            self.erase_root_gib.setSuffix(" GiB")
            self.erase_root_gib.setSpecialValueText("Restante do disco")
            self.erase_root_slider = QSlider(Qt.Orientation.Horizontal)
            self.erase_root_slider.setRange(0, 0)
            self.erase_root_gib.valueChanged.connect(
                lambda value: self.on_erase_size_changed("root", value))
            self.erase_root_slider.valueChanged.connect(
                lambda value: self.on_erase_size_changed("root", value))

            self.erase_home_gib = QSpinBox()
            self.erase_home_gib.setRange(0, 0)
            self.erase_home_gib.setSuffix(" GiB")
            self.erase_home_gib.setSpecialValueText("Restante do disco")
            self.erase_home_slider = QSlider(Qt.Orientation.Horizontal)
            self.erase_home_slider.setRange(0, 0)
            self.erase_home_gib.valueChanged.connect(
                lambda value: self.on_erase_size_changed("home", value))
            self.erase_home_slider.valueChanged.connect(
                lambda value: self.on_erase_size_changed("home", value))
            self._syncing_erase_size = False
            self.erase_size_title = QLabel("APAGAR DISCO: tamanho das partições (0 = restante)")
            self.erase_size_title.setStyleSheet("font-weight:bold;color:#c8d9ea;margin-top:8px")
            sv.addWidget(self.erase_size_title)
            self.erase_capacity_label = QLabel("Selecione um disco para calcular o espaço disponível")
            self.erase_capacity_label.setWordWrap(True)
            self.erase_capacity_label.setStyleSheet("color:#a6d8eb;font-weight:600")
            sv.addWidget(self.erase_capacity_label)
            sv.addWidget(QLabel("Tamanho da RAIZ / (ext4): barra ou campo numérico (0 = restante; fixo mínimo 20 GiB)"))
            root_controls = QHBoxLayout()
            root_controls.addWidget(self.erase_root_slider, 1)
            root_controls.addWidget(self.erase_root_gib)
            sv.addLayout(root_controls)
            self.erase_home_label = QLabel("Tamanho da /home separada (ext4): barra ou campo numérico")
            sv.addWidget(self.erase_home_label)
            home_controls = QHBoxLayout()
            home_controls.addWidget(self.erase_home_slider, 1)
            home_controls.addWidget(self.erase_home_gib)
            sv.addLayout(home_controls)
            self.erase_home_hint = QLabel("0 = todo o espaço restante; tamanho fixo mínimo de /home: 10 GiB")
            self.erase_home_hint.setWordWrap(True)
            sv.addWidget(self.erase_home_hint)
            self.bios_esp_notice = QLabel("MODO BIOS/LEGACY: partição EFI NÃO NECESSÁRIA. O GRUB será instalado no disco MBR.")
            self.bios_esp_notice.setWordWrap(True)
            self.bios_esp_notice.setStyleSheet("color:#ff7777;background:#351c20;border:1px solid #b95765;padding:10px;font-weight:bold")
            sv.addWidget(self.bios_esp_notice)
            self.partition_roles = {}
            self.partition_format = {}
            for role, label in (("root", "RAIZ / — sistema operacional"),
                                ("esp", "EFI /boot/efi — inicialização UEFI"),
                                ("home", "HOME /home — arquivos pessoais (OPCIONAL)")):
                combo = QComboBox()
                combo.addItem(f"{label}: não selecionada", None)
                combo.currentIndexChanged.connect(lambda _index, key=role: self.on_partition_changed(key))
                self.partition_roles[role] = combo
                heading = QLabel(label)
                heading.setStyleSheet("font-weight:bold;color:#e4edf8;margin-top:8px")
                sv.addWidget(heading)
                sv.addWidget(combo)
                flag = QCheckBox(f"Formatar {label} (somente se o modo permitir)")
                flag.setChecked(False)  # Nunca presumir consentimento com perda de dados.
                flag.stateChanged.connect(self.refresh_summary)
                flag.clicked.connect(lambda checked, key=role: self.confirm_format_intent(key, checked))
                self.partition_format[role] = flag
                sv.addWidget(flag)
            self.format_notice = QLabel()
            self.format_notice.setWordWrap(True)
            self.format_notice.setStyleSheet(
                "color:#ffd7d7;background:#45232b;border:2px solid #be6570;padding:12px")
            self.format_notice.hide()
            sv.addWidget(self.format_notice)
            compatibility_note = QLabel(
                "MANUAL VM: a raiz / será formatada em ext4. Marque FORMATO EFI se quiser uma EFI FAT32 nova; "
                "desmarque para preservar EFI FAT32 existente. /home dedicada também pode ser formatada ext4 "
                "ou preservada. Se contiver dados a manter, prefira REUTILIZAR.")
            compatibility_note.setWordWrap(True)
            compatibility_note.setStyleSheet("color:#ffcf91;border:1px solid #766039;padding:9px")
            sv.addWidget(compatibility_note)
            self.cleanup_home_check = QCheckBox(
                "REUTILIZAR /home: remover arquivos e pastas ocultos de TODOS os usuários existentes")
            self.cleanup_home_check.setChecked(False)
            self.cleanup_home_check.clicked.connect(self.confirm_home_cleanup)
            self.cleanup_home_check.stateChanged.connect(self.refresh_summary)
            sv.addWidget(self.cleanup_home_check)
            cleanup_note = QLabel(
                "Opcional: apaga entradas ocultas imediatamente dentro de cada pasta de usuário "
                "na partição /home PRESERVADA (ex.: .config, .local, .ssh, .gnupg, .mozilla). "
                "Pode eliminar perfis, senhas e chaves; ARQUIVOS VISÍVEIS permanecem. "
                "Antes de formatar a raiz, o terminal listará os itens e exigirá LIMPAR. "
                "Sem marcar, nada será removido da /home.")
            cleanup_note.setWordWrap(True)
            cleanup_note.setStyleSheet("color:#ffcf91;border:1px solid #766039;padding:9px")
            sv.addWidget(cleanup_note)
            tabs.addTab(self.scrollable(storage), "Partições")

            profile = QWidget()
            pv = QVBoxLayout(profile)
            pv.addWidget(QLabel("Perfil de software — marcações refletem as stacks já existentes do instalador Bash."))
            self.preset = QComboBox()
            for name in ("Minimal", "Test", "Full", "Custom"):
                self.preset.addItem(name)
            self.preset.setCurrentText("Test")
            self.preset.currentTextChanged.connect(self.update_preset)
            self.preset.currentTextChanged.connect(self.refresh_summary)
            pv.addWidget(self.preset)
            self.checks = {}
            for stack in STACKS:
                box = QCheckBox(stack)
                box.stateChanged.connect(self.mark_custom)
                box.stateChanged.connect(self.refresh_summary)
                self.checks[stack] = box
                pv.addWidget(box)
            self.update_preset()
            form = QFormLayout()
            self.hostname = QLineEdit("wolf-linux")
            self.username = QLineEdit("wolf")
            self.hostname.textChanged.connect(self.refresh_summary)
            self.username.textChanged.connect(self.refresh_summary)
            form.addRow("Hostname", self.hostname)
            form.addRow("Usuário", self.username)
            pv.addLayout(form)
            pv.addWidget(QLabel("Senhas NÃO são coletadas nem armazenadas nesta prévia."))
            pv.addStretch()
            tabs.addTab(self.scrollable(profile), "Software e usuário")

            review = QWidget()
            rv = QVBoxLayout(review)
            self.summary = QPlainTextEdit()
            self.summary.setReadOnly(True)
            self.summary.setLineWrapMode(QPlainTextEdit.LineWrapMode.WidgetWidth)
            self.summary.setWordWrapMode(QTextOption.WrapAtWordBoundaryOrAnywhere)
            rv.addWidget(self.summary)
            cli = QPushButton("Validar plano JSON no backend (somente leitura)")
            cli.clicked.connect(self.review_backend_plan)
            rv.addWidget(cli)
            simulation = QPushButton("Simular etapas do backend Bash (não executa instalação)")
            simulation.clicked.connect(self.simulate_backend_plan)
            vm_trial = QPushButton("Instalar nesta VM (UEFI/GPT ou BIOS/MBR)")
            self.vm_install_button = vm_trial
            vm_trial.setStyleSheet("background:#5d2832;color:white;border:2px solid #be6570;padding:12px;")
            vm_trial.clicked.connect(self.execute_vm_install)
            rv.addWidget(vm_trial)
            self.lab42_button = QPushButton("Laboratório alpha42 — reinstalar somente a raiz da VM multidisco")
            self.lab42_button.setStyleSheet("background:#62472c;color:white;border:2px solid #bb925e;padding:12px;")
            self.lab42_button.setToolTip("SOMENTE VM de laboratório com seriais WOLF41EFI / WOLF41ROOT.\n"
                                              "Formata /dev/vdb1; preserva EFI, /home LVM e NTFS.")
            self.lab42_button.clicked.connect(self.execute_multidisk_lab42)
            self.lab42_button.setVisible(False)
            rv.addWidget(self.lab42_button)
            self.physical_rehearsal_button = QPushButton(
                "Ensaio físico integral — TODAS as etapas descritas, SEM EXECUTAR")
            self.physical_rehearsal_button.setToolTip(
                "Revalida UUID, fstab e PVs e lista todas as etapas do Bash, sem formatação, "
                "instalação de pacotes, montagem rw ou alteração da UEFI.")
            self.physical_rehearsal_button.clicked.connect(self.rehearse_physical)
            self.physical_rehearsal_button.setVisible(False)
            rv.addWidget(self.physical_rehearsal_button)
            self.physical_install_button = QPushButton(
                "INSTALAÇÃO FÍSICA REAL — somente raiz identificada por UUID")
            self.physical_install_button.setStyleSheet(
                "background:#602a30;color:#fff;border:2px solid #cb6370;padding:12px;")
            self.physical_install_button.setToolTip(
                "Requer UEFI, Live física, dois NVMe, /home multi-PV, fstab sem alterações."
                " FORMATARÁ a raiz; não exige backup geral, mas solicita duas confirmações.")
            self.physical_install_button.clicked.connect(self.execute_multidisk_physical)
            self.physical_install_button.setVisible(False)
            rv.addWidget(self.physical_install_button)
            rv.addWidget(simulation)
            legacy = QPushButton("Abrir planejamento CLI tradicional (independente)")
            legacy.clicked.connect(self.open_backend_plan)
            rv.addWidget(legacy)
            review_note = QLabel(
                "Revisar e Simular NÃO alteram discos. Instalar em VM executa SOMENTE "
                "Apagar disco inteiro ou Manual UEFI com partições explicitamente selecionadas. "
                "Reutilizar VM UEFI preserva EFI e /home separada, formatando somente /. "
                "O plano JSON não autoriza instalação sozinho; o modo físico exige preflight e confirmação dupla.")
            review_note.setWordWrap(True)
            rv.addWidget(review_note)
            tabs.addTab(self.scrollable(review), "Revisão")

            # Console PTY ocupa sua própria aba, NÃO uma faixa inferior.
            self.tabs = tabs
            console = QWidget()
            cv = QVBoxLayout(console)
            self.console_info = QLabel("A instalação será exibida aqui; terminal integrado interativo. Nenhuma operação em hardware físico.")
            self.console_info.setWordWrap(True)
            cv.addWidget(self.console_info)
            self.console_output = QPlainTextEdit()
            self.console_output.setReadOnly(True)
            self.console_output.setLineWrapMode(QPlainTextEdit.LineWrapMode.WidgetWidth)
            self.console_output.document().setMaximumBlockCount(4500)
            self.console_output.setStyleSheet("font:10pt monospace;background:#090e15;color:#d6e4f5")
            cv.addWidget(self.console_output, 1)
            line = QHBoxLayout()
            self.console_input = QLineEdit()
            self.console_input.setPlaceholderText("Entrada para o Bash: APAGAR, LIMPAR, senhas etc.")
            self.console_input.setEchoMode(QLineEdit.EchoMode.Password)
            self.console_input.setEnabled(False)
            self.console_input.returnPressed.connect(self.send_console_input)
            line.addWidget(self.console_input, 1)
            send = QPushButton("Enviar ↵")
            send.clicked.connect(self.send_console_input)
            line.addWidget(send)
            self.console_send = send
            send.setEnabled(False)
            self.console_reveal = QCheckBox("Mostrar entrada (não use para senhas)")
            self.console_reveal.toggled.connect(
                lambda checked: self.console_input.setEchoMode(
                    QLineEdit.EchoMode.Normal if checked else QLineEdit.EchoMode.Password))
            cv.addLayout(line)
            cv.addWidget(self.console_reveal)
            self.console_finish = QWidget()
            buttons = QHBoxLayout(self.console_finish)
            continue_live = QPushButton("Continuar na Live")
            continue_live.clicked.connect(self.close)
            reboot_now = QPushButton("Reiniciar agora")
            reboot_now.clicked.connect(self.reboot_after_success)
            buttons.addWidget(continue_live)
            buttons.addWidget(reboot_now)
            cv.addWidget(self.console_finish)
            self.console_finish.hide()
            self.console_tab_index = tabs.addTab(console, "Instalação")
            # Os QLabel longos devem quebrar linhas, mesmo em resoluções baixas.
            for label in wrapper.findChildren(QLabel):
                label.setWordWrap(True)
                label.setMinimumWidth(0)
            self.setCentralWidget(wrapper)
            self.populate_roles()
            self.update_storage_controls()
            self.refresh_disk()
            self.refresh_summary()

        @staticmethod
        def scrollable(content):
            area = QScrollArea()
            area.setWidgetResizable(True)
            area.setFrameShape(QFrame.Shape.NoFrame)
            # Toda a página usa largura da aba; sem barra horizontal.
            area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
            content.setMinimumWidth(0)
            area.setWidget(content)
            return area

        def run_command(self, argv):
            ok, msg = launch(argv)
            if not ok:
                QMessageBox.warning(self, "Wolf Live", msg)

        def reload_disks(self):
            # Inventário novo invalida qualquer prévia autodetectada anterior.
            self.md_snapshot = None
            self.md_candidate.clear()
            self.md_confirm.setChecked(False)
            self.md_override.setChecked(False)
            self.md_status.setText("Inventário alterado: execute novamente a detecção multidisco.")
            self.disks = disk_inventory()
            self.disk_combo.blockSignals(True)
            self.disk_combo.clear()
            self.disk_combo.addItem("Selecione um disco", "")
            for d in self.disks:
                self.disk_combo.addItem(f"{d['path']} — {format_size(d['size'])} — {d['model']}", d["path"])
            self.disk_combo.blockSignals(False)
            self.refresh_disk()
            self.update_erase_bounds()
            self.refresh_summary()

        def selected_disk(self):
            path = str(self.disk_combo.currentData() or "")
            return next((d for d in self.disks if d["path"] == path), None)

        def on_erase_size_changed(self, role, value):
            if self._syncing_erase_size:
                return
            self.update_erase_bounds(changed=role, requested=value)
            self.refresh_summary()

        def update_erase_bounds(self, changed=None, requested=None):
            """Restringe barra e campo aos GiB realmente disponíveis.

            A mudança de disco/firmware/home recalcula todos os limites.
            Alterar uma partição jamais aumenta silenciosamente a outra.
            """
            if self._syncing_erase_size:
                return
            self._syncing_erase_size = True
            try:
                disk = self.selected_disk()
                size = int(disk["size"]) if disk else 0
                boot = "UEFI" if Path("/sys/firmware/efi").exists() else "BIOS"
                layout = self.home_layout.currentData()
                usable = wolf_plan.erase_usable_gib(size, boot)
                root = self.erase_root_gib.value()
                home = self.erase_home_gib.value() if layout == "separate" else 0
                if changed == "root":
                    root = requested
                elif changed == "home":
                    home = requested
                if layout == "separate":
                    if usable >= 30:
                        root = min(max(20, root or 40), usable - 10)
                        home = 0 if home == 0 else max(10, home)
                        if changed == "home" and home:
                            home = min(home, usable - 20)
                            root = min(root, usable - home)
                        elif home and home > usable - root:
                            home = usable - root
                    else:
                        root, home = 0, 0
                else:
                    root = max(0, min(root, usable))
                    if root and root < 20 and usable >= 20:
                        root = 20
                    home = 0
                bounds = wolf_plan.erase_size_bounds(size, boot, layout, root, home)
                root_min = bounds["root_min"] if usable >= 30 or layout == "in-root" else 0
                root_max = bounds["root_max"]
                # Qt exibe specialValueText em TODO valor mínimo. No modo
                # separado, mínimo é 20 GiB, portanto NÃO pode dizer 'Restante'.
                self.erase_root_gib.setSpecialValueText(
                    "Restante do disco" if layout == "in-root" else "")
                for ctrl, minimum, maximum, value in (
                    (self.erase_root_gib, root_min, root_max, root),
                    (self.erase_root_slider, root_min, root_max, root),
                    (self.erase_home_gib, 0, bounds["home_max"], home),
                    (self.erase_home_slider, 0, bounds["home_max"], home),
                ):
                    ctrl.blockSignals(True)
                    ctrl.setRange(minimum, max(minimum, maximum))
                    ctrl.setValue(value)
                    ctrl.blockSignals(False)
                available = disk is not None and usable >= (30 if layout == "separate" else 20)
                active = self.storage_mode.currentData() == "erase" and available
                for ctrl in (self.erase_root_gib, self.erase_root_slider):
                    ctrl.setEnabled(active)
                for ctrl in (self.erase_home_gib, self.erase_home_slider):
                    ctrl.setEnabled(active and layout == "separate")
                if disk is None:
                    label = "Selecione um disco para calcular o limite dos tamanhos."
                elif not available:
                    label = (f"Disco {disk['path']}: {size / 1024**3:.2f} GiB. "
                             "Espaço insuficiente para as partições escolhidas.")
                else:
                    label = (f"Disco {disk['path']}: {size / 1024**3:.2f} GiB | "
                             f"disponível para partições: {usable} GiB "
                             f"(inclui reserva de EFI 1 GiB: {'sim' if boot == 'UEFI' else 'não'}; "
                             "folga técnica 1 GiB). "
                             f"Raiz: até {root_max} GiB" +
                             (f" | /home: até {bounds['home_max']} GiB" if layout == "separate" else ""))
                self.erase_capacity_label.setText(label)
            finally:
                self._syncing_erase_size = False

        def update_storage_controls(self, *_):
            mode = self.storage_mode.currentData()
            previous_mode = getattr(self, "_last_storage_mode", mode)
            if mode != previous_mode:
                # Consentimento para REUTILIZAR não pode migrar silenciosamente
                # para MANUAL, que é executável; exigir nova marcação e aviso.
                for flag in self.partition_format.values():
                    flag.blockSignals(True)
                    flag.setChecked(False)
                    flag.blockSignals(False)
            self._last_storage_mode = mode
            self.cleanup_home_check.setEnabled(mode == "reuse" and self.home_layout.currentData() == "separate")
            if not self.cleanup_home_check.isEnabled():
                self.cleanup_home_check.blockSignals(True)
                self.cleanup_home_check.setChecked(False)
                self.cleanup_home_check.blockSignals(False)
            enabled = mode != "erase"
            multidisk = self.multidisk_active()
            self.disk_combo.setEnabled(not multidisk)
            separate = self.home_layout.currentData() == "separate"
            self.home_layout.setEnabled(True)
            self.erase_size_title.setVisible(not enabled)
            self.erase_capacity_label.setVisible(not enabled)
            self.erase_root_gib.setVisible(not enabled)
            self.erase_root_slider.setVisible(not enabled)
            self.erase_home_label.setVisible(not enabled and separate)
            self.erase_home_gib.setVisible(not enabled and separate)
            self.erase_home_slider.setVisible(not enabled and separate)
            self.erase_home_hint.setVisible(not enabled and separate)
            self.bios_esp_notice.setVisible(not Path("/sys/firmware/efi").exists())
            self.update_erase_bounds()
            # Não deixar seleção desabilitada latente: o usuário escolheu /home em /.
            if not separate:
                home = self.partition_roles["home"]
                home.blockSignals(True)
                home.setCurrentIndex(0)
                home.blockSignals(False)
                flag = self.partition_format["home"]
                flag.blockSignals(True)
                flag.setChecked(False)
                flag.blockSignals(False)
            # Nunca manter uma intenção de formatação silenciosa ao sair do modo
            # Reutilizar/Manual e voltar para ele.
            if not enabled:
                for flag in self.partition_format.values():
                    flag.blockSignals(True)
                    flag.setChecked(False)
                    flag.blockSignals(False)
            for role, widget in self.partition_roles.items():
                widget.setEnabled(enabled and not multidisk and (role != "home" or separate))
            for role, widget in self.partition_format.items():
                widget.setEnabled(enabled and not multidisk and (role != "home" or separate)
                                  and (mode != "reuse" or role == "root"))
            # BIOS nunca recebe partição ESP, mesmo que houvesse uma seleção
            # anterior do usuário na GUI. UEFI mantém comportamento existente.
            bios = not Path("/sys/firmware/efi").exists()
            if bios:
                esp_combo = self.partition_roles["esp"]
                esp_combo.blockSignals(True)
                esp_combo.setCurrentIndex(0)
                esp_combo.blockSignals(False)
                fmt_esp = self.partition_format["esp"]
                fmt_esp.blockSignals(True)
                fmt_esp.setChecked(False)
                fmt_esp.blockSignals(False)
                esp_combo.setEnabled(False)
                fmt_esp.setEnabled(False)
            if hasattr(self, "vm_install_button"):
                current_mode = self.storage_mode.currentData()
                self.vm_install_button.setEnabled(True)
                if self.multidisk_active():
                    self.vm_install_button.setEnabled(False)
                self.vm_install_button.setText({
                    "erase": "Instalar nesta VM — APAGAR TODO O DISCO",
                    "manual": "Instalar nesta VM — MANUAL (UEFI/GPT ou BIOS/MBR)",
                    "reuse": "Instalar nesta VM — REUTILIZAR /home e EFI (se UEFI)",
                }[current_mode])
            self.update_format_notice()
            self.refresh_summary()

        def confirm_home_cleanup(self, checked):
            if checked:
                text = ("REMOVER TODAS AS CONFIGURAÇÕES OCULTAS DOS USUÁRIOS?\n\n"
                        "A partição /home NÃO será formatada e os arquivos visíveis serão mantidos, "
                        "mas diretórios ocultos poderão conter chaves SSH, cofres de senhas, "
                        "e-mails e perfis de aplicativos. Esta remoção NÃO pode ser desfeita.\n\n"
                        "Uma lista completa será mostrada no terminal ANTES de formatar /. "
                        "Será preciso digitar LIMPAR para autorizar. Continuar?")
                accepted = QMessageBox.warning(
                    self, "ATENÇÃO — CONFIGURAÇÕES E CREDENCIAIS", text,
                    QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                    QMessageBox.StandardButton.No) == QMessageBox.StandardButton.Yes
                if not accepted:
                    self.cleanup_home_check.blockSignals(True)
                    self.cleanup_home_check.setChecked(False)
                    self.cleanup_home_check.blockSignals(False)
            self.refresh_summary()

        def on_partition_changed(self, role):
            # Consentimento sobre /dev/...p2 não deve ser carregado ao escolher p3.
            flag = self.partition_format[role]
            flag.blockSignals(True)
            flag.setChecked(False)
            flag.blockSignals(False)
            self.update_format_notice()
            self.refresh_summary()

        def confirm_format_intent(self, role, checked):
            if checked:
                partition = self.partition_roles[role].currentData()
                if not partition:
                    QMessageBox.warning(
                        self, "Selecione a partição",
                        "Escolha a partição antes de marcar a formatação.")
                    accepted = False
                else:
                    answer = QMessageBox.warning(
                        self, "ATENÇÃO — PERDA DE DADOS",
                        format_intent_warning(role, self.home_layout.currentData(), partition),
                        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                        QMessageBox.StandardButton.No,
                    )
                    accepted = answer == QMessageBox.StandardButton.Yes
                if not accepted:
                    flag = self.partition_format[role]
                    flag.blockSignals(True)
                    flag.setChecked(False)
                    flag.blockSignals(False)
            self.update_format_notice()
            self.refresh_summary()

        def update_format_notice(self):
            if self.storage_mode.currentData() == "erase":
                disk = self.disk_combo.currentData() or "(selecione o disco)"
                self.format_notice.setText(
                    "⚠ APAGAR DISCO INTEIRO: " + str(disk) + ".\n"
                    "A execução experimental em VM QEMU/KVM APAGARÁ TODAS AS PARTIÇÕES "
                    "E ARQUIVOS do disco selecionado, mesmo que já tenha partições. Somente disco VirtIO descartável; "
                    "comando separado e confirmação obrigatória no terminal.")
                self.format_notice.show()
                return
            flagged = [role for role, widget in self.partition_format.items()
                       if widget.isEnabled() and widget.isChecked()]
            if flagged:
                names = {"root": "RAIZ /", "esp": "EFI /boot/efi", "home": "/home"}
                devices = ", ".join(f"{names[role]} ({self.partition_roles[role].currentData()})"
                                    for role in flagged)
                self.format_notice.setText(
                    "⚠ FORMATAÇÃO SELECIONADA: " + devices + ".\n"
                    "No MANUAL VM, são formatadas apenas as partições marcadas. "
                    "No REUTILIZAR VM, somente a raiz / é formatada; EFI e /home são preservadas.")
                self.format_notice.show()
            else:
                self.format_notice.hide()

        def open_cleanup_assistant(self):
            disk = str(self.disk_combo.currentData() or "")
            if not disk:
                QMessageBox.warning(self, "Escolha o disco", "Selecione o disco da VM antes de recuperar uma tentativa.")
                return
            if QMessageBox.question(self, "Desmontagem assistida",
                                    f"Examinar APENAS as montagens sob /mnt do disco {disk}?\n"
                                    "O terminal mostrará os pontos de montagem antes de pedir confirmação.\n"
                                    "Discos não serão formatados.") == QMessageBox.StandardButton.Yes:
                self.run_command(["qterminal", "-e", "wolf-live-cleanup-vm", disk])

        def change_keyboard(self):
            dialog = KeyboardDialog()
            if dialog.exec() == QDialog.DialogCode.Accepted:
                self.keyboard = dialog.layouts.currentData()
                self.refresh_summary()

        def populate_roles(self):
            disk_path = str(self.disk_combo.currentData() or "")
            disk = next((d for d in self.disks if d["path"] == disk_path), None)
            labels = {"root": "RAIZ / — sistema operacional",
                      "esp": "EFI /boot/efi — inicialização UEFI",
                      "home": "HOME /home — arquivos pessoais (opcional)"}
            for role, combo in self.partition_roles.items():
                previous = combo.currentData()
                combo.blockSignals(True)
                combo.clear()
                combo.addItem(f"{labels[role]}: não selecionada", None)
                for part in (disk or {}).get("partitions", []):
                    combo.addItem(f"{labels[role]}: {part['path']} — {format_size(part['size'])} — {part['fstype']}", part["path"])
                found = combo.findData(previous)
                combo.setCurrentIndex(found if found >= 0 else 0)
                combo.blockSignals(False)
            # Trocar o disco invalida consentimentos dados para partições antigas.
            for flag in self.partition_format.values():
                flag.blockSignals(True)
                flag.setChecked(False)
                flag.blockSignals(False)
            self.update_format_notice()

        def scan_installations(self):
            if self.storage_mode.currentData() != "reuse":
                QMessageBox.information(self, "Selecione Reutilizar", "A descoberta multidisco é usada no modo Reutilizar partições existentes.")
                return
            self.md_snapshot = None
            self.md_confirm.setChecked(False)
            self.md_override.setChecked(False)
            self.md_status.setText("Procurando instalações existentes em todos os discos... aguarde.")
            self.md_diagnostics.setPlainText("Consultando ext4 e fstab sem recuperar journal nem modificar discos...")
            QApplication.processEvents()
            try:
                result = subprocess.run(
                    ["sudo", "-n", "/usr/bin/python3", "/usr/local/share/wolf-linux-live/gui/wolf_discovery.py", "scan"],
                    capture_output=True, text=True, timeout=100, check=False)
                if result.returncode:
                    raise wolf_discovery.DiscoveryError(result.stderr.strip() or "Falha no inventário")
                data = json.loads(result.stdout)
                if data.get("schema") != wolf_discovery.SNAPSHOT_SCHEMA or data.get("execution") != "disabled":
                    raise wolf_discovery.DiscoveryError("O scanner retornou um contrato inesperado")
                self.md_snapshot = data
                self.md_candidate.blockSignals(True)
                self.md_candidate.clear()
                for candidate in data["candidates"]:
                    path = candidate["root"]
                    self.md_candidate.addItem(f"Instalação: raiz {path} — fstab confirmado", path)
                self.md_candidate.blockSignals(False)
                self.md_status.setText(f"{len(data['candidates'])} instalação(ões) identificada(s). "
                                       + ("Há diagnóstico(s) abaixo; nenhuma recuperação foi executada."
                                          if data['errors'] else "Escolha e confira cada volume."))
                self.md_diagnostics.setPlainText(
                    "\n\n".join(data['errors']) if data['errors'] else
                    "Nenhum bloqueio de leitura ext4 detectado. UUIDs/fstab devem ser confirmados na revisão.")
                self.populate_md_roles()
                self.choose_detected_installation()
            except (OSError, json.JSONDecodeError, ValueError, subprocess.TimeoutExpired) as exc:
                self.md_status.setText(f"Falha na detecção: {exc}")
                self.md_diagnostics.setPlainText(str(exc))
                QMessageBox.warning(self, "Detecção não concluída", str(exc))
            self.update_storage_controls()
            self.refresh_summary()

        def populate_md_roles(self):
            if not self.md_snapshot:
                return
            choices = sorted(self.md_snapshot['devices'].items())
            for role, combo in self.md_roles.items():
                combo.blockSignals(True)
                combo.clear()
                combo.addItem("Nenhuma partição dedicada", None)
                fs = 'vfat' if role == 'esp' else 'ext4'
                for path, info in choices:
                    if info['fstype'] != fs or info['usb_ancestor']:
                        continue
                    disks = ', '.join(info['parent_disks'])
                    size = info['size'] / 1024**3
                    combo.addItem(f"{path} — {size:.1f} GiB ({fs}) — {disks}", path)
                combo.blockSignals(False)

        def choose_detected_installation(self, *_):
            if not self.md_snapshot:
                return
            root = self.md_candidate.currentData()
            candidate = next((c for c in self.md_snapshot['candidates'] if c['root'] == root), None)
            if not candidate:
                return
            for role, combo in self.md_roles.items():
                wanted = candidate['suggestions'][role]
                combo.blockSignals(True)
                idx = combo.findData(wanted)
                combo.setCurrentIndex(idx if idx >= 0 else 0)
                combo.blockSignals(False)
            self.md_confirm.setChecked(False)
            self.md_override.setChecked(False)
            self.md_choices_changed()

        def md_choices_changed(self, *_):
            if not self.md_snapshot:
                return
            self.md_confirm.setChecked(False)
            root = self.md_candidate.currentData()
            cand = next((c for c in self.md_snapshot['candidates'] if c['root'] == root), None)
            if not cand:
                return
            changes = [role for role, combo in self.md_roles.items()
                       if combo.currentData() != cand['suggestions'][role]]
            if changes:
                self.md_warning.setText("DIVERGÊNCIA DO FSTAB em " + ', '.join(changes) +
                    ". Confira UUIDs e marque a confirmação separada. NADA será formatado pela simulação.")
            else:
                self.md_override.setChecked(False)
                self.md_warning.setText("CONFIRA: apenas / poderá ser formatada pelo executor físico protegido; EFI e /home serão preservadas, se o preflight aprovar.")
            if hasattr(self, 'vm_install_button'):
                self.vm_install_button.setEnabled(not self.multidisk_active())
            active = self.multidisk_active()
            if hasattr(self, 'lab42_button'):
                is_lab = (Path('/dev/disk/by-id/virtio-WOLF41EFI').is_symlink() and
                          Path('/dev/disk/by-id/virtio-WOLF41ROOT').is_symlink() and
                          Path('/run/archiso/airootfs').is_dir() and
                          Path('/sys/firmware/efi').is_dir())
                self.lab42_button.setVisible(active and is_lab)
                self.lab42_button.setEnabled(active and is_lab and self._installer_pty is None)
            if hasattr(self, 'physical_rehearsal_button'):
                self.physical_rehearsal_button.setVisible(active)
                self.physical_rehearsal_button.setEnabled(active and self._installer_pty is None)
            if hasattr(self, 'physical_install_button'):
                physical = active and Path('/sys/firmware/efi').is_dir() and \
                    Path('/run/archiso/airootfs').is_dir() and not \
                    Path('/dev/disk/by-id/virtio-WOLF41EFI').exists()
                self.physical_install_button.setVisible(physical)
                self.physical_install_button.setEnabled(physical and self._installer_pty is None)
            self.disk_combo.setEnabled(not active)
            for combo in self.partition_roles.values():
                combo.setEnabled(not active)
            self.refresh_summary()

        def multidisk_active(self):
            return (self.storage_mode.currentData() == 'reuse' and
                    self.md_snapshot is not None and bool(self.md_candidate.currentData()))

        def multidisk_plan(self):
            return wolf_discovery.build_plan(
                self.md_snapshot, root=str(self.md_candidate.currentData()),
                esp=self.md_roles['esp'].currentData(), home=self.md_roles['home'].currentData(),
                confirmed=self.md_confirm.isChecked(),
                acknowledge_override=self.md_override.isChecked(),
                username=self.username.text().strip(), hostname=self.hostname.text().strip(),
                preset=self.preset.currentText().lower(),
                stacks=self.selected_stacks(),
                keyboard=dict(zip(('layout','model','variant'), self.keyboard)))

        def current_preview(self):
            if self.multidisk_active():
                return self.multidisk_plan()
            preset = self.preset.currentText().lower()
            mode = self.storage_mode.currentData()
            roles = {k: c.currentData() for k, c in self.partition_roles.items()}
            formats = {k: c.isChecked() for k, c in self.partition_format.items()}
            home_layout = self.home_layout.currentData()
            if home_layout == "in-root":
                roles["home"] = None
                formats["home"] = False
            if mode == "erase":
                roles = dict.fromkeys(roles)
                formats = dict.fromkeys(formats, False)
            return wolf_plan.build_preview(
                disks=self.disks,
                disk_path=str(self.disk_combo.currentData() or ""),
                mode=mode, preset=preset,
                stacks=self.selected_stacks(),
                hostname=self.hostname.text().strip(), username=self.username.text().strip(),
                keyboard=dict(zip(("layout", "model", "variant"), self.keyboard)),
                boot_mode="UEFI" if Path("/sys/firmware/efi").exists() else "BIOS",
                roles=roles, formats=formats, home_layout=home_layout,
                cleanup_home=self.cleanup_home_check.isChecked() if mode == "reuse" else False,
                erase_sizes={"root_gib": self.erase_root_gib.value() if mode == "erase" else 0,
                             "home_gib": self.erase_home_gib.value() if mode == "erase" and home_layout == "separate" else 0},
            )

        def review_backend_plan(self):
            try:
                doc = self.current_preview()
                plan_file = wolf_plan.write_private(doc)
            except (ValueError, OSError) as exc:
                QMessageBox.warning(self, "Plano inválido", str(exc))
                return
            response = QMessageBox.question(
                self, "Revisão somente leitura",
                f"O documento será revisado pelo backend Bash, sem instalação.\n"
                f"Arquivo privado: {plan_file}\nContinuar?"
            )
            if response == QMessageBox.StandardButton.Yes:
                self.run_command(["qterminal", "-e", "wolf-live-review-plan", str(plan_file)])

        def simulate_backend_plan(self):
            try:
                doc = self.current_preview()
                plan_file = wolf_plan.write_private(doc)
            except (ValueError, OSError) as exc:
                QMessageBox.warning(self, "Plano inválido", str(exc))
                return
            response = QMessageBox.question(
                self, "Simular instalação (SEM EXECUTAR)",
                "O backend lerá o documento e apresentará etapas e impedimentos, "
                "mas não poderá instalar, montar ou formatar nada. Continuar?")
            if response == QMessageBox.StandardButton.Yes:
                self.run_command(["qterminal", "-e", "wolf-live-simulate-plan", str(plan_file)])

        def rehearse_physical(self):
            """Planejamento independente do executor: NUNCA altera dispositivos."""
            if not self.multidisk_active():
                QMessageBox.warning(self, "Ensaio indisponível",
                                    "Selecione Reutilizar e detecte uma instalação multidisco.")
                return
            try:
                doc = self.multidisk_plan()
                plan_file = wolf_plan.write_private(doc)
            except (ValueError, KeyError, OSError) as exc:
                QMessageBox.warning(self, "Plano inválido", str(exc))
                return
            answer = QMessageBox.question(
                self, "Ensaio físico integral — SEM ESCRITA",
                "O relatório percorrerá todas as etapas reais do Bash, "
                "mas NÃO executará formatação, pacstrap, chroot, montagem RW nem GRUB.\n\n"
                "Este ensaio não homologa execução física ou boot. Continuar?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No)
            if answer == QMessageBox.StandardButton.Yes:
                self.run_command(["qterminal", "-e", "wolf-live-physical-rehearsal", str(plan_file)])

        def execute_multidisk_physical(self):
            """Somente interface: o backend físico INDEPENDENTE valida tudo novamente."""
            if self._installer_pty is not None or not self.multidisk_active():
                QMessageBox.warning(self, 'Execução física indisponível', 'Plano ausente ou execução em andamento.')
                return
            try:
                doc = self.multidisk_plan()
                if doc['boot_mode'] != 'UEFI' or doc['acknowledge_override'] or \
                        not all(doc['roles'][role] for role in ('root', 'esp', 'home')):
                    raise ValueError('Este executor exige UEFI sem alterações manuais do fstab.')
                root = doc['roles']['root']['path']
                plan_file = wolf_plan.write_private(doc)
            except (ValueError, KeyError, OSError) as exc:
                QMessageBox.warning(self, 'Plano físico recusado', str(exc))
                return
            check = subprocess.run(
                ['sudo', '-n', 'wolf-install', '--preflight-multidisk-physical', str(plan_file)],
                capture_output=True, text=True, timeout=130, check=False)
            if check.returncode:
                QMessageBox.warning(self, 'Preflight físico BLOQUEOU a instalação',
                                    (check.stderr or check.stdout)[-2800:])
                return
            message = ('INSTALAÇÃO FÍSICA REAL.\n\n'
                       + check.stdout + '\n\nNÃO HÁ BACKUP GERAL. '                       'A raiz será definitivamente formatada. Uma falha pode deixar o sistema sem boot.\n'
                       'EFI, Microsoft, GRUB, NTFS e /home LVM serão preservados.\n'
                       'Depois serão exigidas duas confirmações no terminal. Prosseguir?')
            response = QMessageBox.warning(
                self, 'RISCO DE PERDA REAL — SSD NVMe', message,
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                QMessageBox.StandardButton.Cancel)
            if response != QMessageBox.StandardButton.Yes:
                return
            consent, ok = QInputDialog.getText(
                self, 'Confirmar raiz que será apagada',
                f'Digite exatamente FORMATAR {root}:')
            if not ok or consent != f'FORMATAR {root}':
                return
            self.tabs.setCurrentIndex(self.console_tab_index)
            self.console_output.clear()
            self.console_finish.hide()
            self._installer_finished = False
            self.console_info.setText('INSTALAÇÃO FÍSICA REAL: somente raiz. Acompanhe os avisos e confirmações.')
            try:
                log_dir = Path.home() / '.local/state/wolf-linux/live-installer'
                log_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
                fd, name = tempfile.mkstemp(prefix='physical47-', suffix='.log', dir=str(log_dir))
                os.fchmod(fd, 0o600)
                self._installer_log = os.fdopen(fd, 'w', encoding='utf-8', errors='replace')
                engine = InstallerPty()
                master = engine.start(plan_file, mode='--execute-multidisk-physical')
                self._installer_pty = engine
                self._pty_notifier = QSocketNotifier(master, QSocketNotifier.Type.Read, self)
                self._pty_notifier.activated.connect(self.read_console_output)
                self.console_input.setEnabled(True)
                self.console_send.setEnabled(True)
                self.console_input.setFocus()
                self._vm_result_poll.start()
            except (OSError, ValueError, RuntimeError) as exc:
                if self._installer_log:
                    self._installer_log.close()
                    self._installer_log = None
                QMessageBox.critical(self, 'Não foi possível iniciar executor físico', str(exc))

        def execute_multidisk_lab42(self):
            """Executor REAL apenas do QEMU Lab41, preservando TODOS os outros volumes."""
            if self._installer_pty is not None or not self.multidisk_active():
                QMessageBox.warning(self, 'Lab42 bloqueado', 'Nenhum plano multidisco válido ou execução já ativa.')
                return
            if not (Path('/dev/disk/by-id/virtio-WOLF41EFI').is_symlink() and
                    Path('/dev/disk/by-id/virtio-WOLF41ROOT').is_symlink() and
                    Path('/run/archiso/airootfs').is_dir()):
                QMessageBox.warning(self, 'Lab42 bloqueado', 'Exige os DOIS discos dedicados do laboratório QEMU.')
                return
            try:
                doc = self.multidisk_plan()
                if [doc['roles'][k]['path'] if doc['roles'][k] else None
                        for k in ('root', 'esp', 'home')] != \
                        ['/dev/vdb1', '/dev/vda1', '/dev/mapper/vg_monstro-lv_projetos']:
                    raise ValueError('Dispositivos fora da topologia alpha41 do laboratório')
                plan_file = wolf_plan.write_private(doc)
            except (ValueError, KeyError, OSError) as exc:
                QMessageBox.warning(self, 'Plano Lab42 recusado', str(exc))
                return
            warning = ('LABORATÓRIO ALPHA42: EXECUÇÃO DE INSTALAÇÃO REAL NA VM!\n\n'
                       'SERÁ FORMATADA EM EXT4: /dev/vdb1 — perda total dos dados da raiz.\n'
                       'SERÃO PRESERVADOS: /dev/vda1 (EFI), /dev/vdb2 (NTFS),\n'
                       '/dev/vda2 e /dev/vdb3 (PVs), e o LV /home.\n\n'
                       'A verificação independente do Bash recusará hardware físico,\n'
                       'seriais diferentes, montagens ativas e alterações nos UUIDs.\n'
                       'Você terá de confirmar novamente no terminal integrado.\n\n'
                       'Continuar?')
            choice = QMessageBox.warning(self, 'ATENÇÃO — Lab42 formata /dev/vdb1', warning,
                                         QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                                         QMessageBox.StandardButton.Cancel)
            if choice != QMessageBox.StandardButton.Yes:
                return
            if VmEraseConsentDialog(self, '/dev/vdb1').exec() != QDialog.DialogCode.Accepted:
                return
            self.tabs.setCurrentIndex(self.console_tab_index)
            self.console_output.clear()
            self.console_finish.hide()
            self._installer_finished = False
            self.console_info.setText('ALPHA42 — reinstalação VM multidisco. Formatação EXCLUSIVA de /dev/vdb1. Responda às confirmações no campo abaixo.')
            try:
                log_dir = Path.home() / '.local/state/wolf-linux/live-installer'
                log_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
                fd, name = tempfile.mkstemp(prefix='lab42-install-', suffix='.log', dir=str(log_dir))
                os.fchmod(fd, 0o600)
                self._installer_log = os.fdopen(fd, 'w', encoding='utf-8', errors='replace')
                engine = InstallerPty()
                master = engine.start(plan_file, mode='--execute-multidisk-lab-vm')
                self._installer_pty = engine
                self._pty_notifier = QSocketNotifier(master, QSocketNotifier.Type.Read, self)
                self._pty_notifier.activated.connect(self.read_console_output)
                self.console_input.setEnabled(True)
                self.console_send.setEnabled(True)
                self.console_input.setFocus()
                self._vm_result_poll.start()
            except (OSError, ValueError, RuntimeError) as exc:
                if self._installer_log:
                    self._installer_log.close()
                    self._installer_log = None
                QMessageBox.critical(self, 'Falha ao iniciar Lab42', str(exc))
                self.console_info.setText('Não foi possível abrir o executor Lab42.')

        def execute_vm_install(self):
            if self._installer_pty is not None:
                QMessageBox.warning(self, "Instalação em andamento",
                                    "Aguarde a conclusão da instalação VM anterior.")
                return
            if self.multidisk_active():
                QMessageBox.warning(self, "Somente simulação multidisco",
                    "Use o executor específico do laboratório ou o físico protegido. "
                    "Use Revisar e Simular, que não executam nenhuma operação.")
                return
            try:
                doc = self.current_preview()
                # Pré-checagem do plano na GUI, sem privilégio: o backend
                # repetirá tudo como root antes de solicitar confirmação.
                wolf_plan.vm_execution_fields(
                    doc, disks=wolf_plan.inventory(),
                    active_boot="UEFI" if Path("/sys/firmware/efi").exists() else "BIOS")
                plan_file = wolf_plan.write_private(doc)
            except (ValueError, OSError, KeyError) as exc:
                error = str(exc)
                if "montad" in error.lower() or "em uso" in error.lower():
                    answer = QMessageBox.question(
                        self, "Partição já montada",
                        error + "\n\nDeseja abrir a desmontagem assistida para /mnt? "
                        "Ela não desmontará outros locais nem apagará dados.",
                        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                        QMessageBox.StandardButton.No)
                    if answer == QMessageBox.StandardButton.Yes:
                        self.open_cleanup_assistant()
                else:
                    QMessageBox.warning(self, "Instalação VM BLOQUEADA", error)
                return
            disk = doc["storage"]["disk"]["path"]
            # Uma QMessageBox simples não foi percebida na VM alpha26.
            # Diálogo MODAL com digitação exata torna a confirmação verificável.
            if doc["storage"]["mode"] == "reuse":
                QMessageBox.information(
                    self, "Reutilização VM — preservação",
                    "A raiz / será formatada em ext4. A partição /home "
                    "e, em UEFI, a EFI FAT32 serão preservadas SEM formatação.\n\n"
                    + ("Você solicitou limpeza dos arquivos ocultos de todos os usuários. "
                       "O terminal exigirá uma segunda confirmação LIMPAR antes da formatação. "
                       if doc["storage"]["cleanup_home"] else
                       "As configurações ocultas de /home também serão preservadas."))
            if doc["storage"]["mode"] == "manual":
                root_part = doc["storage"]["partitions"]["root"]
                esp_part = doc["storage"]["partitions"]["esp"]
                home_part = doc["storage"]["partitions"]["home"]
                home_line = (f"{'FORMATAR EXT4' if doc['storage']['format']['home'] else 'PRESERVAR'}: /home = {home_part}\n\n"
                             if home_part else "SEM PARTIÇÃO /home: ficará dentro da raiz FORMATADA.\n\n")
                description = (f"INSTALAÇÃO MANUAL NA VM {disk}\n\n"
                               f"FORMATAR (APAGAR DADOS): raiz / = {root_part}\n"
                               f"{('FORMATAR FAT32' if doc['storage']['format']['esp'] else 'PRESERVAR') + ': EFI = ' + str(esp_part) if esp_part else 'BIOS/Legacy: SEM partição EFI'}\n"
                               + home_line
                               + ("A flag GPT ESP será aplicada automaticamente à EFI selecionada.\n" if esp_part else "GRUB BIOS será instalado no disco MBR selecionado.\n")
                               + "O GParted não é acionado automaticamente.")
                if QMessageBox.warning(self, "Confirme as partições manuais", description,
                                       QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                                       QMessageBox.StandardButton.Cancel) != QMessageBox.StandardButton.Yes:
                    return
            if VmEraseConsentDialog(self, disk).exec() != QDialog.DialogCode.Accepted:
                return
            self.tabs.setCurrentIndex(self.console_tab_index)
            self.console_output.clear()
            self.console_finish.hide()
            self._installer_finished = False
            self.console_info.setText(
                "INSTALAÇÃO EM ANDAMENTO — disco " + disk + ". "
                "Digite as respostas solicitadas pelo Bash no campo abaixo e pressione Enter. "
                "A entrada começa oculta para proteger senhas.")
            try:
                log_dir = Path.home() / ".local/state/wolf-linux/live-installer"
                log_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
                fd, name = tempfile.mkstemp(prefix="vm-install-", suffix=".log", dir=str(log_dir))
                os.fchmod(fd, 0o600)
                self._installer_log = os.fdopen(fd, "w", encoding="utf-8", errors="replace")
                engine = InstallerPty()
                master = engine.start(plan_file)
                self._installer_pty = engine
                self._pty_notifier = QSocketNotifier(master, QSocketNotifier.Type.Read, self)
                self._pty_notifier.activated.connect(self.read_console_output)
                self.console_input.setEnabled(True)
                self.console_send.setEnabled(True)
                self.console_input.setFocus()
                self._vm_result_poll.start()
            except (OSError, ValueError, RuntimeError) as exc:
                if self._installer_log:
                    self._installer_log.close()
                    self._installer_log = None
                QMessageBox.critical(self, "Falha ao iniciar instalação", str(exc))
                self.console_info.setText("Não foi possível iniciar o terminal integrado.")

        def send_console_input(self):
            if not self._installer_pty or self._installer_pty.poll() is not None:
                return
            value = self.console_input.text()
            self.console_input.clear()
            try:
                self._installer_pty.send(value)
            except (OSError, ValueError, RuntimeError) as exc:
                QMessageBox.warning(self, "Entrada inválida", str(exc))

        def read_console_output(self):
            if not self._installer_pty:
                return
            try:
                output, ended = self._installer_pty.read()
            except OSError as exc:
                self.console_info.setText("Erro de leitura do console: " + str(exc))
                return
            if output:
                if self._installer_log:
                    self._installer_log.write(output)
                    self._installer_log.flush()
                self.console_output.moveCursor(QTextCursor.MoveOperation.End)
                self.console_output.insertPlainText(output.replace("\r", ""))
                self.console_output.ensureCursorVisible()
            if ended and self._pty_notifier:
                self._pty_notifier.setEnabled(False)

        def check_vm_install_result(self):
            engine = self._installer_pty
            if engine is None:
                return
            rc = engine.poll()
            if rc is None:
                return
            self.read_console_output()
            self._vm_result_poll.stop()
            if self._pty_notifier:
                self._pty_notifier.setEnabled(False)
                self._pty_notifier.deleteLater()
                self._pty_notifier = None
            engine.close_read()
            self._installer_pty = None
            self.console_input.setEnabled(False)
            self.console_send.setEnabled(False)
            if self._installer_log:
                self._installer_log.close()
                self._installer_log = None
            self._installer_finished = True
            if rc == 0:
                self.console_info.setText(
                    "WOLF LINUX INSTALADO COM SUCESSO! Você pode reiniciar ou continuar na Live. "
                    "Remova a ISO ou altere a ordem de boot antes do reinício.")
                self.console_finish.show()
                self.console_output.appendPlainText("\n[OK] INSTALAÇÃO CONCLUÍDA — código 0")
            else:
                self.console_info.setText(
                    f"INSTALAÇÃO NÃO CONCLUÍDA (código {rc}). Verifique o log acima. "
                    "É possível revisar as opções e tentar novamente após recuperar as montagens.")
                self.console_output.appendPlainText(f"\n[ERRO] INSTALAÇÃO INTERROMPIDA — código {rc}")
                QMessageBox.warning(self, "Instalação interrompida",
                                    f"O Bash terminou com código {rc}. A saída permanece na aba Instalação.")

        def reboot_after_success(self):
            if not self._installer_finished or self._installer_pty is not None or not self.console_finish.isVisible():
                return
            InstallFinishedDialog().reboot_now()
            # A ação ocorre apenas após o clique, sucesso verificado e Live detectada.

        def closeEvent(self, event):
            if self._installer_pty is not None and self._installer_pty.poll() is None:
                QMessageBox.warning(self, "Instalação ativa",
                                    "A instalação ainda está em execução. Aguarde o Bash terminar; "
                                    "fechar a janela agora deixaria a operação sem acompanhamento.")
                event.ignore()
                return
            event.accept()

        def refresh_disk(self):
            if hasattr(self, "partition_roles"):
                self.populate_roles()
            chosen = self.disk_combo.currentData()
            entry = next((x for x in self.disks if x["path"] == chosen), None)
            if entry is None:
                self.disk_detail.setPlainText("Selecione um disco para visualizar suas partições.")
                return
            lines = [f"Disco: {chosen} ({format_size(entry['size'])})", "Partições:"]
            for child in entry["partitions"]:
                lines.append(f"  {child['path']}   {format_size(child['size'])}  "
                             f"{child['fstype']}  {child['mountpoints']}")
            if not entry["partitions"]:
                lines.append("  nenhuma partição identificada")
            self.disk_detail.setPlainText("\n".join(lines))

        def update_preset(self):
            name = self.preset.currentText()
            if name in PRESETS:
                for key, check in self.checks.items():
                    check.blockSignals(True)
                    check.setChecked(key in PRESETS[name])
                    check.blockSignals(False)
            if hasattr(self, "summary"):
                self.refresh_summary()

        def mark_custom(self):
            if self.preset.currentText() != "Custom":
                self.preset.blockSignals(True)
                self.preset.setCurrentText("Custom")
                self.preset.blockSignals(False)

        def selected_stacks(self):
            return tuple(k for k, c in self.checks.items() if c.isChecked())

        def refresh_summary(self, *_):
            if not all(hasattr(self, name) for name in ("summary", "hostname", "username", "storage_mode", "checks")):
                return
            if not hasattr(self, "partition_roles"):
                return
            try:
                document = self.current_preview()
                summary = (wolf_discovery.render_plan(document) if document.get('schema') == wolf_discovery.SCHEMA
                           else wolf_plan.text_summary(document))
            except (ValueError, TypeError) as exc:
                summary = f"Erro de validação: {exc}"
            self.summary.setPlainText(summary)

        def open_backend_plan(self):
            # Somente o modo explicitamente não destrutivo --plan-only.
            preset = self.preset.currentText()
            selected = self.selected_stacks()
            selection = (["--preset", preset.lower()] if preset in PRESETS
                         else ["--stacks", ",".join(selected)] if selected
                         else ["--preset", "minimal"])
            answer = QMessageBox.question(
                self, "Verificar plano no terminal",
                "O planejador Bash fará perguntas novamente e não utilizará o disco marcado nesta GUI. "
                "Ele é independente e executará somente --plan-only. Continuar?",
            )
            if answer != QMessageBox.StandardButton.Yes:
                return
            self.run_command(["qterminal", "-e", "sudo", "wolf-install", "--plan-only", *selection])

    keyboard = KeyboardDialog()
    keyboard.exec()
    window = Window(keyboard.layouts.currentData())
    window.show()
    return app.exec()


def self_test() -> None:
    assert disk_inventory('{"blockdevices":[{"type":"loop","path":"/dev/loop0"},'
                          '{"type":"disk","path":"/dev/sda","size":10737418240,"model":"VM",'
                          '"children":[{"type":"part","path":"/dev/sda1","size":1073741824}]}]}')[0]["path"] == "/dev/sda"
    assert not disk_inventory("invalid")
    result = build_summary("/dev/sda", "erase", ("daily",), "wolf-linux", "wolf", {"/dev/sda"})
    assert "REVISÃO DAS ESCOLHAS" in result
    assert "escolhas validadas independentemente" in result
    for bad in ("; rm -rf /", "../../x"):
        try:
            build_summary(bad, "erase", (), "wolf-linux", "wolf", {"/dev/sda"})
        except ValueError:
            pass
        else:
            raise AssertionError("Disco não inventariado aceito")
    assert not launch(["/aplicativo-inexistente-wolf"])[0]
    assert keyboard_command("br", "abnt2") == ["setxkbmap", "-model", "abnt2", "-layout", "br", "-option", ""]
    assert keyboard_command("br", "abnt2", "thinkpad") == [
        "setxkbmap", "-model", "abnt2", "-layout", "br", "-variant", "thinkpad", "-option", ""]
    for invalid in (("br; rm -rf /", "abnt2", ""), ("br", "abnt2", "not-a-variant"),
                    ("us", "pc105", "thinkpad")):
        try:
            keyboard_command(*invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Layout/variante não autorizado aceito")
    assert "TODOS os arquivos" in format_intent_warning("root", "in-root", "/dev/vda2")
    assert "/home" in format_intent_warning("root", "in-root", "/dev/vda2")
    assert "carregadores" in format_intent_warning("esp", "in-root", "/dev/vda1")
    assert "pessoais" in format_intent_warning("home", "separate", "/dev/vda3")
    print("[OK] Wolf GUI 1.8: BIOS/MBR, PTY, Chromium/Bluetooth, Rescue e dispositivos UDisks2")


def main() -> int:
    parser = argparse.ArgumentParser(description="Wolf Installer GUI — planejamento e instalação em VM")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    return qt_main()


if __name__ == "__main__":
    raise SystemExit(main())
