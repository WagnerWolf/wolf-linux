#!/usr/bin/env python3
"""Repara somente autostart Wolf legado do Picom. Sem sudo, com backup."""
from pathlib import Path
from datetime import datetime
import hashlib
import os
import shutil
import subprocess
import sys

HOME = Path.home()
AUTO = HOME/'.config/autostart/wolf-picom.desktop'
HELPER = HOME/'.local/bin/wolf-picom-session'
MARKER = '# Wolf Linux - Picom VM guard v1'
OLD = '''[Desktop Entry]
Type=Application
Name=Wolf - Composição Picom (LXQt/X11)
Comment=Composição GLX/VSync para Steam, sem efeitos adicionais
Exec=picom
TryExec=picom
OnlyShowIn=LXQt;
NoDisplay=true
X-LXQt-Need-Tray=false
'''

def main():
    if os.geteuid() == 0:
        raise RuntimeError('Execute como usuário normal, sem sudo.')
    source = Path(__file__).resolve().parents[2]/'tools/lxqt/wolf-picom-session.sh'
    if not source.is_file():
        source = Path(__file__).with_name('wolf-picom-session.sh')
    if not source.is_file() or source.is_symlink() or MARKER not in source.read_text(encoding='utf-8'):
        raise RuntimeError('Fonte do guard VM não encontrada ou inesperada.')
    if not AUTO.is_file() or AUTO.is_symlink():
        raise RuntimeError('Autostart Wolf regular ausente: '+str(AUTO))
    if HELPER.is_symlink() or (HELPER.exists() and not HELPER.is_file()):
        raise RuntimeError('Launcher é link ou não é arquivo regular: '+str(HELPER))
    old = AUTO.read_text(encoding='utf-8')
    expected = OLD.replace('Comment=Composição GLX/VSync para Steam, sem efeitos adicionais',
                           'Comment=Compositor GLX no físico, desativado por padrão em VMs')
    expected = expected.replace('\nExec=picom\n', f'\nExec={HELPER}\n')
    if old == expected and HELPER.is_file() and MARKER in HELPER.read_text(encoding='utf-8'):
        print('[OK] Guard VM já instalado.'); return
    if old != OLD:
        raise RuntimeError('Autostart foi personalizado/desabilitado, preservado sem alteração.')
    if HELPER.is_file() and MARKER not in HELPER.read_text(encoding='utf-8'):
        raise RuntimeError('Launcher existente não pertence ao Wolf; preservado.')
    backup = HOME/'wolf-backups/picom-vm'/datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True, exist_ok=False)
    shutil.copy2(AUTO, backup/'wolf-picom.desktop')
    if HELPER.is_file():
        shutil.copy2(HELPER, backup/'wolf-picom-session')
    HELPER.parent.mkdir(parents=True,exist_ok=True)
    tmp_helper = HELPER.with_name(HELPER.name+'.wolf-new')
    tmp_auto = AUTO.with_name(AUTO.name+'.wolf-new')
    try:
        shutil.copy2(source,tmp_helper)
        tmp_helper.chmod(0o755)
        tmp_auto.write_text(expected,encoding='utf-8')
        tmp_auto.chmod(0o644)
        os.replace(tmp_helper,HELPER)
        os.replace(tmp_auto,AUTO)
    finally:
        tmp_helper.unlink(missing_ok=True)
        tmp_auto.unlink(missing_ok=True)
    print('[OK] Autostart Wolf migrado para seleção segura do Picom.')
    print('[BACKUP]',backup)
    print('[STATUS]')
    subprocess.run([str(HELPER),'--status'],check=False)
    print('[PRÓXIMO PASSO] killall picom 2>/dev/null || true; saia e entre na sessão LXQt.')

if __name__ == '__main__':
    try: main()
    except (RuntimeError,OSError,UnicodeError) as exc:
        print('[BLOQUEADO]',exc,file=sys.stderr)
        raise SystemExit(2)
