#!/usr/bin/env python3
"""Wolf Linux 2.2.0: diagnosticar/reparar integração do PCManFM-Qt com LXQt Archiver.

Não instala pacotes e não altera configurações fora do perfil pcmanfm-qt/lxqt.
Execute sem sudo. Alterações com backup e escrita atômica.
"""
import argparse
from datetime import datetime
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile

HOME = Path.home()
SETTINGS = HOME / '.config/pcmanfm-qt/lxqt/settings.conf'
BACKUPS = HOME / 'wolf-backups/pcmanfm-qt-archiver'
TARGET = 'lxqt-archiver'


def keys(raw):
    section = None
    values = []
    for line in raw.splitlines():
        header = re.match(r'^\s*\[([^\]]+)\]\s*$', line)
        if header:
            section = header.group(1)
        elif section == 'System':
            m = re.match(r'^\s*Archiver\s*=\s*(.*?)\s*$', line)
            if m:
                values.append(m.group(1))
    return values


def repair(raw):
    newline = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.splitlines(keepends=True)
    section = None
    seen = False
    inserted = False
    result = []
    for line in lines:
        m = re.match(r'^\s*\[([^\]]+)\]\s*$', line.rstrip('\r\n'))
        if m:
            if section == 'System' and not inserted:
                result.append(f'Archiver={TARGET}{newline}')
                inserted = True
            section = m.group(1)
            if section == 'System':
                seen = True
            result.append(line)
            continue
        if section == 'System' and re.match(r'^\s*Archiver\s*=', line):
            if not inserted:
                result.append(f'Archiver={TARGET}{newline}')
                inserted = True
            # Descarta chaves duplicadas para evitar valores divergentes no Qt.
            continue
        result.append(line)
    if section == 'System' and not inserted:
        result.append(f'Archiver={TARGET}{newline}')
    if not seen:
        if result and not result[-1].endswith(('\n', '\r')):
            result.append(newline)
        result.append(f'[System]{newline}Archiver={TARGET}{newline}')
    return ''.join(result)


def qt_value():
    try:
        from PySide6.QtCore import QSettings
        qt = QSettings(str(SETTINGS), QSettings.IniFormat)
        return qt.value('System/Archiver'), str(qt.status())
    except ImportError:
        return None, 'PySide6 não disponível no ambiente de diagnóstico'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--check', action='store_true', help='Somente diagnóstico')
    group.add_argument('--apply', action='store_true', help='Backup e configuração do Archiver')
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error('execute como usuário normal, sem sudo')
    if SETTINGS.is_symlink():
        parser.error('settings.conf é um link simbólico; não será modificado')
    executable = shutil.which(TARGET)
    raw = SETTINGS.read_text(encoding='utf-8') if SETTINGS.is_file() else ''
    found = keys(raw)
    print('[WOLF] Arquivo:', SETTINGS)
    print('[WOLF] Integração configurada:', found or '(não definida)')
    print('[WOLF] Executável lxqt-archiver:', executable or 'AUSENTE')
    qt, status = qt_value()
    print('[QT] System/Archiver:', qt, '|', status)
    if args.check:
        print('[INFO] Diagnóstico somente leitura.')
        return 0 if found == [TARGET] and executable and (qt is None or qt == TARGET) else 2
    if not executable:
        print('[ERRO] lxqt-archiver não está instalado. Instale o pacote oficial antes de aplicar.')
        return 2
    updated = repair(raw)
    if updated == raw:
        print('[OK] Integração textual já correta; nenhuma alteração.')
        print('[INFO] Se o menu não funcionar, confira as preferências e reinicie a sessão LXQt.')
        return 0
    if SETTINGS.exists() and not SETTINGS.is_file():
        print('[ERRO] settings.conf não é um arquivo regular.')
        return 2
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup_dir = BACKUPS / stamp
    backup_dir.mkdir(parents=True, exist_ok=False)
    if SETTINGS.is_file():
        shutil.copy2(SETTINGS, backup_dir / 'settings.conf')
    else:
        (backup_dir / 'original-ausente.txt').write_text('settings.conf não existia\n', encoding='utf-8')
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.settings.conf.wolf-', dir=SETTINGS.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='') as f:
            f.write(updated)
            f.flush()
            os.fsync(f.fileno())
        if SETTINGS.is_file():
            os.chmod(temporary, stat.S_IMODE(SETTINGS.stat().st_mode))
        else:
            os.chmod(temporary, 0o600)
        os.replace(temporary, SETTINGS)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('[OK] Archiver=lxqt-archiver aplicado.')
    print('[BACKUP]', backup_dir)
    print('[INFO] Feche o PCManFM-Qt e inicie nova sessão LXQt antes de testar.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
