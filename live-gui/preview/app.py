#!/usr/bin/env python3
"""Wolf Installer — interface principal do instalador Wolf Linux.

Somente o executor independente, após validação, pode realizar operações de disco.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import subprocess
import os
import tempfile
from pathlib import Path

from PySide6.QtCore import Qt, QEvent, QProcess, QTimer, QSocketNotifier
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QFormLayout,
    QLabel, QPushButton, QFrame, QRadioButton, QButtonGroup, QComboBox,
    QCheckBox, QStackedWidget, QScrollArea, QGroupBox, QSpinBox, QSlider,
    QTableWidget, QTableWidgetItem, QHeaderView, QAbstractItemView,
    QMessageBox, QDialog, QPlainTextEdit, QFileDialog, QSizePolicy, QLineEdit,
)
from planner import (Choices, Inventory, PreviewError, detect_inventory,
                     demo_inventory, describe_device, human_size, erase_budget, erase_allocation,
                     preview_dotfiles, safe_export, validate_plan)
from vm_bridge import build_vm_plan, check_vm_plan, BridgeError

# Mesmo motor PTY usado no instalador clássico: o Bash não roda na thread Qt.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from terminal_engine import InstallerPty

BASE = Path(__file__).resolve().parent
STYLE = """
QWidget { background: #0e1521; color: #e5ebf4; font-family: 'Noto Sans', 'DejaVu Sans', sans-serif; font-size: 10pt; }
QLabel { background: transparent; }
QLabel#heading { font-size: 20pt; font-weight: 700; color: #f5f8fd; }
QLabel#section { font-size: 15pt; font-weight: 650; color: #eaf1ff; }
QLabel#muted { color: #9dacc3; }
QLabel#warning { background: #352819; border: 1px solid #9e7141; padding: 11px; border-radius: 8px; color: #ffddae; }
QLabel#info { background: #1c2e41; border: 1px solid #385875; padding: 11px; border-radius: 8px; color: #cce8ff; }
QLabel#success { background: #17342f; border: 1px solid #337b6c; padding: 11px; border-radius: 8px; color: #c2fae5; }
QFrame#card, QGroupBox { background: #192434; border: 1px solid #344358; border-radius: 10px; }
QGroupBox { padding: 18px 13px 13px; margin-top: 12px; font-weight: bold; }
QGroupBox::title { subcontrol-origin: margin; subcontrol-position: top left; left: 13px; padding: 0 6px; }
QRadioButton { padding: 9px 10px; border: 1px solid #33465d; border-radius: 9px; background: #1c2839; font-weight: 600; }
QRadioButton:checked { background: #26405b; border: 2px solid #6da9ef; }
QRadioButton::indicator { width: 17px; height: 17px; }
QComboBox, QSpinBox, QPlainTextEdit { background: #111d2d; border: 1px solid #475a74; padding: 9px; border-radius: 7px; min-height: 23px; }
QComboBox::drop-down { border: none; width: 24px; }
QComboBox QAbstractItemView { background: #182638; color: #ecf3fc; selection-background-color: #365875; }
QCheckBox { padding: 5px 0; spacing: 10px; }
QCheckBox::indicator { width: 18px; height: 18px; }
QPushButton { background: #26364c; border: 1px solid #435e7c; border-radius: 8px; padding: 10px 16px; font-weight: 600; }
QPushButton:hover { background: #344965; }
QPushButton:disabled { background: #182230; color: #677b90; border-color: #293647; }
QPushButton#primary { background: #2565a8; border-color: #448bd2; color: white; }
QPushButton#primary:hover { background: #307bc7; }
QPushButton#danger { background: #7d3837; border-color: #ad6664; color: white; }
QPushButton#danger:hover { background: #9a4141; }
QTableWidget { background: #152130; alternate-background-color: #1c2b3c; gridline-color: #314056; border: 1px solid #364b65; border-radius: 7px; }
QTableWidget::item { padding: 5px; }
QHeaderView::section { background: #253a54; padding: 9px; border: none; border-right: 1px solid #3d5370; font-weight: 600; }
QScrollArea { border: none; }
QSlider::groove:horizontal { height: 7px; border-radius: 3px; background: #374f6c; }
QSlider::sub-page:horizontal { background: #4e93d3; border-radius: 3px; }
QSlider::handle:horizontal { background: #a9d2fb; width: 17px; margin: -6px 0; border-radius: 8px; }

"""


def text_label(text: str, *, name: str = 'muted', wrap: bool = True) -> QLabel:
    w = QLabel(text)
    w.setObjectName(name)
    w.setWordWrap(wrap)
    w.setMinimumWidth(0)
    w.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred)
    w.setTextFormat(Qt.TextFormat.PlainText)
    return w


def section(text: str) -> QLabel:
    return text_label(text, name='section')


def vertical(gap=12) -> QVBoxLayout:
    layout = QVBoxLayout()
    layout.setSpacing(gap)
    return layout


def button(text: str, handler, *, style: str | None = None) -> QPushButton:
    btn = QPushButton(text)
    if style:
        btn.setObjectName(style)
    btn.clicked.connect(handler)
    return btn


def make_scroll(content: QWidget) -> QScrollArea:
    area = QScrollArea()
    area.setWidgetResizable(True)
    area.setWidget(content)
    return area


def make_combo() -> QComboBox:
    combo = QComboBox()
    combo.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToMinimumContentsLengthWithIcon)
    combo.setMinimumContentsLength(12)
    combo.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Fixed)
    return combo


# Comandos fixos; nunca recebem caminho, dispositivo ou entrada livre do usuário.
# São os mesmos atalhos utilizados na sessão Live quando disponíveis.
UTILITIES = (
    ('terminal', 'Terminal', (('qterminal',), ('konsole',), ('xfce4-terminal',))),
    ('files', 'Arquivos e dispositivos', (('pcmanfm-qt',), ('dolphin',), ('thunar',))),
    ('browser', 'Chromium', (('wolf-live-browser',), ('chromium',))),
    ('bluetooth', 'Bluetooth', (('blueman-manager',),)),
    ('rescue', 'Wolf Rescue', (('wolf-live-rescue',),)),
    ('wifi', 'Redes Wi-Fi', (('wolf-live-network',), ('nm-connection-editor',))),
    ('time', 'Relógio e sincronização', (('qterminal', '-e', 'wolf-live-time-status'),)),
    ('diag', 'Diagnóstico', (('qterminal', '-e', 'wolf-live-diagnostics'),)),
    ('topology', 'Topologia de armazenamento', (('qterminal', '-e', 'sudo', 'wolf-live-storage-topology'),)),
    ('gparted', 'GParted — Particionador', (('wolf-live-gparted',), ('gparted',))),
)


def utility_command(key: str) -> tuple[str, ...] | None:
    for tool_key, _label, commands in UTILITIES:
        if tool_key == key:
            for args in commands:
                if shutil.which(args[0]) and all(
                    shutil.which(arg) for arg in args[1:] if arg.startswith('wolf-live-')
                ):
                    return args
            return None
    return None


class ConfirmDialog(QDialog):
    """Duplo consentimento somente por cliques, nunca por digitação."""
    def __init__(self, parent: QWidget, *, final: bool, description: str):
        super().__init__(parent)
        self.setWindowTitle('Confirmação final' if final else 'Confirmar alterações')
        screen = QApplication.primaryScreen()
        available = screen.availableGeometry() if screen else None
        self.resize(min(690, max(490, available.width()-55)) if available else 690,
                    min(540 if final else 480, max(400, available.height()-65)) if available else 500)
        self.setMinimumSize(470, 375)
        root = vertical(15)
        root.setContentsMargins(22, 22, 22, 20)
        self.setLayout(root)
        title = section('Tem certeza? Esta operação é irreversível.' if final
                        else 'Você deseja continuar com estas alterações?')
        root.addWidget(title)
        root.addWidget(text_label('Revise exatamente o que será apagado, criado e preservado.'
                                  if final else 'O resumo abaixo mostra os efeitos esperados da instalação.', name='warning' if final else 'info'))
        output = QPlainTextEdit()
        output.setReadOnly(True)
        output.setPlainText(description)
        root.addWidget(output, 1)
        if final:
            root.addWidget(text_label('Ao confirmar, operações REAIS e IRREVERSÍVEIS serão realizadas nos dispositivos identificados.', name='warning'))
        controls = QHBoxLayout()
        controls.addStretch()
        no = button('Não, voltar', self.reject)
        controls.addWidget(no)
        yes = button('Sim, confirmar' if final else 'Sim, continuar', self.accept, style='danger' if final else 'primary')
        controls.addWidget(yes)
        root.addLayout(controls)
        no.setDefault(True)
        no.setFocus()


KEYBOARD_LAYOUTS = (
    ('Português (Brasil) — ABNT2', 'br', 'abnt2', ''),
    ('Português (Brasil) — ThinkPad', 'br', 'abnt2', 'thinkpad'),
    ('English (US)', 'us', 'pc105', ''),
    ('Português (Portugal)', 'pt', 'pc105', ''),
    ('Español', 'es', 'pc105', ''),
    ('Français', 'fr', 'pc105', ''),
    ('Deutsch', 'de', 'pc105', ''),
    ('Italiano', 'it', 'pc105', ''),
)

class KeyboardDialog(QDialog):
    def __init__(self, parent, current):
        super().__init__(parent)
        self.setWindowTitle('Configurar teclado')
        self.resize(510, 275)
        layout = vertical(9)
        self.setLayout(layout)
        layout.addWidget(section('Layout do teclado'))
        layout.addWidget(text_label('Escolha o teclado da sessão Live e do sistema que será instalado.'))
        self.combo = make_combo()
        for title, lang, model, variant in KEYBOARD_LAYOUTS:
            self.combo.addItem(title, (lang, model, variant))
        index = self.combo.findData(current)
        if index >= 0:
            self.combo.setCurrentIndex(index)
        layout.addWidget(self.combo)
        self.test = QLineEdit()
        self.test.setPlaceholderText('Teste o teclado aqui: ç á / ? @')
        layout.addWidget(self.test)
        self.feedback = text_label('')
        layout.addWidget(self.feedback)
        self.combo.currentIndexChanged.connect(self.apply_layout)
        self.apply_layout()
        row = QHBoxLayout()
        row.addWidget(button('Cancelar', self.reject))
        row.addWidget(button('Aplicar', self.accept, style='primary'))
        layout.addLayout(row)

    def apply_layout(self, *_):
        lang, model, variant = self.combo.currentData()
        cmd = ['setxkbmap', '-model', model, '-layout', lang]
        if variant:
            cmd += ['-variant', variant]
        cmd += ['-option', '']
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            self.feedback.setText('Layout aplicado à sessão.' if result.returncode == 0
                                  else 'Não foi possível aplicar nesta sessão: ' + result.stderr.strip()[:140])
        except (OSError, subprocess.TimeoutExpired):
            self.feedback.setText('O utilitário setxkbmap não está disponível nesta sessão.')
        self.test.clear()


class MainWindow(QMainWindow):
    def __init__(self, inventory: Inventory):
        super().__init__()
        self.inventory = inventory
        self.mode = None
        self.operations = []
        self.setWindowTitle('Wolf Linux | Instalador')
        self.keyboard = ('br', 'abnt2', '')
        self.username = 'wolf'
        self.hostname = 'wolf-linux'
        self.preset = None
        self.review_plan = None
        screen = QApplication.primaryScreen()
        available = screen.availableGeometry() if screen else None
        if available:
            self.resize(min(1210, max(750, available.width()-60)),
                        min(850, max(550, available.height()-70)))
        else:
            self.resize(1160, 760)
        self.setMinimumSize(750, 520)
        self._pty = None
        self._pty_notifier = None
        self._pty_timer = QTimer(self)
        self._pty_timer.timeout.connect(self.check_install_result)
        self._installer_log = None
        self.build_ui()
        self.populate_devices()
        self.config_stack.setCurrentIndex(3)  # nenhuma instalação pré-selecionada
        self.update_state()
        self.pages.setCurrentIndex(2)  # etapa inicial: teclado
        self.continue_button.hide()  # apenas o botão 'Avançar' do teclado fica visível
        QTimer.singleShot(0, self.apply_keyboard)  # aplicar ABNT2 mesmo sem alterar o combo
        self.status.setText('Etapa 1: selecione e teste o layout do teclado.')
        # Uma roda de mouse move sempre a página atual, mesmo quando está
        # sobre sliders, caixas numéricas, combos, tabelas e textos.
        QApplication.instance().installEventFilter(self)

    def build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        main = vertical(14)
        main.setContentsMargins(16, 12, 16, 10)
        central.setLayout(main)

        header = QHBoxLayout()
        labels = vertical(3)
        labels.addWidget(text_label('Wolf Linux', name='heading'))
        labels.addWidget(text_label('Instalador · escolha como usar seus discos'))
        header.addLayout(labels, 1)
        main.addLayout(header)

        self.pages = QStackedWidget()
        main.addWidget(self.pages, 1)
        self.build_choices_page()
        self.build_review_page()
        self.build_keyboard_page()
        self.build_terminal_page()

        footer = QHBoxLayout()
        self.status = text_label('Selecione o armazenamento. Operações reais exigem pré-validação e confirmação.')
        footer.addWidget(self.status, 1)
        self.back_button = button('← Voltar', self.return_to_choices)
        self.back_button.hide()
        footer.addWidget(self.back_button)
        self.continue_button = button('Revisar  →', self.go_review, style='primary')
        footer.addWidget(self.continue_button)
        main.addLayout(footer)

    def build_choices_page(self):
        page = QWidget()
        page_layout = QHBoxLayout(page)
        page_layout.setSpacing(12)
        page_layout.setContentsMargins(0, 5, 0, 4)
        self.pages.addWidget(page)

        left = QFrame()
        left.setObjectName('card')
        # Largura coerente com a resolução. Evita seleção comprimida e
        # barra de rolagem horizontal em 1024x768 e em janelas grandes.
        screen = self.screen() or QApplication.primaryScreen()
        width = screen.availableGeometry().width() if screen else 1150
        self.sidebar_width = min(330, max(255, int(width * 0.27)))
        left.setFixedWidth(self.sidebar_width)
        left.setSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Expanding)
        nav = vertical(7)
        nav.setContentsMargins(10, 10, 10, 10)
        # Na resolução da Live, mantenha a barra lateral rolável também.
        nav_content = QWidget()
        nav_content.setLayout(nav)
        nav_scroll = make_scroll(nav_content)
        self.nav_scroll = nav_scroll
        nav_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        nav_scroll.setMinimumWidth(0)
        nav_content.setMinimumWidth(0)
        side_layout = QVBoxLayout(left)
        side_layout.setContentsMargins(2, 2, 2, 2)
        side_layout.addWidget(nav_scroll)
        nav.addWidget(button('← 1. Layout de teclado', self.open_keyboard_step))
        nav.addWidget(section('2. Tipo de instalação'))
        nav.addWidget(text_label('Cada opção apresenta somente os controles necessários.'))
        self.radio_group = QButtonGroup(self)
        modes = [
            ('erase', 'Apagar disco inteiro', 'Instalação automática no disco escolhido. Todos os dados dele serão apagados.'),
            ('manual', 'Particionamento manual', 'Atribua os volumes de /, EFI e /home individualmente.'),
            ('reuse', 'Reutilizar partições', 'Formate apenas /; preserve EFI e /home existentes.'),
        ]
        self.mode_radios = {}
        for value, title, detail in modes:
            radio = QRadioButton(title)
            radio.setCursor(Qt.CursorShape.PointingHandCursor)
            radio.setToolTip(detail)
            radio.setMinimumHeight(40)
            radio.setSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Fixed)
            radio.toggled.connect(lambda active, m=value: self.mode_changed(m) if active else None)
            self.radio_group.addButton(radio)
            self.mode_radios[value] = radio
            nav.addWidget(radio)
            note = text_label(detail)
            note.setContentsMargins(7, 0, 0, 6)
            nav.addWidget(note)
        nav.addSpacing(6)
        nav.addWidget(section('3. Perfil de instalação — obrigatório'))
        nav.addWidget(text_label('Escolha quais programas instalar. A revisão ficará bloqueada até selecionar um perfil.', name='info'))
        self.preset_combo = make_combo()
        self.preset_combo.addItem('Escolha Minimal, Test ou Full...', None)
        self.preset_combo.addItem('Minimal — sistema básico', 'minimal')
        self.preset_combo.addItem('Test — apps principais', 'test')
        self.preset_combo.addItem('Full — todas as stacks', 'full')
        nav.addWidget(self.preset_combo)
        self.preset_combo.setObjectName('requiredProfile')
        self.preset_combo.currentIndexChanged.connect(self.update_state)
        self.space_help = text_label('Estimativas de espaço em / (GiB): Minimal 25–35; Test 40–60; Full 75–110. Varia conforme downloads e atualizações.', name='info')
        nav.addWidget(self.space_help)
        nav.addWidget(section('4. Identificação'))
        nav.addWidget(text_label('Nome de usuário'))
        self.user_input = QLineEdit('wolf')
        self.user_input.setMaxLength(32)
        self.user_input.textChanged.connect(self.update_state)
        self.user_input.editingFinished.connect(self.on_clean_changed)
        nav.addWidget(self.user_input)
        nav.addWidget(text_label('Nome do computador'))
        self.host_input = QLineEdit('wolf-linux')
        self.host_input.setMaxLength(63)
        self.host_input.textChanged.connect(self.update_state)
        nav.addWidget(self.host_input)
        self.keyboard_button = button('Alterar teclado ↗', self.change_keyboard)
        nav.addWidget(self.keyboard_button)
        nav.addWidget(text_label('Firmware detectado:'))
        self.firmware_label = text_label(self.inventory.firmware, name='info')
        nav.addWidget(self.firmware_label)
        nav.addWidget(button('Atualizar dispositivos', self.refresh_devices))
        nav.addWidget(button('Ferramentas auxiliares ↗', self.open_utilities))
        page_layout.addWidget(left)

        right = QFrame()
        right.setObjectName('card')
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(12, 12, 12, 12)
        right_layout.setSpacing(9)
        self.mode_title = section('Configuração do armazenamento')
        right_layout.addWidget(self.mode_title)
        self.mode_description = text_label('')
        right_layout.addWidget(self.mode_description)
        self.disk_space_advice = text_label('', name='info')
        right_layout.addWidget(self.disk_space_advice)
        self.config_stack = QStackedWidget()
        right_layout.addWidget(self.config_stack, 1)
        self.erase_page = self.build_erase_page()
        self.manual_page = self.build_manual_page()
        self.reuse_page = self.build_reuse_page()
        self.config_stack.addWidget(make_scroll(self.erase_page))
        self.config_stack.addWidget(make_scroll(self.manual_page))
        self.config_stack.addWidget(make_scroll(self.reuse_page))
        self.config_stack.addWidget(self.build_unselected_page())
        self.validation_label = text_label('', name='warning')
        right_layout.addWidget(self.validation_label)
        page_layout.addWidget(right, 1)

    def inner_page(self):
        page = QWidget()
        layout = vertical(14)
        layout.setContentsMargins(5, 7, 7, 12)
        page.setLayout(layout)
        return page, layout

    def build_erase_page(self):
        page, v = self.inner_page()
        v.addWidget(text_label('Unidade de destino', name='section'))
        self.erase_disk = make_combo()
        self.erase_disk.currentIndexChanged.connect(self.on_erase_disk_change)
        v.addWidget(self.erase_disk)
        v.addWidget(text_label('A unidade selecionada será reparticionada por completo. Nenhuma partição atual será mantida.', name='warning'))
        self.erase_capacity = text_label('Selecione um disco para calcular o espaço disponível.', name='info')
        v.addWidget(self.erase_capacity)
        v.addWidget(section('Organização automática'))
        self.erase_home = make_combo()
        self.erase_home.addItem('/home dentro da raiz / (mais simples)', False)
        self.erase_home.addItem('Criar partição /home separada', True)
        self.erase_home.currentIndexChanged.connect(self.on_erase_home_change)
        v.addWidget(self.erase_home)

        self.erase_root_group = QGroupBox('Espaço para a partição raiz (/)')
        group_layout = vertical(9)
        self.erase_root_group.setLayout(group_layout)
        group_layout.addWidget(text_label('Digite o tamanho em GiB ou arraste o controle. Mínimo: 25 GiB.'))
        root_row = QHBoxLayout()
        self.erase_root_slider = QSlider(Qt.Orientation.Horizontal)
        self.erase_root_slider.setRange(25, 60)
        self.erase_root_slider.setValue(60)
        self.erase_root_slider.valueChanged.connect(self.erase_root_from_slider)
        root_row.addWidget(self.erase_root_slider, 1)
        self.erase_root = QSpinBox()
        self.erase_root.setRange(25, 60)
        self.erase_root.setValue(60)
        self.erase_root.setSuffix(' GiB')
        self.erase_root.setMinimumWidth(130)
        self.erase_root.valueChanged.connect(self.erase_root_from_spin)
        root_row.addWidget(self.erase_root)
        group_layout.addLayout(root_row)
        self.erase_root_remaining = text_label('')
        group_layout.addWidget(self.erase_root_remaining)
        v.addWidget(self.erase_root_group)

        self.erase_home_group = QGroupBox('Espaço para /home separada')
        home_layout = vertical(9)
        self.erase_home_group.setLayout(home_layout)
        self.erase_auto_home = QCheckBox('Usar todo o espaço restante para /home')
        self.erase_auto_home.setChecked(True)
        self.erase_auto_home.toggled.connect(self.update_state)
        home_layout.addWidget(self.erase_auto_home)
        home_row = QHBoxLayout()
        self.erase_home_slider = QSlider(Qt.Orientation.Horizontal)
        self.erase_home_slider.setRange(10, 10)
        self.erase_home_slider.valueChanged.connect(self.erase_home_from_slider)
        home_row.addWidget(self.erase_home_slider, 1)
        self.erase_home_size = QSpinBox()
        self.erase_home_size.setRange(10, 10)
        self.erase_home_size.setSuffix(' GiB')
        self.erase_home_size.setMinimumWidth(130)
        self.erase_home_size.valueChanged.connect(self.erase_home_from_spin)
        home_row.addWidget(self.erase_home_size)
        home_layout.addLayout(home_row)
        self.erase_home_remaining = text_label('')
        home_layout.addWidget(self.erase_home_remaining)
        v.addWidget(self.erase_home_group)

        self.erase_budget_summary = text_label('', name='info')
        v.addWidget(self.erase_budget_summary)
        self.erase_boot_notice = text_label('', name='muted')
        v.addWidget(self.erase_boot_notice)
        self.erase_partitions = QTableWidget(0, 3)
        self.erase_partitions.setHorizontalHeaderLabels(['Volume atual', 'Tamanho', 'Sistema de arquivos'])
        self.erase_partitions.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.erase_partitions.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        self.erase_partitions.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        self.erase_partitions.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.erase_partitions.setSelectionMode(QAbstractItemView.SelectionMode.NoSelection)
        self.erase_partitions.setMinimumHeight(118)
        self.erase_partitions.setMaximumHeight(195)
        v.addWidget(text_label('Partições e volumes existentes na unidade (somente visualização):'))
        v.addWidget(self.erase_partitions)
        v.addStretch()
        return page

    @staticmethod
    def set_numeric(widget, minimum: int, maximum: int, value: int):
        widget.blockSignals(True)
        widget.setRange(minimum, max(minimum, maximum))
        widget.setValue(max(minimum, min(value, max(minimum, maximum))))
        widget.blockSignals(False)

    def on_erase_disk_change(self, *_):
        try:
            budget = erase_budget(self.inventory, self.erase_disk.currentData() or '')
        except PreviewError:
            self.update_state()
            return
        if self.erase_home.currentData():
            target = min(60, budget.usable_gib - 10)
        else:
            target = budget.usable_gib
        self.set_numeric(self.erase_root, 25, max(25, target), target)
        self.update_state()

    def erase_root_from_slider(self, val):
        self.erase_root.setValue(val)
        self.update_state()

    def erase_root_from_spin(self, val):
        self.erase_root_slider.setValue(val)
        self.update_state()

    def erase_home_from_slider(self, val):
        self.erase_home_size.setValue(val)
        self.update_state()

    def erase_home_from_spin(self, val):
        self.erase_home_slider.setValue(val)
        self.update_state()

    def update_erase_budget(self):
        try:
            budget = erase_budget(self.inventory, self.erase_disk.currentData() or '')
        except PreviewError:
            self.erase_capacity.setText('Selecione um disco para calcular o espaço disponível.')
            self.erase_home_group.setVisible(bool(self.erase_home.currentData()))
            self.erase_budget_summary.setText('')
            self.erase_root_remaining.setText('')
            self.erase_home_remaining.setText('')
            return
        separate = bool(self.erase_home.currentData())
        upper_root = max(25, budget.usable_gib - (10 if separate else 0))
        root = min(self.erase_root.value(), upper_root)
        self.set_numeric(self.erase_root, 25, upper_root, root)
        self.set_numeric(self.erase_root_slider, 25, upper_root, root)
        self.erase_home_group.setVisible(separate)
        remainder = budget.usable_gib - root
        if separate:
            size = remainder if self.erase_auto_home.isChecked() else min(self.erase_home_size.value(), remainder)
            self.set_numeric(self.erase_home_size, 10, max(10, remainder), max(10, size))
            self.set_numeric(self.erase_home_slider, 10, max(10, remainder), max(10, size))
            editable = not self.erase_auto_home.isChecked()
            self.erase_home_size.setEnabled(editable)
            self.erase_home_slider.setEnabled(editable)
            self.erase_home_remaining.setText(f'Etapa /home: {remainder} GiB restantes após a raiz; '
                                              f'{max(0, remainder - size)} GiB não alocados.')
            unallocated = max(0, remainder - size)
            home_str = f'   |   /home: {size} GiB'
        else:
            self.erase_home_remaining.setText('')
            unallocated = max(0, remainder)
            home_str = '   |   /home integrada'
        self.erase_capacity.setText(f'Disco: {budget.disk_gib} GiB   •   Reservado para boot: '
                                    f'{budget.boot_gib} GiB   •   Margem: {budget.margin_gib} GiB   •   '
                                    f'Utilizável: {budget.usable_gib} GiB')
        self.erase_root_remaining.setText(f'Etapa raiz: {budget.usable_gib} GiB disponíveis inicialmente; '
                                          f'{remainder} GiB restantes depois de reservar /.')
        self.erase_budget_summary.setText(f'/ : {root} GiB{home_str}   |   '
                                          f'Sem alocação: {unallocated} GiB')

    def role_combo(self, layout: QVBoxLayout, label: str, callback):
        layout.addWidget(text_label(label, name='muted'))
        combo = make_combo()
        combo.currentIndexChanged.connect(callback)
        layout.addWidget(combo)
        return combo

    def build_manual_page(self):
        page, v = self.inner_page()
        v.addWidget(button('Abrir GParted ↗', lambda: self.launch_utility('gparted')))
        v.addWidget(text_label('Escolha os volumes para cada função. Neste modo, selecione partições de um mesmo disco. LVM multidisco requer o instalador especializado.', name='info'))
        rootbox = QGroupBox('Sistema operacional')
        rl = vertical(6)
        rootbox.setLayout(rl)
        self.manual_root = self.role_combo(rl, 'Raiz / (obrigatória; será formatada em ext4)', self.update_state)
        rl.addWidget(text_label('A nova instalação substituirá o conteúdo da raiz selecionada.'))
        v.addWidget(rootbox)
        self.manual_efi_group = QGroupBox('Inicialização UEFI')
        el = vertical(6)
        self.manual_efi_group.setLayout(el)
        self.manual_efi = self.role_combo(el, 'Partição EFI /boot/efi (obrigatória)', self.update_state)
        self.manual_format_efi = QCheckBox('Formatar EFI (apagar carregadores)')
        self.manual_format_efi.toggled.connect(self.update_state)
        el.addWidget(self.manual_format_efi)
        v.addWidget(self.manual_efi_group)
        self.manual_bios_group = QGroupBox('Inicialização BIOS')
        bl = vertical(6)
        self.manual_bios_group.setLayout(bl)
        self.manual_boot_disk = self.role_combo(bl, 'Disco onde instalar o bootloader', self.update_state)
        v.addWidget(self.manual_bios_group)
        homebox = QGroupBox('Arquivos pessoais')
        hl = vertical(6)
        homebox.setLayout(hl)
        self.manual_home = self.role_combo(hl, '/home (opcional; vazio = dentro da raiz)', self.on_home_changed)
        self.manual_format_home = QCheckBox('Formatar /home (apagar arquivos)')
        self.manual_format_home.toggled.connect(self.update_state)
        hl.addWidget(self.manual_format_home)
        v.addWidget(homebox)
        v.addWidget(text_label('Crie/redimensione as partições no GParted e atualize a lista. Após usar o GParted, a lista será atualizada automaticamente. Neste modo, selecione partições do mesmo disco.', name='info'))
        v.addStretch()
        return page

    def build_reuse_page(self):
        page, v = self.inner_page()
        v.addWidget(text_label('Escolha partições existentes para reutilizar. Raiz, EFI e /home precisam estar em partições comuns do mesmo disco. LVM não é suportado neste modo.', name='info'))
        self.reuse_root = self.role_combo(v, 'Raiz / (obrigatória — formatar ext4)', self.update_state)
        self.reuse_efi_group = QGroupBox('Inicialização UEFI')
        el = vertical(6)
        self.reuse_efi_group.setLayout(el)
        self.reuse_efi = self.role_combo(el, 'Partição EFI (será preservada)', self.update_state)
        v.addWidget(self.reuse_efi_group)
        self.reuse_bios_group = QGroupBox('Inicialização BIOS')
        bl = vertical(6)
        self.reuse_bios_group.setLayout(bl)
        self.reuse_boot_disk = self.role_combo(bl, 'Disco do bootloader', self.update_state)
        v.addWidget(self.reuse_bios_group)
        self.reuse_home = self.role_combo(v, '/home separada (opcional; será preservada)', self.on_home_changed)
        self.reuse_clean = QCheckBox('Limpar dotfiles da pasta pessoal')
        self.reuse_clean.toggled.connect(self.on_clean_changed)
        v.addWidget(self.reuse_clean)
        v.addWidget(text_label('Remove entradas ocultas diretamente de /home/usuário (inclui .local, .steam e .ssh).'))
        self.reuse_backup = QCheckBox('Criar backup antes da limpeza (indisponível neste modo)')
        self.reuse_backup.toggled.connect(self.update_state)
        self.reuse_backup.setEnabled(False)
        v.addWidget(self.reuse_backup)
        self.dotfiles_notice = text_label('Se ativada, a limpeza também inclui .local, Steam, chaves e perfis ocultos. O conteúdo visível será preservado.', name='warning')
        v.addWidget(self.dotfiles_notice)
        self.dotfiles_preview = QPlainTextEdit()
        self.dotfiles_preview.setReadOnly(True)
        self.dotfiles_preview.setMaximumHeight(105)
        v.addWidget(self.dotfiles_preview)
        v.addWidget(text_label('Sem seleção de limpeza, nenhuma entrada de /home será removida. A prévia consulta o volume escolhido em modo somente leitura, sem modificar seus dados.', name='muted'))
        v.addStretch()
        return page

    def build_review_page(self):
        page = QWidget()
        v = vertical(13)
        v.setContentsMargins(0, 2, 0, 4)
        page.setLayout(v)
        self.pages.addWidget(make_scroll(page))
        v.addWidget(section('4. Revisar alterações'))
        self.review_intro = text_label('')
        v.addWidget(self.review_intro)
        self.review_alert = text_label('As confirmações autorizam operações reais nos discos exibidos. Confira cuidadosamente o destino.', name='warning')
        v.addWidget(self.review_alert)
        self.review_table = QTableWidget(0, 3)
        self.review_table.setHorizontalHeaderLabels(['Dispositivo ou destino', 'Operação prevista', 'Efeito sobre os dados'])
        self.review_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Interactive)
        self.review_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeMode.Interactive)
        self.review_table.setColumnWidth(0, 180)
        self.review_table.setColumnWidth(1, 190)
        self.review_table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        self.review_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.review_table.setAlternatingRowColors(True)
        self.review_table.setWordWrap(True)
        self.review_table.verticalHeader().setVisible(False)
        self.review_table.setMinimumHeight(220)
        v.addWidget(self.review_table, 1)
        self.review_risks = text_label('', name='warning')
        v.addWidget(self.review_risks)
        row = QHBoxLayout()
        row.addWidget(button('Exportar resumo JSON', self.export_json))
        row.addStretch()
        self.confirm_button = button('Confirmar', self.double_confirm, style='primary')
        row.addWidget(self.confirm_button)
        v.addLayout(row)

    def build_terminal_page(self):
        page = QWidget()
        layout = vertical(10)
        layout.setContentsMargins(12, 8, 12, 12)
        page.setLayout(layout)
        layout.addWidget(section('Instalação — terminal integrado'))
        self.terminal_info = text_label('A instalação só começa após revisar e confirmar o plano.', name='info')
        layout.addWidget(self.terminal_info)
        self.terminal_output = QPlainTextEdit()
        self.terminal_output.setReadOnly(True)
        self.terminal_output.document().setMaximumBlockCount(6000)
        self.terminal_output.setStyleSheet('font: 10pt monospace; background: #090e15; color: #d6e4f5;')
        layout.addWidget(self.terminal_output, 1)
        input_row = QHBoxLayout()
        self.terminal_input = QLineEdit()
        self.terminal_input.setEnabled(False)
        self.terminal_input.setEchoMode(QLineEdit.EchoMode.Password)
        self.terminal_input.setPlaceholderText('Responda aqui caso o Bash solicite uma entrada ou senha')
        self.terminal_input.returnPressed.connect(self.send_terminal_input)
        input_row.addWidget(self.terminal_input, 1)
        self.terminal_send = button('Enviar ↵', self.send_terminal_input)
        self.terminal_send.setEnabled(False)
        input_row.addWidget(self.terminal_send)
        layout.addLayout(input_row)
        self.terminal_reveal = QCheckBox('Mostrar o texto digitado (não use para senhas)')
        self.terminal_reveal.toggled.connect(lambda reveal: self.terminal_input.setEchoMode(
            QLineEdit.EchoMode.Normal if reveal else QLineEdit.EchoMode.Password))
        layout.addWidget(self.terminal_reveal)
        footer = QHBoxLayout()
        self.terminal_back = button('Voltar à revisão', self.return_from_terminal)
        self.terminal_back.setEnabled(False)
        footer.addWidget(self.terminal_back)
        footer.addStretch()
        self.terminal_reboot = button('Reiniciar após sucesso', self.reboot_after_install, style='primary')
        self.terminal_reboot.hide()
        footer.addWidget(self.terminal_reboot)
        layout.addLayout(footer)
        self.pages.addWidget(page)

    def send_terminal_input(self):
        if self._pty is None or self._pty.poll() is not None:
            return
        value = self.terminal_input.text()
        self.terminal_input.clear()
        try:
            self._pty.send(value)
        except (OSError, ValueError, RuntimeError) as exc:
            QMessageBox.warning(self, 'Entrada recusada', str(exc))

    def read_terminal_output(self):
        if self._pty is None:
            return
        try:
            output, ended = self._pty.read()
        except OSError as exc:
            self.terminal_info.setText('Erro ao ler PTY: ' + str(exc))
            return
        if output:
            if self._installer_log:
                self._installer_log.write(output)
                self._installer_log.flush()
            self.terminal_output.appendPlainText(output.replace('\r', ''))
            self.terminal_output.ensureCursorVisible()
        if ended and self._pty_notifier:
            self._pty_notifier.setEnabled(False)

    def check_install_result(self):
        if self._pty is None:
            return
        rc = self._pty.poll()
        if rc is None:
            return
        self.read_terminal_output()
        self._pty_timer.stop()
        if self._pty_notifier:
            self._pty_notifier.setEnabled(False)
            self._pty_notifier.deleteLater()
            self._pty_notifier = None
        self._pty.close_read()
        self._pty = None
        if self._installer_log:
            self._installer_log.close()
            self._installer_log = None
        self.terminal_input.setEnabled(False)
        self.terminal_send.setEnabled(False)
        self.terminal_back.setEnabled(True)
        if rc == 0:
            self.terminal_info.setText('Instalação concluída com sucesso (código 0). Remova a ISO antes de inicializar pelo disco.')
            self.terminal_output.appendPlainText('\n[OK] INSTALAÇÃO CONCLUÍDA — código 0')
            self.terminal_reboot.show()
        else:
            self.terminal_info.setText(f'Instalação não concluída (código {rc}). Consulte o terminal; antes de tentar novamente, confira montagens e checkpoints.')
            self.terminal_output.appendPlainText(f'\n[ERRO] INSTALAÇÃO INTERROMPIDA — código {rc}')
        self.status.setText(f'Instalador finalizado com código {rc}.')

    def return_from_terminal(self):
        if self._pty is not None:
            return
        self.pages.setCurrentIndex(1)
        self.back_button.show()
        self.confirm_button.setEnabled(True)

    def reboot_after_install(self):
        if self._pty is not None or not self.terminal_reboot.isVisible():
            return
        answer = QMessageBox.question(self, 'Reiniciar',
                                      'A instalação terminou com sucesso. Reiniciar agora? Remova a ISO para iniciar pelo disco instalado.',
                                      QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                                      QMessageBox.StandardButton.No)
        if answer == QMessageBox.StandardButton.Yes:
            QProcess.startDetached('systemctl', ['reboot'])

    def closeEvent(self, event):
        if self._pty is not None and self._pty.poll() is None:
            QMessageBox.warning(self, 'Instalação em andamento',
                                'Aguarde a conclusão do Bash antes de fechar o instalador.')
            event.ignore()
            return
        super().closeEvent(event)

    def build_unselected_page(self):
        page, layout = self.inner_page()
        layout.addWidget(section('Escolha o tipo de instalação'))
        layout.addWidget(text_label('Selecione uma das modalidades à esquerda para exibir somente os campos correspondentes.'))
        layout.addStretch()
        return page

    def build_keyboard_page(self):
        page = QWidget()
        v = vertical(18)
        v.setContentsMargins(22, 22, 22, 22)
        page.setLayout(v)
        v.addWidget(section('1. Layout do teclado'))
        v.addWidget(text_label('Escolha e teste o teclado antes de definir o tipo de instalação.'))
        self.keyboard_combo = make_combo()
        for title, lang, model, variant in KEYBOARD_LAYOUTS:
            self.keyboard_combo.addItem(title, (lang, model, variant))
        self.keyboard_combo.currentIndexChanged.connect(self.apply_keyboard)
        v.addWidget(self.keyboard_combo)
        v.addWidget(text_label('Teste a digitação:'))
        self.keyboard_test = QLineEdit()
        self.keyboard_test.setPlaceholderText('Digite aqui: ç á é / ? @')
        v.addWidget(self.keyboard_test)
        self.keyboard_feedback = text_label('')
        v.addWidget(self.keyboard_feedback)
        v.addStretch()
        v.addWidget(button('Avançar para o tipo de instalação →', self.finish_keyboard_step, style='primary'))
        self.pages.addWidget(page)

    def apply_keyboard(self, *_):
        keyboard = self.keyboard_combo.currentData()
        if not keyboard:
            return
        self.keyboard = keyboard
        lang, model, variant = keyboard
        cmd = ['setxkbmap', '-model', model, '-layout', lang]
        if variant:
            cmd += ['-variant', variant]
        cmd += ['-option', '']
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            self.keyboard_feedback.setText('Layout aplicado à sessão Live.' if proc.returncode == 0
                else 'Layout selecionado; teste da sessão indisponível: ' + proc.stderr.strip()[:130])
        except (OSError, subprocess.TimeoutExpired):
            self.keyboard_feedback.setText('Layout selecionado; aplicação ao teclado Live indisponível.')
        self.keyboard_test.clear()
        title = self.keyboard_combo.currentText().split(' — ')[0]
        self.keyboard_button.setText('Teclado: ' + title + ' ↗')
        self.update_state()

    def finish_keyboard_step(self):
        self.apply_keyboard()
        self.pages.setCurrentIndex(0)
        self.continue_button.show()
        self.back_button.hide()
        self.status.setText('Etapa 2: escolha o tipo de instalação e configure o armazenamento.')

    def open_keyboard_step(self):
        if self._pty is not None:
            return
        self.pages.setCurrentIndex(2)
        self.back_button.hide()
        self.continue_button.hide()
        self.status.setText('Etapa 1: layout do teclado.')

    def change_keyboard(self):
        self.open_keyboard_step()

    def mode_changed(self, mode: str):
        self.mode = mode
        if not self.mode_radios[mode].isChecked():
            self.mode_radios[mode].setChecked(True)
        idx = {'erase':0, 'manual':1, 'reuse':2}[mode]
        self.config_stack.setCurrentIndex(idx)
        self.mode_title.setText({
            'erase':'Apagar disco inteiro', 'manual':'Particionamento manual',
            'reuse':'Reutilizar partições existentes'}[mode])
        self.mode_description.setText({
            'erase':'Assistente automático: selecione somente o disco e como distribuir / e /home.',
            'manual':'Selecione as funções de cada volume e escolha explicitamente o que formatar.',
            'reuse':'Instale novamente o sistema preservando EFI e /home (quando separada).',
        }[mode])
        self.update_state()

    def select_combo(self, combo: QComboBox, entries, *, empty: str | None = None):
        prior = combo.currentData()
        combo.blockSignals(True)
        combo.clear()
        if empty is not None:
            combo.addItem(empty, '')
        for text, val in entries:
            combo.addItem(text, val)
            combo.setItemData(combo.count()-1, text, Qt.ItemDataRole.ToolTipRole)
        if prior:
            idx = combo.findData(prior)
            if idx >= 0:
                combo.setCurrentIndex(idx)
        combo.blockSignals(False)

    def populate_devices(self):
        disk_items = [(describe_device(d), d.path) for d in self.inventory.disks]
        vol_items = [(describe_device(d), d.path) for d in self.inventory.volumes]
        esp_items = [(describe_device(d), d.path) for d in self.inventory.volumes if d.kind == 'part']
        self.select_combo(self.erase_disk, disk_items, empty='Selecione a unidade para apagar...')
        for combo in (self.manual_root, self.manual_home, self.reuse_root, self.reuse_home):
            self.select_combo(combo, vol_items, empty='Escolha uma partição ou volume...' if combo in (self.manual_root, self.reuse_root) else 'Não usar partição /home separada')
        for combo in (self.manual_efi, self.reuse_efi):
            self.select_combo(combo, esp_items, empty='Selecione a partição EFI...')
        for combo in (self.manual_boot_disk, self.reuse_boot_disk):
            self.select_combo(combo, disk_items, empty='Selecione o disco de inicialização...')
        uefi = self.inventory.firmware == 'UEFI'
        for item in (self.manual_efi_group, self.reuse_efi_group):
            item.setVisible(uefi)
        for item in (self.manual_bios_group, self.reuse_bios_group):
            item.setVisible(not uefi)
        self.erase_boot_notice.setText('Inicialização UEFI: será prevista uma partição EFI FAT32.'
                                       if uefi else 'Inicialização BIOS: será previsto um layout de boot compatível, sujeito à validação futura do disco.')
        self.firmware_label.setText('UEFI' if uefi else 'BIOS / Legacy')
        self.on_erase_disk_change()
        self.on_home_changed()
        self.update_erase_table()

    def refresh_devices(self):
        if self.inventory.illustrative:
            self.inventory = demo_inventory()
        else:
            try:
                self.inventory = detect_inventory()
            except PreviewError as exc:
                QMessageBox.warning(self, 'Falha de leitura', str(exc))
                return
        self.populate_devices()
        self.update_state()
        self.status.setText(f'Dispositivos atualizados: {len(self.inventory.disks)} discos e {len(self.inventory.volumes)} volumes.')

    def on_erase_home_change(self, *_):
        separate = bool(self.erase_home.currentData())
        try:
            budget = erase_budget(self.inventory, self.erase_disk.currentData() or '')
        except PreviewError:
            self.update_state()
            return
        default_root = min(60, max(25, budget.usable_gib - 10)) if separate else budget.usable_gib
        self.set_numeric(self.erase_root, 25, max(25, default_root), default_root)
        self.update_state()

    def on_home_changed(self, *_):
        enabled = bool(self.reuse_home.currentData())
        self.reuse_clean.setEnabled(enabled)
        if not enabled:
            self.reuse_clean.setChecked(False)
        self.manual_format_home.setEnabled(bool(self.manual_home.currentData()))
        if not self.manual_home.currentData():
            self.manual_format_home.setChecked(False)
        self.on_clean_changed()

    def on_clean_changed(self, *_):
        has_cleanup = bool(self.reuse_clean.isChecked() and self.reuse_clean.isEnabled())
        self.reuse_backup.setVisible(has_cleanup)
        self.dotfiles_notice.setVisible(has_cleanup)
        self.dotfiles_preview.setVisible(has_cleanup)
        if not has_cleanup:
            self.reuse_backup.setChecked(False)
        if has_cleanup:
            volume = str(self.reuse_home.currentData() or '')
            username = self.user_input.text().strip()
            if not volume or not username:
                self.dotfiles_preview.setPlainText('Escolha a partição /home e o nome de usuário.')
            elif self.inventory.illustrative:
                self.dotfiles_preview.setPlainText('Inventário ilustrativo: sem leitura de arquivos.')
            else:
                try:
                    proc = subprocess.run(['sudo', '-n', 'wolf-home-preview-live', volume, username],
                                          capture_output=True, text=True, timeout=18, check=False)
                    if proc.returncode == 0:
                        self.dotfiles_preview.setPlainText(proc.stdout.strip() or 'Nenhum arquivo oculto encontrado para este usuário.')
                    else:
                        self.dotfiles_preview.setPlainText('Prévia indisponível: ' + (proc.stderr.strip()[:500] or str(proc.returncode)))
                except (OSError, subprocess.TimeoutExpired) as exc:
                    self.dotfiles_preview.setPlainText(f'Não foi possível consultar o volume: {exc}')
        self.update_state()

    def update_erase_table(self):
        d = self.inventory.get(self.erase_disk.currentData() or '')
        volumes = self.inventory.descendants(d.path) if d else []
        self.erase_partitions.setRowCount(len(volumes))
        for row, v in enumerate(volumes):
            for col, value in enumerate((v.path, human_size(v.size), v.fstype or 'sem formato')):
                self.erase_partitions.setItem(row, col, QTableWidgetItem(value))

    def choices(self) -> Choices:
        if self.mode is None:
            raise PreviewError('Selecione um tipo de instalação à esquerda.')
        if self.mode == 'erase':
            separate = bool(self.erase_home.currentData())
            home_gib = self.erase_home_size.value() if separate and not self.erase_auto_home.isChecked() else None
            return Choices(mode='erase', erase_disk=self.erase_disk.currentData() or '',
                           erase_home_separate=separate, erase_root_gib=self.erase_root.value(),
                           erase_home_gib=home_gib)
        if self.mode == 'manual':
            return Choices(mode='manual', root=self.manual_root.currentData() or '',
                           efi=self.manual_efi.currentData() or '',
                           bios_disk=self.manual_boot_disk.currentData() or '',
                           home=self.manual_home.currentData() or '',
                           format_efi=self.manual_format_efi.isChecked(),
                           format_home=self.manual_format_home.isChecked())
        return Choices(mode='reuse', root=self.reuse_root.currentData() or '',
                       efi=self.reuse_efi.currentData() or '',
                       bios_disk=self.reuse_boot_disk.currentData() or '',
                       home=self.reuse_home.currentData() or '',
                       clean_dotfiles=self.reuse_clean.isChecked(),
                       backup_dotfiles=self.reuse_backup.isChecked())

    def update_profile_space(self):
        """Advisory only: root filesystem sizes vary with optional downloads."""
        estimates = {'minimal': (25, 35), 'test': (40, 60), 'full': (75, 110)}
        preset = self.preset_combo.currentData()
        if preset not in estimates:
            self.disk_space_advice.setText('Escolha um perfil para ver a estimativa de espaço em / (não inclui jogos e arquivos pessoais).')
            return
        low, high = estimates[preset]
        root_gib = None
        if self.mode == 'erase':
            root_gib = self.erase_root.value()
        elif self.mode == 'manual':
            root = self.inventory.get(self.manual_root.currentData() or '')
            root_gib = root.size / (1024 ** 3) if root else None
        elif self.mode == 'reuse':
            root = self.inventory.get(self.reuse_root.currentData() or '')
            root_gib = root.size / (1024 ** 3) if root else None
        parts = ('Base KDE 25–35 GiB · Daily +8–15 · Gaming +10–25 · '
                 'Development +5–12 · Android/Flutter +20–40 · Containers +3–10 · Extras +2–8 GiB')
        headline = f'{preset.title()}: estimativa de {low}–{high} GiB em / (valores indicativos, não limites garantidos).'
        if root_gib is not None:
            headline += f' Raiz selecionada: {root_gib:.0f} GiB.'
            if root_gib < low:
                headline += ' ATENÇÃO: a raiz é menor que o estimado; downloads podem esgotar o espaço.'
        self.disk_space_advice.setText(headline + '\n' + parts)
        self.disk_space_advice.setObjectName('warning' if root_gib is not None and root_gib < low else 'info')
        self.disk_space_advice.style().unpolish(self.disk_space_advice)
        self.disk_space_advice.style().polish(self.disk_space_advice)

    def update_state(self, *_):
        if not hasattr(self, 'validation_label'):
            return
        self.update_profile_space()
        if self.mode == 'erase':
            self.update_erase_table()
            self.update_erase_budget()
        if hasattr(self, 'manual_format_home'):
            self.manual_format_home.setEnabled(bool(self.manual_home.currentData()))
        try:
            self.operations = validate_plan(self.inventory, self.choices())
        except PreviewError as exc:
            self.operations = []
            self.validation_label.setText('Para continuar: ' + str(exc))
            self.continue_button.setEnabled(False)
        else:
            self.validation_label.setText('Plano pronto para revisão. Execução somente após validação independente e duas confirmações.')
            self.continue_button.setEnabled(True)
        if self.preset_combo.currentData() is None:
            self.validation_label.setText('Escolha um perfil de instalação (Minimal, Test ou Full) para continuar.')
            self.continue_button.setEnabled(False)

    @staticmethod
    def is_within(widget, ancestor):
        while widget is not None:
            if widget is ancestor:
                return True
            widget = widget.parentWidget()
        return False

    def eventFilter(self, watched, event):
        # A roda movimenta a seção sob o cursor, em vez de mudar o valor
        # do combo ou do slider; popups abertos continuam com a rolagem nativa.
        if (event.type() == QEvent.Type.Wheel and isinstance(watched, QWidget)
                and self.pages.currentIndex() == 0
                and QApplication.activePopupWidget() is None):
            for area in (self.nav_scroll, self.config_stack.currentWidget()):
                if self.is_within(watched, area):
                    scroll = area.verticalScrollBar()
                    pixels = event.pixelDelta().y()
                    delta = pixels if pixels else round(event.angleDelta().y() * 0.75)
                    if delta:
                        scroll.setValue(scroll.value() - delta)
                        event.accept()
                        return True
        return super().eventFilter(watched, event)

    def open_utilities(self):
        dialog = QDialog(self)
        dialog.setWindowTitle('Ferramentas auxiliares')
        screen = QApplication.primaryScreen()
        available = screen.availableGeometry() if screen else None
        dialog.resize(min(650, available.width()-55) if available else 650,
                      min(600, available.height()-65) if available else 600)
        layout = vertical(9)
        layout.setContentsMargins(14, 14, 14, 14)
        dialog.setLayout(layout)
        scroller = QScrollArea(dialog)
        scroller.setWidgetResizable(True)
        holder = QWidget()
        utility_layout = vertical(9)
        holder.setLayout(utility_layout)
        scroller.setWidget(holder)
        layout.addWidget(scroller, 1)
        utility_layout.addWidget(section('Ferramentas da sessão Live'))
        utility_layout.addWidget(text_label('Abra os programas disponíveis no ambiente atual. '
                                    'Alguns utilitários podem alterar discos independentemente do instalador.',
                                    name='warning'))
        for key, title, _commands in UTILITIES:
            cmd = utility_command(key)
            row = QHBoxLayout()
            row.addWidget(text_label(title))
            row.addStretch(1)
            action = button('Abrir  ↗' if cmd else 'Indisponível',
                            lambda _checked=False, k=key: self.launch_utility(k))
            action.setEnabled(bool(cmd))
            row.addWidget(action)
            utility_layout.addLayout(row)
        utility_layout.addStretch()
        layout.addWidget(button('Fechar', dialog.accept))
        dialog.exec()

    def launch_utility(self, key: str):
        cmd = utility_command(key)
        if not cmd:
            QMessageBox.warning(self, 'Aplicativo indisponível',
                                'O utilitário não está instalado ou o atalho da ISO não está disponível neste sistema.')
            return
        if key == 'gparted':
            result = QMessageBox.warning(
                self, 'Atenção: GParted modifica discos',
                'O GParted é uma ferramenta independente. Se você aplicar alterações '
                'dentro dele, discos e partições serão modificados DE VERDADE.\n\n'
                'O instalador não controla nem desfaz as alterações do GParted. Deseja abrir?',
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No)
            if result != QMessageBox.StandardButton.Yes:
                return
        if key == 'gparted':
            self._gparted = QProcess(self)
            self._gparted.finished.connect(lambda _rc, _status: self.refresh_devices())
            self._gparted.errorOccurred.connect(lambda _err: self.status.setText('Erro ao executar GParted.'))
            self._gparted.start(cmd[0], list(cmd[1:]))
            if not self._gparted.waitForStarted(3000):
                QMessageBox.warning(self, 'Não foi possível abrir', self._gparted.errorString())
                return
            self.status.setText('GParted aberto. A lista será atualizada ao fechar a ferramenta.')
            return
        try:
            ok, _pid = QProcess.startDetached(cmd[0], list(cmd[1:]))
        except Exception as exc:
            QMessageBox.warning(self, 'Não foi possível abrir', str(exc))
            return
        if not ok:
            QMessageBox.warning(self, 'Não foi possível abrir',
                                'Falha ao iniciar a ferramenta. Verifique se o comando está disponível e autorizado.')
        else:
            self.status.setText('Ferramenta externa iniciada. Verifique os dispositivos novamente após usá-la.')

    def go_review(self):
        if self.preset_combo.currentData() is None:
            QMessageBox.warning(self, 'Perfil obrigatório', 'Selecione Minimal, Test ou Full antes de revisar a instalação.')
            self.preset_combo.setFocus()
            return
        try:
            self.operations = validate_plan(self.inventory, self.choices())
            choices = self.choices()
            doc = build_vm_plan(self.inventory, choices, self.user_input.text().strip(),
                                self.host_input.text().strip(), self.preset_combo.currentData(), self.keyboard)
            check_vm_plan(doc)
        except (PreviewError, BridgeError) as exc:
            QMessageBox.warning(self, 'Plano não executável', str(exc))
            self.update_state()
            return
        self.review_plan = doc
        label = {'erase':'Apagar disco inteiro', 'manual':'Particionamento manual',
                 'reuse':'Reutilizar partições existentes'}[self.mode]
        self.review_intro.setText(f'Modo: {label}  •  Firmware: {self.inventory.firmware}  •  Perfil: {self.preset_combo.currentData()}\n'
                                  f'Usuário: {doc["identity"]["username"]}  •  Teclado: {self.keyboard[0]}  •  Disco: {doc["storage"]["disk"]["path"]}')
        self.review_table.setRowCount(len(self.operations))
        for row, op in enumerate(self.operations):
            for col, value in enumerate((op.target, op.action, op.impact)):
                self.review_table.setItem(row, col, QTableWidgetItem(value))
            self.review_table.resizeRowToContents(row)
            self.review_table.setRowHeight(row, max(52, self.review_table.rowHeight(row)))
        n = sum(op.destructive for op in self.operations)
        self.review_risks.setText(f'{n} item(ns) podem causar perda de dados. '
                                  'A execução exige sessão Live e revalidação do destino '
                                  'e as partições, EFI e identificadores serão reconferidos pelo executor.')
        self.pages.setCurrentIndex(1)
        self.back_button.show()
        self.continue_button.hide()
        self.status.setText('Plano pré-validado; aguardando confirmação.')

    def return_to_choices(self):
        self.pages.setCurrentIndex(0)
        self.back_button.hide()
        self.continue_button.show()
        self.update_state()

    def full_description(self):
        return '\n\n'.join(f'{"APAGA/MODIFICA" if op.destructive else "PRESERVA/CRIA"}  |  {op.target}\n'
                           f'Operação: {op.action}\nEfeito: {op.impact}' for op in self.operations)

    def double_confirm(self):
        if not self.review_plan:
            QMessageBox.warning(self, 'Revise novamente', 'Nenhum plano de execução foi preparado.')
            return
        # Refaz o plano ANTES dos cliques, sem confiar no estado anterior da GUI.
        try:
            current = build_vm_plan(self.inventory, self.choices(), self.user_input.text().strip(),
                                    self.host_input.text().strip(), self.preset_combo.currentData(), self.keyboard)
            if current != self.review_plan:
                raise BridgeError('A configuração mudou depois da revisão. Revise novamente.')
            # O preflight completo já ocorreu em Revisar. Repetir somente
            # DEPOIS dos dois cliques, imediatamente antes de iniciar o Bash.
        except (PreviewError, BridgeError) as exc:
            QMessageBox.warning(self, 'Verificação interrompida', str(exc))
            self.return_to_choices()
            return
        desc = self.full_description()
        if ConfirmDialog(self, final=False, description=desc).exec() != QDialog.DialogCode.Accepted:
            self.status.setText('Instalação cancelada na primeira confirmação.')
            return
        if ConfirmDialog(self, final=True, description=desc).exec() != QDialog.DialogCode.Accepted:
            self.status.setText('Instalação cancelada na confirmação final.')
            return
        try:
            # Inventário de armazenamento atualizado ANTES de autorizar o Bash.
            check_vm_plan(current)
            from vm_bridge import write_vm_plan
            plan = write_vm_plan(current)
        except (BridgeError, OSError) as exc:
            QMessageBox.critical(self, 'Instalação bloqueada', str(exc))
            return
        # Chama EXATAMENTE o mesmo PTY do instalador clássico; não abre QTerminal externo.
        # O Bash repete todas as verificações e usa a flag liberada só para clique duplo.
        if self._pty is not None:
            QMessageBox.warning(self, 'Instalação em andamento', 'Aguarde o executor atual terminar.')
            return
        self.pages.setCurrentIndex(3)
        self.back_button.hide()
        self.continue_button.hide()
        self.confirm_button.setEnabled(False)
        self.terminal_back.setEnabled(False)
        self.terminal_reboot.hide()
        self.terminal_output.clear()
        self.terminal_info.setText('Executando o instalador Bash. Respostas e solicitações aparecerão abaixo.')
        try:
            log_dir = Path.home()/'.local/state/wolf-linux/live-installer'
            log_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            fd, name = tempfile.mkstemp(prefix='gui-install-', suffix='.log', dir=str(log_dir))
            os.fchmod(fd, 0o600)
            self._installer_log = os.fdopen(fd, 'w', encoding='utf-8', errors='replace')
            engine = InstallerPty()
            master = engine.start(plan, mode='--execute-gui-plan-vm-click')
            self._pty = engine
            self._pty_notifier = QSocketNotifier(master, QSocketNotifier.Type.Read, self)
            self._pty_notifier.activated.connect(self.read_terminal_output)
            self.terminal_input.setEnabled(True)
            self.terminal_send.setEnabled(True)
            self.terminal_input.setFocus()
            self._pty_timer.start(200)
            self.status.setText('Instalação em andamento — terminal integrado.')
        except (OSError, RuntimeError, ValueError) as exc:
            if self._installer_log:
                self._installer_log.close()
                self._installer_log = None
            self.terminal_back.setEnabled(True)
            self.terminal_info.setText('Não foi possível iniciar o executor Bash.')
            self.terminal_output.appendPlainText('[ERRO] '+str(exc))

    def export_json(self):
        if not self.operations:
            return
        name, _ = QFileDialog.getSaveFileName(self, 'Salvar revisão (sem execução)',
                                              str(Path.home()/'wolf-plano-previa.json'),
                                              'Arquivos JSON (*.json)')
        if not name:
            return
        doc = safe_export(self.choices(), self.inventory, self.operations)
        try:
            Path(name).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        except OSError as exc:
            QMessageBox.warning(self, 'Falha ao salvar', str(exc))
        else:
            self.status.setText('Revisão salva como arquivo não executável.')


def main() -> int:
    parser = argparse.ArgumentParser(description='Instalador Wolf Linux: instalações reais com confirmação')
    parser.add_argument('--demonstracao', action='store_true', help='exibir inventário fictício ilustrativo')
    args = parser.parse_args()
    try:
        inv = demo_inventory() if args.demonstracao else detect_inventory()
    except PreviewError as exc:
        print(f'Falha na leitura dos discos: {exc}\nUse --demonstracao para visualizar sem discos.', file=sys.stderr)
        return 1
    app = QApplication(sys.argv[:1])
    app.setStyle('Fusion')
    app.setStyleSheet(STYLE)
    window = MainWindow(inv)
    if inv.illustrative:
        window.status.setText('Dados ilustrativos: os nomes exibidos não representam os dispositivos do computador.')
    window.show()
    return app.exec()


if __name__ == '__main__':
    raise SystemExit(main())
