#!/usr/bin/env python3
"""Migra pastas XDG padrão para pt_BR, sob comando explícito do usuário.

Prévia por padrão; --migrate transfere somente entradas sem colisão, preserva
caminhos personalizados e realiza backup de configurações. Não usa sudo.
"""
from __future__ import annotations
import argparse
from datetime import datetime
from pathlib import Path
import re
import shutil
from urllib.parse import unquote, urlparse

NAMES = {
    'DESKTOP': ('Desktop', 'Área de Trabalho'),
    'DOWNLOAD': ('Downloads', 'Downloads'),
    'TEMPLATES': ('Templates', 'Modelos'),
    'PUBLICSHARE': ('Public', 'Público'),
    'DOCUMENTS': ('Documents', 'Documentos'),
    'MUSIC': ('Music', 'Músicas'),
    'PICTURES': ('Pictures', 'Imagens'),
    'VIDEOS': ('Videos', 'Vídeos'),
}
FAVORITES = [('DOCUMENTS','Documentos'),('DOWNLOAD','Downloads'),
             ('PICTURES','Imagens'),('MUSIC','Músicas'),('VIDEOS','Vídeos')]
PAT = re.compile(r'^(XDG_(?:DESKTOP|DOWNLOAD|TEMPLATES|PUBLICSHARE|DOCUMENTS|MUSIC|PICTURES|VIDEOS)_DIR)="(.*)"$')


def migrate(home: Path, *, apply=False) -> list[str]:
    home = home.resolve()
    cfg = home / '.config/user-dirs.dirs'
    locale = home / '.config/user-dirs.locale'
    bookmarks = home / '.config/gtk-3.0/bookmarks'
    for file in (cfg,locale,bookmarks):
        if file.is_symlink():
            raise RuntimeError(f'Configuração é link simbólico: {file}')
    original = cfg.read_text(encoding='utf-8') if cfg.is_file() else ''
    lines = original.splitlines()
    found = {m.group(1):m.group(2) for line in lines if (m:=PAT.fullmatch(line))}
    changes = {}
    operations = []
    actions = []
    blocked = set()
    pending_names = []
    for kind, (english, portuguese) in NAMES.items():
        key = f'XDG_{kind}_DIR'
        current = found.get(key)
        if current not in (None, f'$HOME/{english}', f'$HOME/{portuguese}'):
            actions.append(f'[PRESERVADO] {kind}: caminho personalizado ({current})')
            continue
        old, new = home / english, home / portuguese
        if old.is_symlink() or new.is_symlink():
            actions.append(f'[PRESERVADO] {kind}: link simbólico; verificação manual')
            blocked.add(kind)
            continue
        if old.exists() and not old.is_dir():
            actions.append(f'[PRESERVADO] {kind}: origem não é pasta: {old}')
            blocked.add(kind)
            continue
        if new.exists() and not new.is_dir():
            actions.append(f'[PRESERVADO] {kind}: destino não é pasta: {new}')
            blocked.add(kind)
            continue
        if old != new and old.is_dir():
            if not new.exists():
                operations.append(('rename', old, new))
                actions.append(f'[RENOMEAR] {old.name} → {new.name}')
            else:
                # Uma pasta de destino vazia pode já ter sido criada pelo LXQt.
                # Transferir somente arquivos sem nome conflitante.
                # Mesclar recursivamente subpastas homônimas, sem substituir
                # arquivos; o caso comum é Pictures/Capturas de tela já existir
                # também em Imagens/Capturas de tela.
                def plan(src, dst):
                    if dst.is_symlink() or (src.is_symlink() and dst.exists()):
                        pending_names.append(f'{src.relative_to(old)} (link simbólico)')
                        return
                    if not dst.exists() and not dst.is_symlink():
                        operations.append(('move', src, dst))
                    elif src.is_dir() and dst.is_dir() and not src.is_symlink():
                        for child in sorted(src.iterdir()):
                            plan(child, dst / child.name)
                    else:
                        pending_names.append(str(src.relative_to(old)))
                before = len(operations)
                before_pending = len(pending_names)
                for entry in sorted(old.iterdir()):
                    plan(entry, new / entry.name)
                actions.append(f'[UNIR SEM SOBRESCREVER] {old.name} → {new.name} '
                               f'({len(operations)-before} movimentação(ões) prevista(s))')
                if len(pending_names) > before_pending:
                    pending = pending_names[before_pending:]
                    actions.append(f'[PENDENTE] {kind}: itens com colisão: '
                                   + ', '.join(pending[:8]) + ('...' if len(pending)>8 else ''))
                    blocked.add(kind)
                    continue
        changes[key] = f'$HOME/{portuguese}'
        actions.append(f'[CONFIGURAR] {kind}: {portuguese}')
    if not apply:
        return actions or ['[OK] Nenhuma alteração necessária.']

    # A validação de colisões terminou antes da primeira movimentação.
    backup = home / 'wolf-backups/xdg-ptbr' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True, exist_ok=False)
    for file in (cfg,locale,bookmarks):
        if file.is_file(): shutil.copy2(file, backup / file.name)
    movements = []
    for kind, old, new in operations:
        new.parent.mkdir(parents=True, exist_ok=True)
        if new.exists() or new.is_symlink():
            raise RuntimeError(f'Operação interrompida: destino criado durante migração: {new}')
        old.rename(new)
        movements.append(f'{old} -> {new}')
    for kind, (_, portuguese) in NAMES.items():
        key = f'XDG_{kind}_DIR'
        if key in changes and kind not in blocked:
            target = home / portuguese
            target.mkdir(parents=True, exist_ok=True)
    result = []
    remaining = dict(changes)
    for line in lines:
        match = PAT.fullmatch(line)
        if match and match.group(1) in remaining:
            result.append(f'{match.group(1)}="{remaining.pop(match.group(1))}"')
        else:
            result.append(line)
    result.extend(f'{key}="{value}"' for key, value in remaining.items())
    cfg.parent.mkdir(parents=True, exist_ok=True)
    tmp = cfg.with_name(cfg.name + '.wolf-temp')
    tmp.write_text('\n'.join(result)+'\n', encoding='utf-8')
    tmp.replace(cfg)
    locale.write_text('pt_BR\n', encoding='utf-8')

    # Favoritos PCManFM-Qt (formato GTK bookmarks): atualizar nomes migrados,
    # sem apagar favoritos pessoais de volumes externos.
    old_urls = {(home / eng).as_uri() for kind,(eng,pt) in NAMES.items()
                if kind not in blocked and eng != pt}
    active = dict(changes)
    bookmarks_original = bookmarks.read_text(encoding='utf-8').splitlines() if bookmarks.is_file() else []
    custom = []
    for line in bookmarks_original:
        uri = line.split(' ',1)[0]
        if uri not in old_urls and line not in custom:
            custom.append(line)
    new_lines = []
    for kind,label in FAVORITES:
        key=f'XDG_{kind}_DIR'
        # Respeita caminhos personalizados, inclusive fora do HOME.
        raw = found.get(key)
        if key in active:
            raw = active[key]
        if raw and raw.startswith('$HOME/'):
            path = home / raw.removeprefix('$HOME/')
            uri = path.as_uri()
            if uri not in [l.split(' ',1)[0] for l in new_lines]:
                new_lines.append(f'{uri} {label}')
    known = {line.split(' ',1)[0] for line in new_lines}
    new_lines += [line for line in custom if line.split(' ',1)[0] not in known]
    bookmarks.parent.mkdir(parents=True, exist_ok=True)
    bookmarks.write_text('\n'.join(new_lines)+('\n' if new_lines else ''),encoding='utf-8')
    (backup / 'movimentos.txt').write_text('\n'.join(movements)+'\n',encoding='utf-8')
    actions.append(f'[BACKUP] {backup}')
    if blocked:
        actions.append('[ATENÇÃO] Migração parcial: há itens com conflito; arquivos preservados '
                       'e a pasta XDG com conflito permanece apontando para a origem. '
                       'Revise as pendências e execute novamente.')
    else:
        actions.append('[OK] Todas as pastas XDG padrão elegíveis foram migradas.')
    return actions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--migrate', action='store_true', help='Aplicar migração com backup; padrão é prévia')
    args=parser.parse_args()
    try:
        messages = migrate(Path.home(), apply=args.migrate)
        print('\n'.join(messages))
        if args.migrate and any(line.startswith('[ATENÇÃO]') for line in messages):
            parser.exit(2, '[PENDENTE] Migração parcial: revise os arquivos com nomes repetidos.\n')
    except (OSError, RuntimeError, ValueError) as exc:
        parser.exit(1, f'[ERRO] Migração interrompida: {exc}\n')

if __name__=='__main__': main()
