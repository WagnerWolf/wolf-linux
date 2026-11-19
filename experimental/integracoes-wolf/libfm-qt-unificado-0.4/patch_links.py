#!/usr/bin/env python3
"""Cria pacote Wolf libfm-qt 2.4.0-4.2 a partir do build validado 4.1.

Não instala pacotes, não altera a receita existente e não compila nada.
Exige árvore fonte 2.4.0 extraída do build anterior (makepkg -o).
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys

VERSION = '2.4.0'
PREVIOUS = '4.1'
NEXT = '4.2'
SOURCE_DIR_NAME = 'libfm-qt-' + VERSION
PATCH_NAME = 'wolf-symlinks-native.patch'
HELPER = '.local/bin/wolf-symlink-actions'

FILE_ANCHOR = '''        copyAction_ = new QAction(QIcon::fromTheme(QStringLiteral("edit-copy")), tr("Copy"), this);
        connect(copyAction_, &QAction::triggered, this, &FileMenu::onCopyTriggered);
        addAction(copyAction_);
'''

FILE_EXTRA = '''
        // WOLF-SYMLINK-NATIVE: FileMenu is the menu of *selected items*.
        // Do not use clipboard here; source paths come from this selection.
        // Only local files and folders are supported. Never operate in trash:/.
        QStringList wolfSources;
        bool wolfNativeSelection = !files_.empty();
        for(const auto& wolfFile : files_) {
            if(!wolfFile->path().isNative()) {
                wolfNativeSelection = false;
                break;
            }
            const auto wolfPath = wolfFile->path().localPath();
            if(!wolfPath || !*wolfPath.get()) {
                wolfNativeSelection = false;
                break;
            }
            wolfSources << QString::fromUtf8(wolfPath.get());
        }
        const QString wolfHelper = QDir::homePath()
                                   + QStringLiteral("/.local/bin/wolf-symlink-actions");
        if(wolfNativeSelection && !allTrash_ && QFileInfo(wolfHelper).isExecutable()) {
            QAction* wolfSame = addAction(QIcon::fromTheme(QStringLiteral("emblem-symbolic-link")),
                                          QStringLiteral("Criar link simbólico aqui"));
            connect(wolfSame, &QAction::triggered, this, [wolfHelper, wolfSources]() {
                QTimer::singleShot(0, [wolfHelper, wolfSources]() {
                    QStringList args{QStringLiteral("same")};
                    args.append(wolfSources);
                    QProcess::startDetached(wolfHelper, args);
                });
            });
            QAction* wolfChoose = addAction(QIcon::fromTheme(QStringLiteral("folder")),
                                            QStringLiteral("Criar link simbólico em…"));
            connect(wolfChoose, &QAction::triggered, this, [wolfHelper, wolfSources]() {
                QTimer::singleShot(0, [wolfHelper, wolfSources]() {
                    QStringList args{QStringLiteral("choose")};
                    args.append(wolfSources);
                    QProcess::startDetached(wolfHelper, args);
                });
            });
        }
'''

FOLDER_ANCHOR = '''        pasteAction_ = new QAction(QIcon::fromTheme(QStringLiteral("edit-paste")), tr("&Paste"), this);
        addAction(pasteAction_);
        connect(pasteAction_, &QAction::triggered, this, &FolderMenu::onPasteActionTriggered);
'''

FOLDER_EXTRA = '''
        // WOLF-SYMLINK-NATIVE: FolderMenu is shown on *empty folder background*.
        // Read the Ctrl+C clipboard only in this menu; never link this folder.
        const auto wolfFolderPath = view_->path();
        const QString wolfHelper = QDir::homePath()
                                   + QStringLiteral("/.local/bin/wolf-symlink-actions");
        if(wolfFolderPath.isNative() && view_->folderInfo()
           && view_->folderInfo()->isWritable() && QFileInfo(wolfHelper).isExecutable()) {
            const auto wolfPath = wolfFolderPath.localPath();
            if(wolfPath && *wolfPath.get()) {
                const QString wolfDestination = QString::fromUtf8(wolfPath.get());
                QAction* wolfPaste = addAction(QIcon::fromTheme(QStringLiteral("emblem-symbolic-link")),
                                               QStringLiteral("Colar como links simbólicos nesta pasta"));
                connect(wolfPaste, &QAction::triggered, this, [wolfHelper, wolfDestination]() {
                    QTimer::singleShot(0, [wolfHelper, wolfDestination]() {
                        QProcess::startDetached(wolfHelper,
                            QStringList{QStringLiteral("paste-folder"), wolfDestination});
                    });
                });
            }
        }
'''


def one_replace(text: str, anchor: str, addition: str, name: str) -> str:
    if text.count(anchor) != 1:
        raise ValueError(f'{name}: âncora diferente da libfm-qt 2.4.0; não aplicar às cegas')
    if 'WOLF-SYMLINK-NATIVE' in text:
        raise ValueError(f'{name}: patch de symlinks já aplicado')
    return text.replace(anchor, anchor + addition, 1)


def transform_filemenu(src: str) -> str:
    if 'FileMenu::FileMenu(' not in src or 'namespace Fm {' not in src:
        raise ValueError('filemenu.cpp inesperado')
    text = one_replace(src, '#include <QMessageBox>\n',
                       '#include <QDir>\n#include <QFileInfo>\n#include <QProcess>\n#include <QTimer>\n', 'filemenu includes')
    return one_replace(text, FILE_ANCHOR, FILE_EXTRA, 'filemenu contexto')


def transform_foldermenu(src: str) -> str:
    if 'FolderMenu::FolderMenu(' not in src or 'namespace Fm {' not in src:
        raise ValueError('foldermenu.cpp inesperado')
    text = one_replace(src, '#include <QMessageBox>\n',
                       '#include <QDir>\n#include <QFileInfo>\n#include <QProcess>\n#include <QTimer>\n', 'foldermenu includes')
    return one_replace(text, FOLDER_ANCHOR, FOLDER_EXTRA, 'foldermenu contexto')


def create_patch(source_dir: Path) -> str:
    changes = []
    for name, transformer in (('filemenu.cpp', transform_filemenu),
                              ('foldermenu.cpp', transform_foldermenu)):
        file = source_dir / 'src' / name
        if not file.is_file() or file.is_symlink():
            raise ValueError(f'Fonte ausente ou symlink: {file}')
        old = file.read_text(encoding='utf-8')
        new = transformer(old)
        changes.append(''.join(difflib.unified_diff(
            old.splitlines(keepends=True), new.splitlines(keepends=True),
            fromfile='a/src/' + name, tofile='b/src/' + name, n=4)))
    patch = ''.join(changes)
    if not patch:
        raise ValueError('Patch vazio')
    # Validate against source tree, without touching it.
    check = subprocess.run(['patch', '--batch', '-p1', '--dry-run'], input=patch, text=True,
                           cwd=str(source_dir), capture_output=True, timeout=20)
    if check.returncode:
        raise ValueError('patch --dry-run falhou: ' + (check.stdout + check.stderr)[-1200:])
    return patch


def prepare(previous: Path, output: Path, source_dir: Path | None = None) -> Path:
    previous = previous.expanduser().resolve(strict=True)
    output = output.expanduser().absolute()
    if output.exists() or output.is_symlink() or output == previous or previous in output.parents:
        raise ValueError('Saída já existe ou está dentro do build anterior; use pasta nova')
    if output in previous.parents:
        raise ValueError('Não use um diretório ancestral como saída')
    recipe_path = previous / 'PKGBUILD'
    if not recipe_path.is_file() or recipe_path.is_symlink():
        raise ValueError('PKGBUILD antigo ausente')
    recipe = recipe_path.read_text(encoding='utf-8')
    if not re.search(r'(?m)^pkgname=libfm-qt\s*$', recipe):
        raise ValueError('Pacote não é libfm-qt')
    if not re.search(r'(?m)^pkgver=2\.4\.0\s*$', recipe):
        raise ValueError('Versão upstream diferente de 2.4.0')
    if not re.search(r'(?m)^pkgrel=4\.1\s*$', recipe):
        raise ValueError('É necessário usar a receita Wolf 2.4.0-4.1 já validada')
    if 'wolf-places-usb.patch' not in recipe or 'WOLF-EXPERIMENTAL' not in recipe:
        raise ValueError('Patch USB Wolf não encontrado na receita; preservar a personalização anterior')
    if PATCH_NAME in recipe:
        raise ValueError('Patch de symlinks já referenciado')
    pat = r'(?m)^(\s*)patch --forward -Np1 -i "\$srcdir/wolf-places-usb\.patch"\s*$'
    matches = list(re.finditer(pat, recipe))
    if len(matches) != 1:
        raise ValueError('prepare(): não foi encontrada uma única chamada do patch USB')
    src = (source_dir or (previous / 'src' / SOURCE_DIR_NAME)).expanduser().resolve(strict=True)
    if src.name != SOURCE_DIR_NAME:
        raise ValueError(f'A fonte deve ser uma pasta {SOURCE_DIR_NAME}')
    # Require the previous patch already applied to the old build sources, if available.
    places = src / 'src' / 'placesview.cpp'
    if not places.is_file() or 'Wolf Linux experimental: somente indica' not in places.read_text(encoding='utf-8'):
        raise ValueError('Não achei o patch USB na árvore de fontes; use a fonte do build Wolf 4.1, após makepkg -o')
    patch = create_patch(src)
    digest = hashlib.sha512(patch.encode('utf-8')).hexdigest()
    updated = re.sub(r'(?m)^pkgrel=4\.1\s*$', 'pkgrel=4.2', recipe, count=1)
    line = matches[0].group(0).rstrip()
    updated = updated.replace(line, line + '\n' + matches[0].group(1) +
                              f'patch --forward -Np1 -i "$srcdir/{PATCH_NAME}"', 1)
    updated += f'\n# WOLF-SYMLINK-NATIVE: contexto real selecionado x fundo da pasta\nsource+=("{PATCH_NAME}")\nsha512sums+=("{digest}")\n'
    output.mkdir(parents=True)
    skip_ext = ('.pkg.tar.zst', '.pkg.tar.xz', '.tar.xz', '.tar.gz', '.log')
    for child in previous.iterdir():
        if child.name in ('src', 'pkg', '.git', 'PKGBUILD', '.SRCINFO') or child.name.endswith(skip_ext):
            continue
        if child.is_symlink():
            raise ValueError(f'Recusa copiar link simbólico inesperado: {child}')
        if child.is_file():
            shutil.copy2(child, output / child.name)
        elif child.name == 'keys' and child.is_dir():
            shutil.copytree(child, output / child.name)
    if not (output / 'wolf-places-usb.patch').is_file():
        raise ValueError('Arquivo USB não copiado: repita com a receita 4.1 completa')
    (output / 'PKGBUILD').write_text(updated, encoding='utf-8')
    (output / PATCH_NAME).write_text(patch, encoding='utf-8')
    (output / 'WOLF-SYMLINK-BUILD.txt').write_text(
        'Wolf libfm-qt 2.4.0-4.2 preview — mantém patch formatador USB.\n'
        'Gerado sem compilar ou instalar. Validar em VM antes de atualizar sistema físico.\n'
        'Compilação local: makepkg -s\n'
        'Instalação manual depois de validar: sudo pacman -U libfm-qt-2.4.0-4.2-x86_64.pkg.tar.zst\n'
        'Rollback: sudo pacman -U <caminho>/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst\n'
        'Para usar o menu novo, instalar helper e desativar ações desktop legadas.\n',
        encoding='utf-8')
    return output


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--anterior', required=True, type=Path, help='Build Wolf 2.4.0-4.1 (contém PKGBUILD e src/)')
    p.add_argument('--saida', required=True, type=Path, help='Pasta NOVA do build 2.4.0-4.2')
    p.add_argument('--fonte', type=Path, help='Fonte extraída 2.4.0, já com patch USB aplicado')
    a = p.parse_args()
    try:
        out = prepare(a.anterior, a.saida, a.fonte)
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        p.exit(2, f'[BLOQUEADO] {exc}\n')
    print('[OK] Receita 2.4.0-4.2 preparada:', out)
    print('[OK] Patch USB anterior mantido e novo patch conferido com --dry-run.')
    print('[IMPORTANTE] Pacote AINDA NÃO compilado nem validado no hardware.')

if __name__ == '__main__':
    main()
