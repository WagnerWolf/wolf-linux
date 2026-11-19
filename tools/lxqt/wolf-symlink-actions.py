#!/usr/bin/env python3
"""Wolf Linux symlink backend, called by native libfm-qt menu actions."""
import os
import sys
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse


def _is_item(path: Path) -> bool:
    return os.path.lexists(path)


def create_links(sources, dest_dir):
    """Create relative symlinks without overwriting existing files.

    Returns (created_paths, [(source, error), ...]).
    """
    dest = Path(dest_dir).absolute()
    if not dest.is_dir():
        raise NotADirectoryError(f"A pasta de destino não existe: {dest}")
    created, errors, seen = [], [], set()
    for source in sources:
        src = Path(source).absolute()
        if str(src) in seen:
            continue
        seen.add(str(src))
        if not _is_item(src):
            errors.append((str(src), "O item de origem não existe."))
            continue
        stem = src.name
        if not stem:
            errors.append((str(src), "Nome inválido."))
            continue
        target = dest / stem
        if _is_item(target):
            target = dest / f"{stem} - link"
        counter = 2
        while _is_item(target):
            target = dest / f"{stem} - link ({counter})"
            counter += 1
        try:
            # A link to a symlink refers to the symlink path, not its dereferenced target.
            target.symlink_to(os.path.relpath(str(src), str(dest)), target_is_directory=src.is_dir())
            created.append(target)
        except OSError as exc:
            errors.append((str(src), str(exc)))
    return created, errors


def _paths_from_uri_text(raw: str):
    paths = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith('#') or line in ('copy', 'cut'):
            continue
        u = urlparse(line)
        if u.scheme != 'file' or u.netloc not in ('', 'localhost'):
            continue
        paths.append(unquote(u.path))
    return paths


def _clipboard_paths():
    from PySide6.QtWidgets import QApplication
    from PySide6.QtCore import QUrl
    app = QApplication.instance() or QApplication(sys.argv[:1])
    clipboard = app.clipboard().mimeData()
    if clipboard is None:
        return []
    if clipboard.hasUrls():
        return [u.toLocalFile() for u in clipboard.urls() if u.isLocalFile() and u.toLocalFile()]
    for kind in ('x-special/gnome-copied-files', 'text/uri-list'):
        if clipboard.hasFormat(kind):
            return _paths_from_uri_text(bytes(clipboard.data(kind)).decode('utf-8', 'replace'))
    return []


def _message(title, body, error=False):
    try:
        from PySide6.QtWidgets import QApplication, QMessageBox
        app = QApplication.instance() or QApplication(sys.argv[:1])
        if error:
            QMessageBox.warning(None, title, body)
        elif os.environ.get('WOLF_LINK_SHOW_SUCCESS') == '1':
            QMessageBox.information(None, title, body)
        else:
            pass  # Sucesso é silencioso por padrão.
    except Exception:
        print(f"{title}: {body}", file=sys.stderr)


def main(argv=None):
    args = list(argv if argv is not None else sys.argv[1:])
    if len(args) < 2 or args[0] not in ('same', 'choose', 'paste-folder'):
        print('Uso: wolf-symlink-actions {same|choose|paste-folder} CAMINHO...', file=sys.stderr)
        return 2
    mode, values = args[0], args[1:]
    if mode == 'same':
        created, errors = [], []
        # Per-source dirname: selections may be from more than one directory.
        for path in values:
            a, b = create_links([path], str(Path(path).absolute().parent))
            created.extend(a)
            errors.extend(b)
    elif mode == 'choose':
        try:
            from PySide6.QtWidgets import QApplication, QFileDialog
            app = QApplication.instance() or QApplication(sys.argv[:1])
            dest = QFileDialog.getExistingDirectory(None, 'Onde criar os links simbólicos?', str(Path.home()))
        except ImportError:
            print('PySide6 não está instalado.', file=sys.stderr)
            return 3
        if not dest:
            return 0  # Cancelled without changes
        created, errors = create_links(values, dest)
    else:
        if len(values) != 1:
            print('Informe uma pasta de destino.', file=sys.stderr)
            return 2
        try:
            from PySide6.QtWidgets import QApplication
            app = QApplication.instance() or QApplication(sys.argv[:1])
            sources = _clipboard_paths()
        except ImportError:
            print('PySide6 não está instalado.', file=sys.stderr)
            return 3
        if not sources:
            _message('Links simbólicos', 'Copie arquivos ou pastas no PCManFM-Qt (Ctrl+C) antes de colar como link.', True)
            return 1
        created, errors = create_links(sources, values[0])
    if errors:
        _message('Falha ao criar alguns links', '\n'.join(f'{p}: {msg}' for p, msg in errors[:10]), True)
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
