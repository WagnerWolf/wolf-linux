#!/usr/bin/env python3
"""Wolf Installer GUI 0.9 — instalação VM com confirmação e tela de conclusão.

Execução real somente em VM descartável, via backend Bash, após confirmação
dupla do disco. Reutilização segue em simulação; manual UEFI está em piloto restrito a VM.
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
import wolf_plan

VERSION = "0.9"
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
        "reuse": "Reutilizar partições (dispositivos ainda precisam ser escolhidos no backend)",
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
        return (f"Você está marcando a intenção de FORMATAR a raiz /: {selected}.\n\n"
                "Formatar essa partição remove TODOS os arquivos atualmente armazenados nela.\n"
                f"{home_risk}\n\n"
                "No modo Reutilizar, o instalador Bash atual formata a raiz como ext4; "
                "desmarcar esta opção não habilita uma instalação sem formatação.\n\n"
                "No modo MANUAL VM a raiz / SERÁ FORMATADA após nova validação e confirmação; "
                "em REUTILIZAR, a execução está bloqueada.\n\n"
                "Deseja manter essa seleção de formatação?")
    if role == "esp":
        return (f"Você está marcando a intenção de FORMATAR a EFI: {selected}.\n\n"
                "Isso pode apagar carregadores de boot de Linux, Windows e outros sistemas. "
                "O instalador Bash em reutilização preserva a EFI; esta escolha "
                "não é compatível com a execução atual.\n\n"
                "Formatação da EFI não está habilitada na instalação gráfica. "
                "Manter esta opção apenas na revisão/simulação?")
    if role == "home":
        return (f"Você está marcando a intenção de FORMATAR /home: {selected}.\n\n"
                "Isso apagaria os arquivos pessoais da partição /home dedicada. "
                "O instalador Bash atual não oferece essa formatação em reutilização.\n\n"
                "Formatação de /home separada não está habilitada na instalação gráfica. "
                "Manter esta opção apenas na revisão/simulação?")
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
    from PySide6.QtCore import QTimer
    from PySide6.QtGui import QTextOption
    from PySide6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QFormLayout,
        QLabel, QPushButton, QFrame, QMessageBox, QTabWidget, QComboBox, QLineEdit,
        QPlainTextEdit, QCheckBox, QScrollArea, QDialog, QDialogButtonBox,
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
                "no MANUAL, apenas a raiz / será formatada.\n\n"
                "Use SOMENTE uma VM DESCARTÁVEL. O Bash fará outra validação e confirmação."
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
            self.accept_button.setText("Abrir terminal de instalação")
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
            self.setWindowTitle("Wolf Linux — Installer GUI 0.9 — VM experimental")
            self.resize(1040, 750)
            self.setMinimumSize(740, 520)
            self.disks = disk_inventory()
            self._vm_result_path = None
            self._vm_result_poll = QTimer(self)
            self._vm_result_poll.setInterval(700)
            self._vm_result_poll.timeout.connect(self.check_vm_install_result)
            wrapper = QWidget()
            layout = QVBoxLayout(wrapper)
            layout.setContentsMargins(20, 18, 20, 18)
            headline = QLabel("WOLF LINUX 2.0   /   INSTALADOR GRÁFICO")
            headline.setStyleSheet("font-size:19pt;font-weight:700;color:#ffffff")
            layout.addWidget(headline)
            warning = QLabel("EXECUÇÃO EXPERIMENTAL EXCLUSIVA DE VM QEMU/KVM: "
                             "Apagar disco inteiro (inclusive partições existentes) ou Manual UEFI "
                             "com raiz formatada e EFI preservada. Reutilizar continua em simulação. "
                             "A instalação exige confirmação. GParted é uma ferramenta independente.")
            warning.setWordWrap(True)
            warning.setStyleSheet("color:#ffcf91;border:1px solid #766039;padding:10px")
            layout.addWidget(warning)
            tabs = QTabWidget()
            layout.addWidget(tabs, 1)

            home = QWidget()
            hv = QVBoxLayout(home)
            for key, val in detect_hardware().items():
                label = QLabel(f"{key}: {val}")
                label.setWordWrap(True)
                hv.addWidget(label)
            hv.addWidget(QLabel("Ambiente Live: terminal, PCManFM-Qt e GParted disponíveis."))
            wifi_help = QLabel("Wi-Fi: clique no ícone de rede no canto superior direito para escolher a rede e informar a senha. O botão de redes também abre as configurações avançadas.")
            wifi_help.setWordWrap(True)
            hv.addWidget(wifi_help)
            for title, argv in (
                ("Abrir terminal", ["qterminal"]),
                ("Gerenciador de arquivos", ["pcmanfm-qt"]),
                ("GParted — Particionador", ["wolf-live-gparted"]),
                ("Configurar Wi-Fi / redes", ["wolf-live-network"]),
                ("Diagnóstico", ["qterminal", "-e", "wolf-live-diagnostics"]),
            ):
                btn = QPushButton(title)
                btn.clicked.connect(lambda checked=False, args=argv: self.run_command(args))
                hv.addWidget(btn)
            kb_btn = QPushButton("Alterar layout do teclado")
            kb_btn.clicked.connect(self.change_keyboard)
            hv.addWidget(kb_btn)
            hv.addStretch()
            tabs.addTab(self.scrollable(home), "Bem-vindo")

            storage = QWidget()
            sv = QVBoxLayout(storage)
            sv.addWidget(QLabel("Inventário de dispositivos (leitura apenas) — confirme também pelo lsblk no terminal."))
            self.disk_combo = QComboBox()
            self.disk_combo.addItem("Selecione um disco", "")
            for disk in self.disks:
                self.disk_combo.addItem(
                    f"{disk['path']} — {format_size(disk['size'])} — {disk['model']}" +
                    (" [REMOVÍVEL]" if disk['removable'] else ""), disk["path"])
            self.disk_combo.currentIndexChanged.connect(self.refresh_disk)
            self.disk_combo.currentIndexChanged.connect(self.refresh_summary)
            sv.addWidget(self.disk_combo)
            self.disk_detail = QPlainTextEdit()
            self.disk_detail.setReadOnly(True)
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
            refresh_btn = QPushButton("Atualizar lista de discos")
            refresh_btn.clicked.connect(self.reload_disks)
            sv.addWidget(refresh_btn)
            part_tool = QPushButton("Abrir GParted — Particionador (ferramenta independente)")
            part_tool.clicked.connect(lambda: self.run_command(["wolf-live-gparted"]))
            sv.addWidget(part_tool)
            advanced_info = QLabel(
                "APAGAR DISCO: remove tudo e cria EFI FAT32 (UEFI) + raiz ext4; /home será um DIRETÓRIO da raiz. "
                "MANUAL VM/UEFI: crie as partições no GParted, atualize a lista e atribua / e /boot/efi "
                "abaixo; a execução formata a raiz e PRESERVA EFI e /home separada. "
                "REUTILIZAR: ainda somente revisão e simulação. "
                "O GParted pode alterar o disco quando você confirma operações nele.")
            advanced_info.setWordWrap(True)
            sv.addWidget(advanced_info)
            guide = QLabel(
                "PARTIÇÕES NECESSÁRIAS (UEFI): EFI (ESP) FAT32 com flag GPT esp/boot, 512 MiB a 1 GiB, para os arquivos de boot; "
                "raiz / ext4, mínimo 20 GiB (recomendado 40 GiB ou mais), contendo o sistema. "
                "Opcional: /home separada ext4 para arquivos pessoais; o restante do espaço pode ser dedicado a ela. "
                "Em BIOS/Legacy não há ESP obrigatória, mas o modo manual gráfico BIOS ainda não está liberado."
            )
            guide.setWordWrap(True)
            guide.setStyleSheet("color:#c8d9ea;border:1px solid #344356;padding:10px")
            sv.addWidget(guide)
            sv.addWidget(QLabel("Defina o papel de cada partição (/) é o sistema; /home é OPCIONAL):"))
            self.home_layout = QComboBox()
            self.home_layout.addItem("/home dentro da partição raiz / (sem partição dedicada)", "in-root")
            self.home_layout.addItem("/home em partição dedicada", "separate")
            self.home_layout.currentIndexChanged.connect(self.update_storage_controls)
            self.home_layout.currentIndexChanged.connect(self.refresh_summary)
            sv.addWidget(self.home_layout)
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
                "IMPORTANTE: no modo MANUAL VM, o instalador formata a raiz / em ext4, "
                "preserva a EFI FAT32 e /home dedicada. No modo REUTILIZAR, "
                "a instalação permanece BLOQUEADA nesta revisão.")
            compatibility_note.setWordWrap(True)
            compatibility_note.setStyleSheet("color:#ffcf91;border:1px solid #766039;padding:9px")
            sv.addWidget(compatibility_note)
            tabs.addTab(self.scrollable(storage), "Discos e partições")

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
            tabs.addTab(self.scrollable(profile), "Perfis e usuário")

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
            vm_trial = QPushButton("Instalar nesta VM (APAGAR disco / Manual UEFI)")
            self.vm_install_button = vm_trial
            vm_trial.setStyleSheet("background:#5d2832;color:white;border:2px solid #be6570;padding:12px;")
            vm_trial.clicked.connect(self.execute_vm_install)
            rv.addWidget(vm_trial)
            rv.addWidget(simulation)
            legacy = QPushButton("Abrir planejamento CLI tradicional (independente)")
            legacy.clicked.connect(self.open_backend_plan)
            rv.addWidget(legacy)
            review_note = QLabel(
                "Revisar e Simular NÃO alteram discos. Instalar em VM executa SOMENTE "
                "Apagar disco inteiro ou Manual UEFI com partições explicitamente selecionadas. "
                "Reutilizar continua bloqueado para execução. "
                "O plano JSON não autoriza instalação sozinho.")
            review_note.setWordWrap(True)
            rv.addWidget(review_note)
            tabs.addTab(self.scrollable(review), "Revisar pré-plano")
            self.setCentralWidget(wrapper)
            self.populate_roles()
            self.update_storage_controls()
            self.refresh_disk()
            self.refresh_summary()

        @staticmethod
        def scrollable(content):
            area = QScrollArea()
            area.setWidgetResizable(True)
            area.setWidget(content)
            return area

        def run_command(self, argv):
            ok, msg = launch(argv)
            if not ok:
                QMessageBox.warning(self, "Wolf Live", msg)

        def reload_disks(self):
            self.disks = disk_inventory()
            self.disk_combo.blockSignals(True)
            self.disk_combo.clear()
            self.disk_combo.addItem("Selecione um disco", "")
            for d in self.disks:
                self.disk_combo.addItem(f"{d['path']} — {format_size(d['size'])} — {d['model']}", d["path"])
            self.disk_combo.blockSignals(False)
            self.refresh_disk()
            self.refresh_summary()

        def update_storage_controls(self, *_):
            enabled = self.storage_mode.currentData() != "erase"
            separate = enabled and self.home_layout.currentData() == "separate"
            self.home_layout.setEnabled(enabled)
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
                widget.setEnabled(enabled and (role != "home" or separate))
            if self.storage_mode.currentData() == "manual":
                for name in ("esp", "home"):
                    widget = self.partition_format[name]
                    widget.blockSignals(True)
                    widget.setChecked(False)
                    widget.blockSignals(False)
            for role, widget in self.partition_format.items():
                # Manual VM: não permitir marcar formatação de ESP ou /home.
                widget.setEnabled(enabled and (role != "home" or separate)
                                  and (self.storage_mode.currentData() != "manual" or role == "root"))
            if hasattr(self, "vm_install_button"):
                current_mode = self.storage_mode.currentData()
                self.vm_install_button.setEnabled(current_mode != "reuse")
                self.vm_install_button.setText({
                    "erase": "Instalar nesta VM — APAGAR TODO O DISCO",
                    "manual": "Instalar nesta VM — MANUAL UEFI (formatar raiz /)",
                    "reuse": "Reutilizar partições — execução ainda não liberada",
                }[current_mode])
            self.update_format_notice()
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
                        "Escolha a partição antes de marcar a intenção de formatação.")
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
                    "O modo MANUAL VM pode formatar somente a raiz / após confirmação; "
                    "a opção REUTILIZAR não executa instalações nesta revisão.")
                self.format_notice.show()
            else:
                self.format_notice.hide()

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

        def current_preview(self):
            preset = self.preset.currentText().lower()
            mode = self.storage_mode.currentData()
            roles = {k: c.currentData() for k, c in self.partition_roles.items()}
            formats = {k: c.isChecked() for k, c in self.partition_format.items()}
            home_layout = self.home_layout.currentData() if mode != "erase" else "in-root"
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

        def execute_vm_install(self):
            if self._vm_result_path is not None:
                QMessageBox.warning(self, "Instalação em andamento",
                                    "Aguarde a conclusão da instalação VM anterior.")
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
                QMessageBox.warning(self, "Instalação VM BLOQUEADA", str(exc))
                return
            disk = doc["storage"]["disk"]["path"]
            # Uma QMessageBox simples não foi percebida na VM alpha26.
            # Diálogo MODAL com digitação exata torna a confirmação verificável.
            if doc["storage"]["mode"] == "manual":
                root_part = doc["storage"]["partitions"]["root"]
                esp_part = doc["storage"]["partitions"]["esp"]
                home_part = doc["storage"]["partitions"]["home"]
                description = (f"INSTALAÇÃO MANUAL NA VM {disk}\n\n"
                               f"FORMATAR (APAGAR DADOS): raiz / = {root_part}\n"
                               f"PRESERVAR: EFI = {esp_part}\n"
                               f"PRESERVAR: /home = {home_part or 'dentro da raiz'}\n\n"
                               "Apenas a raiz será formatada pelo instalador.\n"
                               "O GParted não é acionado automaticamente.")
                if QMessageBox.warning(self, "Confirme as partições manuais", description,
                                       QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel,
                                       QMessageBox.StandardButton.Cancel) != QMessageBox.StandardButton.Yes:
                    return
            if VmEraseConsentDialog(self, disk).exec() != QDialog.DialogCode.Accepted:
                return
            # Cada execução usa um sinalizador privado, inicialmente VAZIO.
            # Somente o wrapper, após o término do Bash, escreve success/failed.
            try:
                status_dir = Path.home() / ".local/state/wolf-linux/live-installer"
                status_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
                fd, name = tempfile.mkstemp(prefix="vm-install-", suffix=".status",
                                            dir=str(status_dir))
                os.close(fd)
                status_path = Path(name)
            except OSError as exc:
                QMessageBox.warning(self, "Falha no acompanhamento", str(exc))
                return
            ok, error = launch(["qterminal", "-e", "wolf-live-execute-vm-plan",
                                str(plan_file), str(status_path)])
            if not ok:
                status_path.unlink(missing_ok=True)
                QMessageBox.warning(self, "Falha ao abrir terminal", error)
                return
            self._vm_result_path = status_path
            self._vm_result_poll.start()

        def check_vm_install_result(self):
            status_path = self._vm_result_path
            if status_path is None:
                return
            try:
                status = status_path.read_text(encoding="utf-8").strip()
            except OSError:
                return  # O instalador ainda não finalizou ou arquivo transitório.
            if not status:
                return
            if status != "success" and not re.fullmatch(r"failed [1-9][0-9]*", status):
                return  # Não interpretar mensagens inesperadas como sucesso.
            self._vm_result_poll.stop()
            self._vm_result_path = None
            status_path.unlink(missing_ok=True)
            if status == "success":
                # O terminal já terminou; a GUI original é encerrada depois
                # desta única decisão, independentemente da opção escolhida.
                self.hide()
                InstallFinishedDialog().exec()
                self.close()
            else:
                QMessageBox.warning(
                    self, "Instalação não concluída",
                    f"O instalador retornou código {status.split()[1]}.\n"
                    "Nenhuma mensagem de sucesso foi emitida. "
                    "Consulte o terminal e os logs antes de tentar novamente."
                )

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
                summary = wolf_plan.text_summary(self.current_preview())
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
    print("[OK] Wolf GUI 0.9: consentimento, revisão e conclusão monitorada")


def main() -> int:
    parser = argparse.ArgumentParser(description="Wolf Installer GUI — pré-planejamento")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    return qt_main()


if __name__ == "__main__":
    raise SystemExit(main())
