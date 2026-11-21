#!/usr/bin/env python3
"""Verifica distribuicao opt-in do utilitario de suspensao no KDE (sem executar)."""
from pathlib import Path
import sys
import subprocess

root = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
installer = (root/'install/wolf-install.sh').read_text(encoding='utf-8')
helper = root/'tools/stable/wolf-sem-suspensao.sh'
prep = (root/'preparar_ambiente_wolf_linux.sh').read_text(encoding='utf-8')
gen = (root/'gerar-iso.sh').read_text(encoding='utf-8')
assert helper.is_file() and helper.stat().st_mode & 0o111, 'Helper ausente ou nao executavel'
assert subprocess.run(['bash','-n',str(helper)],capture_output=True).returncode==0, 'Sintaxe do helper'
assert 'AllowSuspend=no' in helper.read_text() and 'AllowHibernation=no' in helper.read_text()
assert '--undo' in helper.read_text() and '--status' in helper.read_text()
assert 'WOLF_IMAGE=\'/usr/share/backgrounds/wolf-linux/wallpaper.png\'' in helper.read_text()
assert 'ln -sfn ../lib/wolf-linux/helpers/stable/wolf-sem-suspensao.sh /mnt/usr/local/bin/wolf-sem-suspensao' in installer
assert '/mnt/usr/share/applications/wolf-sem-suspensao.desktop' in installer
assert 'OnlyShowIn=KDE;' in installer
assert 'Exec=konsole --hold -e /usr/local/bin/wolf-sem-suspensao --apply' in installer
assert 'Exec=konsole --hold -e /usr/local/bin/wolf-sem-suspensao --undo' in installer
assert 'Exec=konsole --hold -e /usr/local/bin/wolf-sem-suspensao --status' in installer
assert 'wolf-sem-suspensao --apply' not in prep and 'wolf-sem-suspensao --apply' not in gen
assert 'wolf-linux-2.3.1' in prep and 'wolf-linux-2.3.1' in gen
assert 'wolf-linux-iso-project=2.3.1' in prep
assert 'wolf-linux-iso-project=2.3.1' in gen
assert (root/'assets/wallpapers/wolf-linux-wallpaper.png').is_file()
print('[OK] Suspensão opcional: instalador só oferece atalho, não executa fix; restauração e wallpaper presentes.')
