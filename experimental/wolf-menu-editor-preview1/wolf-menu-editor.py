#!/usr/bin/env python3
"""Wolf Menu Editor 0.1 Preview 1 — editor .desktop por usuário, LXQt/Qt6.

Nunca modifica entradas globais de aplicativos ou arquivos do pacman.
Usa o ID XDG para que os overrides sejam aplicados pelo LXQt.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import datetime as dt
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import unicodedata
import uuid

VERSION = '0.1-preview1'
GROUP = '[Desktop Entry]'
GROUP_RE = re.compile(r'^\s*\[[^\]]+\]\s*$')
KEY_RE = re.compile(r'^([A-Za-z][A-Za-z0-9-]*(?:\[[^\]]+\])?)\s*=')


class MenuError(RuntimeError):
    pass


def safe_value(value: str, label: str) -> str:
    value = value.strip()
    if '\n' in value or '\r' in value or '\x00' in value:
        raise MenuError(f'Valor inválido: {label}')
    return value


def desktop_get(content: str, key: str, default: str = '') -> str:
    inside = False
    for line in content.splitlines():
        if GROUP_RE.match(line):
            inside = line.strip() == GROUP
            continue
        if inside:
            m = KEY_RE.match(line)
            if m and m.group(1) == key:
                return line.split('=', 1)[1].strip()
    return default


def desktop_update(content: str, changes: dict[str, str | None]) -> str:
    """Altera apenas chaves no [Desktop Entry]; preserva outras seções, ações e comentários."""
    if GROUP not in [x.strip() for x in content.splitlines() if GROUP_RE.match(x)]:
        raise MenuError('Arquivo sem grupo [Desktop Entry].')
    lines = content.splitlines(keepends=True)
    output: list[str] = []
    section = False
    seen: set[str] = set()
    inserted = False
    for line in lines:
        if GROUP_RE.match(line):
            if section and not inserted:
                for key, value in changes.items():
                    if key not in seen and value is not None:
                        output.append(f'{key}={value}\n')
                inserted = True
            section = line.strip() == GROUP
            output.append(line)
            continue
        if section:
            m = KEY_RE.match(line)
            if m and m.group(1) in changes:
                key = m.group(1)
                if key not in seen:
                    new = changes[key]
                    if new is not None:
                        output.append(f'{key}={new}\n')
                    seen.add(key)
                continue
        output.append(line)
    if section and not inserted:
        for key, value in changes.items():
            if key not in seen and value is not None:
                output.append(f'{key}={value}\n')
    return ''.join(output)


def normalized_categories(value: str) -> str:
    raw = [x.strip() for x in value.replace(',', ';').split(';')]
    vals = []
    for x in raw:
        if x and x not in vals:
            if not re.fullmatch(r'[A-Za-z0-9_-]+', x):
                raise MenuError(f'Categoria inválida: {x}')
            vals.append(x)
    return (';'.join(vals) + ';') if vals else ''


def display_name(content: str) -> str:
    for key in ('Name[pt_BR]', 'Name[pt]', 'Name'):
        name = desktop_get(content, key)
        if name:
            return name
    return '(sem nome)'


def desktop_id(path: Path, base: Path) -> str:
    return str(path.relative_to(base)).replace('/', '-')


@dataclass
class Entry:
    entry_id: str
    active_path: Path
    user_path: Path | None
    system_path: Path | None
    content: str

    @property
    def hidden(self) -> bool:
        return desktop_get(self.content, 'NoDisplay').lower() == 'true' or desktop_get(self.content, 'Hidden').lower() == 'true'

    @property
    def name(self) -> str:
        return display_name(self.content)

    @property
    def origin(self) -> str:
        if self.user_path and self.system_path:
            return 'Personalizada (sobrepõe sistema)'
        if self.user_path:
            return 'Entrada pessoal'
        return 'Entrada do sistema'


class Repository:
    def __init__(self, user_dir: Path | None = None, system_dirs: list[Path] | None = None,
                 backup_dir: Path | None = None):
        xdg_data_home = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
        self.user_dir = user_dir or (xdg_data_home / 'applications')
        if system_dirs is None:
            system_dirs = [Path(p) / 'applications' for p in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':') if p]
        self.system_dirs = system_dirs
        self.backup_dir = backup_dir or (xdg_data_home / 'wolf-menu-editor/backups')

    def discover(self) -> dict[str, Entry]:
        entries: dict[str, dict[str, Path]] = {}
        for base in [*self.system_dirs, self.user_dir]:
            if not base.is_dir():
                continue
            # Locais por usuário sempre têm prioridade; entre diretórios globais, o primeiro ganha.
            files = sorted(base.rglob('*.desktop'))
            for path in files:
                if not path.is_file() or path.is_symlink():
                    continue
                eid = desktop_id(path, base)
                slot = entries.setdefault(eid, {})
                if base == self.user_dir:
                    slot['user'] = path
                else:
                    slot.setdefault('system', path)
        out = {}
        for eid, data in entries.items():
            active = data.get('user') or data.get('system')
            if not active:
                continue
            try:
                text = active.read_text(encoding='utf-8-sig')
            except (UnicodeError, OSError):
                continue
            if desktop_get(text, 'Type', 'Application') not in ('Application', ''):
                continue
            if GROUP not in text:
                continue
            out[eid] = Entry(eid, active, data.get('user'), data.get('system'), text)
        return out

    def _safe_user_path(self, path: Path) -> Path:
        if path.suffix != '.desktop' or path.is_symlink():
            raise MenuError('Destino inválido ou link simbólico não permitido.')
        # Resolve o diretório pai para evitar saída da árvore local.
        root = self.user_dir.expanduser().resolve()
        parent = path.expanduser().parent.resolve()
        if parent != root and root not in parent.parents:
            raise MenuError('Alterações permitidas somente em ~/.local/share/applications.')
        return path

    def _backup(self, path: Path) -> Path | None:
        if not path.exists():
            return None
        if path.is_symlink():
            raise MenuError('Não alteramos links simbólicos de lançadores.')
        if not path.is_file():
            raise MenuError('O lançador não é um arquivo normal.')
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        label = dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        name = f'{label}-{uuid.uuid4().hex[:8]}-{path.name}'
        dest = self.backup_dir / name
        shutil.copy2(path, dest)
        return dest

    def _atomic_write(self, path: Path, content: str) -> None:
        path = self._safe_user_path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            self._backup(path)
        fd, tmp = tempfile.mkstemp(prefix='.wolf-menu-', suffix='.tmp', dir=path.parent)
        try:
            with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
                f.write(content)
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, 0o644)
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    def delete_local(self, entry: Entry) -> str:
        if entry.user_path is None:
            raise MenuError('Entradas do sistema não podem ser excluídas.')
        path = self._safe_user_path(entry.user_path)
        backup = self._backup(path)
        path.unlink()
        return str(backup)

    def local_target(self, entry: Entry) -> Path:
        if entry.user_path:
            return entry.user_path
        return self.user_dir / entry.entry_id

    def save(self, entry: Entry | None, *, name: str, command: str, comment: str,
             icon: str, categories: str, workdir: str, tryexec: str,
             terminal: bool, visible: bool) -> Path:
        name = safe_value(name, 'nome')
        command = safe_value(command, 'comando')
        if not name or not command:
            raise MenuError('Nome e comando são obrigatórios.')
        comment = safe_value(comment, 'descrição')
        icon = safe_value(icon, 'ícone')
        workdir = safe_value(workdir, 'diretório de trabalho')
        tryexec = safe_value(tryexec, 'TryExec')
        categories = normalized_categories(safe_value(categories, 'categorias'))
        if entry is None:
            slug = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode().lower()
            slug = re.sub(r'[^a-z0-9]+', '-', slug).strip('-') or 'aplicativo'
            base = f'wolf-{slug}'
            filename = base + '.desktop'
            taken = set(self.discover())
            i = 2
            while filename in taken or (self.user_dir / filename).exists():
                filename = f'{base}-{i}.desktop'
                i += 1
            path = self.user_dir / filename
            content = '[Desktop Entry]\nType=Application\nVersion=1.0\n'
        else:
            path = self.local_target(entry)
            content = entry.content
        changes = {
            'Type': 'Application', 'Name': name,
            'Name[pt_BR]': name, 'Name[pt]': name,
            'Exec': command, 'Comment': comment or None,
            'Comment[pt_BR]': comment or None, 'Comment[pt]': comment or None,
            'Icon': icon or None, 'Categories': categories or None,
            'Path': workdir or None, 'TryExec': tryexec or None,
            'Terminal': 'true' if terminal else 'false',
            'NoDisplay': 'false' if visible else 'true', 'Hidden': 'false',
        }
        edited = desktop_update(content, changes)
        self._atomic_write(path, edited)
        return path

    def hide(self, entry: Entry) -> Path:
        target = self.local_target(entry)
        new = desktop_update(entry.content, {'NoDisplay': 'true'})
        self._atomic_write(target, new)
        return target


def selftest() -> None:
    with tempfile.TemporaryDirectory(prefix='wolf-menu-test-') as tmp:
        root = Path(tmp)
        sysdir, userdir = root / 'system', root / 'user'
        sysdir.mkdir()
        userdir.mkdir()
        a = sysdir / 'foo.desktop'
        a.write_text('[Desktop Entry]\nType=Application\nName=Foo\nExec=foo %U\nIcon=foo\n[Desktop Action Edit]\nName=Edit\nExec=foo --edit\n', encoding='utf-8')
        repo = Repository(userdir, [sysdir], root / 'backups')
        items = repo.discover()
        assert 'foo.desktop' in items and items['foo.desktop'].system_path == a
        repo.hide(items['foo.desktop'])
        items = repo.discover()
        assert items['foo.desktop'].hidden and a.read_text(encoding='utf-8').find('NoDisplay') == -1
        repo.save(items['foo.desktop'], name='Foo Personalizado', command='foo --new %U', comment='Teste', icon='foo',
                  categories='Utility;Settings;', workdir='', tryexec='', terminal=False, visible=True)
        items = repo.discover()
        assert not items['foo.desktop'].hidden
        assert desktop_get(items['foo.desktop'].content, 'Name[pt_BR]') == 'Foo Personalizado'
        assert '[Desktop Action Edit]\nName=Edit\nExec=foo --edit' in items['foo.desktop'].content
        assert a.read_text(encoding='utf-8').find('Personalizado') == -1
        assert any((root / 'backups').iterdir())
        repo.delete_local(items['foo.desktop'])
        assert repo.discover()['foo.desktop'].name == 'Foo'
        p = repo.save(None, name='Novo Teste', command='/usr/bin/true', comment='', icon='utilities-terminal',
                      categories='Utility', workdir='', tryexec='', terminal=False, visible=True)
        assert p.is_file() and desktop_get(p.read_text(), 'Categories') == 'Utility;'
        assert p.name in repo.discover()
        repo.delete_local(repo.discover()[p.name])
        assert p.name not in repo.discover()
        print('[OK] 10 verificações: descoberta, ocultação, override, ações, backup, restauração, criação e exclusão.')


def gui() -> None:
    try:
        from PySide6.QtCore import Qt
        from PySide6.QtGui import QIcon
        from PySide6.QtWidgets import (
            QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
            QSplitter, QListWidget, QListWidgetItem, QLineEdit, QLabel,
            QPushButton, QFormLayout, QCheckBox, QMessageBox,
            QFileDialog, QComboBox, QScrollArea, QGroupBox,
        )
    except ImportError:
        print('[ERRO] PySide6 ausente: sudo pacman -S --needed pyside6', file=sys.stderr)
        raise SystemExit(2)

    class Window(QMainWindow):
        def __init__(self):
            super().__init__()
            self.repo = Repository()
            self.entries: dict[str, Entry] = {}
            self.current: Entry | None = None
            self.creating = False
            self.setWindowTitle(f'Wolf Menu Editor — {VERSION}')
            self.resize(1120, 720)
            self.setMinimumSize(840, 560)
            self.build()
            self.refresh()

        def build(self):
            root = QWidget()
            self.setCentralWidget(root)
            outer = QVBoxLayout(root)
            header = QLabel('Editor do Menu de Aplicativos')
            font = header.font(); font.setPointSize(16); font.setBold(True); header.setFont(font)
            outer.addWidget(header)
            outer.addWidget(QLabel('Edições pessoais, sem alterar programas nem arquivos gerenciados pelo Pacman.'))
            splitter = QSplitter(Qt.Orientation.Horizontal)
            outer.addWidget(splitter, 1)

            left = QWidget(); lv = QVBoxLayout(left)
            self.search = QLineEdit(); self.search.setPlaceholderText('Buscar aplicativo ou comando…')
            lv.addWidget(self.search)
            self.show_hidden = QCheckBox('Exibir entradas ocultas')
            self.show_hidden.setChecked(True)
            lv.addWidget(self.show_hidden)
            self.listing = QListWidget(); lv.addWidget(self.listing, 1)
            bl = QHBoxLayout()
            self.btn_new = QPushButton('Novo aplicativo')
            self.btn_reload = QPushButton('Atualizar')
            bl.addWidget(self.btn_new); bl.addWidget(self.btn_reload)
            lv.addLayout(bl)
            splitter.addWidget(left)

            scroll = QScrollArea(); scroll.setWidgetResizable(True)
            right = QWidget(); rv = QVBoxLayout(right)
            self.info = QLabel('Selecione uma entrada ou crie uma nova.'); self.info.setWordWrap(True)
            rv.addWidget(self.info)
            form = QFormLayout()
            self.name = QLineEdit(); self.exec = QLineEdit(); self.comment = QLineEdit()
            self.icon = QLineEdit(); self.categories = QLineEdit()
            self.workdir = QLineEdit(); self.tryexec = QLineEdit()
            self.terminal = QCheckBox('Executar em terminal')
            self.visible = QCheckBox('Mostrar no menu de aplicativos')
            self.visible.setChecked(True)
            for label, field in [('Nome:',self.name),('Comando (Exec):',self.exec),('Descrição:',self.comment),
                                 ('Ícone (nome ou arquivo):',self.icon),('Categorias (separadas por ;):',self.categories),
                                 ('Pasta de trabalho (Path):',self.workdir),('Executável exigido (TryExec):',self.tryexec)]:
                form.addRow(label, field)
            iconrow = QHBoxLayout(); self.btn_icon=QPushButton('Escolher imagem…')
            iconrow.addWidget(self.btn_icon); iconrow.addStretch(); form.addRow('',iconrow)
            presets = QComboBox()
            presets.addItem('Adicionar categoria…', '')
            for k in ['Utility','Settings','System','Network','WebBrowser','Development','IDE','Graphics','AudioVideo','Video','Audio','Game','Office','FileManager','TerminalEmulator','Education','Science']:
                presets.addItem(k, k)
            self.preset = presets
            form.addRow('Categorias comuns:', self.preset)
            form.addRow('',self.terminal); form.addRow('',self.visible)
            rv.addLayout(form)
            helptext = QLabel('Ocultar um aplicativo do sistema não desinstala o pacote. '
                              'A edição cria uma cópia em ~/.local/share/applications; '
                              'o arquivo original permanece intacto.')
            helptext.setWordWrap(True)
            rv.addWidget(helptext)
            row = QHBoxLayout()
            self.btn_save = QPushButton('Salvar')
            self.btn_hide = QPushButton('Ocultar do menu')
            self.btn_reset = QPushButton('Restaurar original')
            self.btn_delete = QPushButton('Excluir entrada pessoal')
            for b in [self.btn_save,self.btn_hide,self.btn_reset,self.btn_delete]: row.addWidget(b)
            rv.addLayout(row)
            rv.addStretch(1)
            scroll.setWidget(right); splitter.addWidget(scroll)
            splitter.setSizes([350,770])
            self.statusBar().showMessage('Pronto.')
            self.search.textChanged.connect(self.populate)
            self.show_hidden.toggled.connect(self.populate)
            self.listing.currentItemChanged.connect(self.on_select)
            self.btn_new.clicked.connect(self.new)
            self.btn_reload.clicked.connect(self.refresh)
            self.btn_icon.clicked.connect(self.choose_icon)
            self.preset.currentIndexChanged.connect(self.add_category)
            self.btn_save.clicked.connect(self.save)
            self.btn_hide.clicked.connect(self.hide)
            self.btn_reset.clicked.connect(self.reset)
            self.btn_delete.clicked.connect(self.delete)

        def refresh(self, select_id: str | None = None):
            self.entries = self.repo.discover()
            self.populate(select_id)
            self.statusBar().showMessage(f'{len(self.entries)} entradas encontradas. Mudanças pessoais são respaldadas por backup.')

        def populate(self, select_id: str | None = None):
            if isinstance(select_id, bool): select_id = None
            old_id = select_id
            if old_id is None and self.listing.currentItem():
                old_id = self.listing.currentItem().data(Qt.ItemDataRole.UserRole)
            self.listing.blockSignals(True)
            self.listing.clear()
            term = self.search.text().lower().strip()
            for eid, e in sorted(self.entries.items(), key=lambda p: (p[1].name.casefold(),p[0])):
                if e.hidden and not self.show_hidden.isChecked(): continue
                if term not in f'{e.name} {eid} {desktop_get(e.content,"Exec")} {desktop_get(e.content,"Categories")}'.lower(): continue
                label = e.name + ('  [oculto]' if e.hidden else '')
                item = QListWidgetItem(label)
                item.setToolTip(f'{e.origin}\n{e.active_path}')
                item.setData(Qt.ItemDataRole.UserRole, eid)
                ico = desktop_get(e.content,'Icon')
                if ico:
                    qico = QIcon(ico) if ico.startswith('/') else QIcon.fromTheme(ico)
                    if not qico.isNull(): item.setIcon(qico)
                self.listing.addItem(item)
                if eid == old_id: self.listing.setCurrentItem(item)
            self.listing.blockSignals(False)
            if not self.creating:
                selected = self.listing.currentItem()
                self.set_current(self.entries.get(selected.data(Qt.ItemDataRole.UserRole)) if selected else None)

        def set_current(self, entry: Entry | None):
            self.creating = False
            self.current = entry
            if entry is None:
                self.info.setText('Selecione um aplicativo na lista ou clique em Novo aplicativo.')
                self.btn_hide.setEnabled(False); self.btn_reset.setEnabled(False)
                self.btn_delete.setEnabled(False); self.btn_save.setEnabled(False)
                return
            e = entry.content
            self.info.setText(f'{entry.origin}\n{entry.active_path}')
            self.name.setText(entry.name)
            self.exec.setText(desktop_get(e,'Exec'))
            self.comment.setText(desktop_get(e,'Comment[pt_BR]',desktop_get(e,'Comment')))
            self.icon.setText(desktop_get(e,'Icon'))
            self.categories.setText(desktop_get(e,'Categories'))
            self.workdir.setText(desktop_get(e,'Path'))
            self.tryexec.setText(desktop_get(e,'TryExec'))
            self.terminal.setChecked(desktop_get(e,'Terminal').lower()=='true')
            self.visible.setChecked(not entry.hidden)
            self.btn_save.setEnabled(True)
            self.btn_hide.setEnabled(not entry.hidden)
            self.btn_reset.setEnabled(bool(entry.system_path and entry.user_path))
            self.btn_delete.setEnabled(bool(entry.user_path and not entry.system_path))

        def on_select(self, now, _old):
            if now is not None:
                self.set_current(self.entries.get(now.data(Qt.ItemDataRole.UserRole)))

        def new(self):
            self.listing.blockSignals(True); self.listing.setCurrentItem(None); self.listing.blockSignals(False)
            self.current = None; self.creating = True
            self.info.setText('Nova entrada pessoal — será criada em ~/.local/share/applications.')
            for field in [self.name,self.exec,self.comment,self.icon,self.categories,self.workdir,self.tryexec]: field.clear()
            self.categories.setText('Utility;')
            self.icon.setText('application-x-executable')
            self.terminal.setChecked(False); self.visible.setChecked(True)
            self.btn_save.setEnabled(True); self.btn_hide.setEnabled(False)
            self.btn_reset.setEnabled(False); self.btn_delete.setEnabled(False)
            self.name.setFocus()

        def choose_icon(self):
            filename, _ = QFileDialog.getOpenFileName(self,'Selecionar ícone', str(Path.home()), 'Imagens (*.png *.svg *.xpm *.jpg *.jpeg);;Todos (*)')
            if filename: self.icon.setText(filename)

        def add_category(self, i):
            value = self.preset.itemData(i)
            if value:
                cats = [c for c in self.categories.text().split(';') if c]
                if value not in cats: cats.append(value)
                self.categories.setText(';'.join(cats) + ';')
                self.preset.blockSignals(True); self.preset.setCurrentIndex(0); self.preset.blockSignals(False)

        def failure(self, exc): QMessageBox.critical(self,'Não foi possível concluir',str(exc))

        def save(self):
            try:
                target = self.repo.save(self.current if not self.creating else None,
                    name=self.name.text(), command=self.exec.text(), comment=self.comment.text(),
                    icon=self.icon.text(), categories=self.categories.text(), workdir=self.workdir.text(),
                    tryexec=self.tryexec.text(), terminal=self.terminal.isChecked(), visible=self.visible.isChecked())
            except Exception as exc: self.failure(exc); return
            self.creating = False
            self.refresh(desktop_id(target, self.repo.user_dir))
            self.statusBar().showMessage(f'Salvo: {target}')
            QMessageBox.information(self,'Salvo','Entrada salva com segurança em seu perfil.\n\nO menu pode levar alguns segundos para atualizar.')

        def hide(self):
            if not self.current: return
            try: target=self.repo.hide(self.current)
            except Exception as exc: self.failure(exc); return
            self.refresh(desktop_id(target, self.repo.user_dir))
            self.statusBar().showMessage('Entrada ocultada. Aplicativo e pacote permanecem instalados.')

        def reset(self):
            e=self.current
            if not e or not e.user_path or not e.system_path: return
            result=QMessageBox.question(self,'Restaurar original',
               'Remover sua personalização deste lançador e restaurar a versão do sistema?\n\nUma cópia de segurança será mantida.',
               QMessageBox.StandardButton.Yes|QMessageBox.StandardButton.No)
            if result!=QMessageBox.StandardButton.Yes: return
            try: self.repo.delete_local(e)
            except Exception as exc: self.failure(exc); return
            self.refresh(e.entry_id)

        def delete(self):
            e=self.current
            if not e or not e.user_path or e.system_path: return
            result=QMessageBox.question(self,'Excluir entrada pessoal',
               f'Excluir somente seu lançador pessoal "{e.name}"?\n\nO aplicativo em si não será desinstalado. Um backup será criado.',
               QMessageBox.StandardButton.Yes|QMessageBox.StandardButton.No)
            if result!=QMessageBox.StandardButton.Yes: return
            try: self.repo.delete_local(e)
            except Exception as exc: self.failure(exc); return
            self.refresh()

    app=QApplication(sys.argv)
    app.setApplicationName('Wolf Menu Editor')
    app.setDesktopFileName('wolf-menu-editor')
    win=Window(); win.show()
    sys.exit(app.exec())


def main():
    parser=argparse.ArgumentParser(description=f'Wolf Menu Editor {VERSION}')
    parser.add_argument('--self-test', action='store_true', help='testar operações em arquivos temporários')
    parser.add_argument('--check', action='store_true', help='inspecionar dependências sem alterar nada')
    args=parser.parse_args()
    if args.self_test:
        selftest(); return
    if args.check:
        import importlib.util
        print(f'Wolf Menu Editor {VERSION}')
        print(f'PySide6: {"OK" if importlib.util.find_spec("PySide6") else "AUSENTE (sudo pacman -S --needed pyside6)"}')
        r=Repository()
        print('Entradas locais:',r.user_dir)
        print('Entradas de sistema:',', '.join(map(str,r.system_dirs)))
        print('Backups:',r.backup_dir)
        print('Entradas encontradas:',len(r.discover()))
        return
    if os.geteuid() == 0:
        print('[ERRO] Execute o editor como usuário normal, nunca como root.', file=sys.stderr)
        raise SystemExit(2)
    gui()


if __name__ == '__main__':
    main()
