#!/usr/bin/env python3
"""Wolf LXQt: ajuste conservador do fundo do painel + teste Picom.

Modifica SOMENTE o QSS do painel Wolf e a configuração/autostart do Picom.
--apply não ativa o compositor; --enable ativa no próximo login após teste visual.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime

HOME = Path.home()
THEME = HOME / '.local/share/lxqt/themes/wolf-dark/lxqt-panel.qss'
CONFIG = HOME / '.config/picom/picom.conf'
AUTO = HOME / '.config/autostart/wolf-picom.desktop'
BACKUPS = HOME / 'wolf-backups/picom-lxqt'
MARKER = '/* Wolf Picom: fundo opaco dos painéis LXQt */'
PICOM_MARKER = '# Wolf Linux - Picom X11 (perfil conservador)'
CSS = '''/* Wolf Picom: fundo opaco dos painéis LXQt */
LXQtPanel #BackgroundWidget {
    background: #242a34;
}
'''
PICOM_CONF = '''# Wolf Linux - Picom X11 (perfil conservador)
backend = "glx";
vsync = true;
shadow = false;
fading = false;
active-opacity = 1.0;
inactive-opacity = 1.0;
frame-opacity = 1.0;
unredir-if-possible = false;
'''
AUTOSTART = '''[Desktop Entry]
Type=Application
Name=Wolf - Composição Picom (LXQt/X11)
Comment=Composição GLX/VSync para Steam, sem efeitos adicionais
Exec=picom
TryExec=picom
OnlyShowIn=LXQt;
NoDisplay=true
X-LXQt-Need-Tray=false
'''

def ensure_safe(p):
    if not p.is_relative_to(HOME):
        raise RuntimeError('Caminho fora do HOME: '+str(p))
    if p.is_symlink():
        raise RuntimeError('Link simbólico não será alterado: '+str(p))
    if p.exists() and not p.is_file():
        raise RuntimeError('Não é arquivo regular: '+str(p))

def digest(b):
    return hashlib.sha256(b).hexdigest()

def write_file(p, content):
    ensure_safe(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    temp=p.with_name(p.name+'.wolf-tmp')
    temp.write_bytes(content)
    temp.replace(p)

def record_backup(paths):
    stamp=datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    directory=BACKUPS/stamp
    directory.mkdir(parents=True, exist_ok=False)
    entries=[]
    for p in paths:
        ensure_safe(p)
        before=p.read_bytes() if p.exists() else None
        relative=p.relative_to(HOME)
        if before is not None:
            target=directory/'original'/relative
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(before)
        entries.append({'path': str(relative),'existed': before is not None,
                        'original_sha256': digest(before) if before is not None else None})
    return directory,entries

def commit_backup(directory,entries):
    for item in entries:
        path=HOME/item['path']
        item['installed_sha256']=digest(path.read_bytes()) if path.exists() else None
    (directory/'manifest.json').write_text(json.dumps(entries,indent=2,ensure_ascii=False),encoding='utf-8')
    history=BACKUPS/'history.txt'
    with history.open('a',encoding='utf-8') as out:
        out.write(str(directory)+'\n')

def patch_theme(original):
    text=original.decode('utf-8')
    if MARKER in text:
        return original
    return (CSS+'\n'+text).encode('utf-8')

def check():
    print('Tema Wolf:', 'encontrado' if THEME.is_file() else 'ausente',THEME)
    print('Fundo opaco Wolf:', THEME.is_file() and MARKER in THEME.read_text(encoding='utf-8',errors='replace'))
    print('Picom:', shutil.which('picom') or 'ausente')
    print('Configuração Picom:', CONFIG if CONFIG.is_file() else 'ausente')
    print('Autostart Wolf:', AUTO if AUTO.is_file() else 'desativado')
    if AUTO.is_file(): print('Autostart conteúdo Wolf:', 'Name=Wolf - Composição Picom' in AUTO.read_text())
    try:
        p=subprocess.run(['pgrep','-a','-u',str(os.getuid()),'-x','picom'],capture_output=True,text=True)
        if p.stdout.strip():print('Picom em execução:',p.stdout.strip())
        else:print('Picom não está em execução')
    except FileNotFoundError:
        pass

def apply():
    if not THEME.is_file():
        raise RuntimeError('Tema Wolf-dark ausente: '+str(THEME)+' (reaplique Wolf-dark no Control Center).')
    ensure_safe(THEME)
    ensure_safe(CONFIG)
    if CONFIG.is_file() and PICOM_MARKER not in CONFIG.read_text(encoding='utf-8',errors='replace'):
        raise RuntimeError('Configuração Picom pessoal já existe, mas não é a Wolf: '+str(CONFIG)+'; não será sobrescrita.')
    directory, entries=record_backup([THEME,CONFIG])
    write_file(THEME,patch_theme(THEME.read_bytes()))
    write_file(CONFIG,PICOM_CONF.encode())
    commit_backup(directory,entries)
    print('[OK] Fundo opaco e perfil Picom escritos. Backup:',directory)
    print('[INFO] Picom NÃO foi ativado automaticamente. Reinicie o lxqt-panel ou a sessão para atualizar o tema.')
    print('[TESTE] Se Picom não estiver em execução: picom --config "$HOME/.config/picom/picom.conf"')
    print('[INFO] Após validar os painéis e Steam, use --enable para iniciar Picom no próximo login.')

def enable():
    if not THEME.is_file() or MARKER not in THEME.read_text(encoding='utf-8'):
        raise RuntimeError('Aplique primeiro --apply para corrigir o fundo do painel.')
    if not CONFIG.is_file() or PICOM_MARKER not in CONFIG.read_text(encoding='utf-8'):
        raise RuntimeError('Configuração Wolf do Picom não encontrada.')
    if not shutil.which('picom'):
        raise RuntimeError('Picom não instalado (pacote picom).')
    ensure_safe(AUTO)
    if AUTO.is_file() and 'Name=Wolf - Composição Picom' not in AUTO.read_text(encoding='utf-8',errors='replace'):
        raise RuntimeError('Há um autostart com este nome não criado pelo Wolf. Preservado: '+str(AUTO))
    directory, entries=record_backup([AUTO])
    write_file(AUTO,AUTOSTART.encode())
    commit_backup(directory,entries)
    print('[OK] Autostart Wolf Picom ativado para a próxima sessão LXQt. Backup:',directory)

def disable():
    if not AUTO.is_file():
        print('[INFO] Autostart Wolf não existe.'); return
    ensure_safe(AUTO)
    if 'Name=Wolf - Composição Picom' not in AUTO.read_text(encoding='utf-8',errors='replace'):
        raise RuntimeError('Autostart estranho ao Wolf, não será removido.')
    directory, entries=record_backup([AUTO])
    AUTO.unlink()
    commit_backup(directory,entries)
    print('[OK] Autostart Wolf removido. Se Picom está executando, encerre-o manualmente. Backup:',directory)

def undo():
    history=BACKUPS/'history.txt'
    if not history.is_file():
        raise RuntimeError('Nenhum backup Wolf Picom encontrado.')
    lines=[x for x in history.read_text(encoding='utf-8').splitlines() if x.strip()]
    if not lines:
        raise RuntimeError('Histórico de backups vazio.')
    directory=Path(lines[-1])
    if not directory.is_relative_to(BACKUPS) or not (directory/'manifest.json').is_file():
        raise RuntimeError('Manifesto de backup inválido.')
    entries=json.loads((directory/'manifest.json').read_text(encoding='utf-8'))
    for entry in entries:
        p=HOME/entry['path']; ensure_safe(p)
        now=digest(p.read_bytes()) if p.is_file() else None
        if now!=entry['installed_sha256']:
            raise RuntimeError('Arquivo mudou desde a aplicação, cancelando restauração: '+str(p))
    for entry in entries:
        p=HOME/entry['path']
        if entry['existed']:
            write_file(p,(directory/'original'/entry['path']).read_bytes())
        elif p.exists():p.unlink()
    if len(lines)>1:
        history.write_text('\n'.join(lines[:-1])+'\n',encoding='utf-8')
    else:
        history.unlink()
    print('[OK] Última operação revertida a partir de',directory)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    mx=ap.add_mutually_exclusive_group(required=True)
    for option in ('check','apply','enable','disable','undo'):
        mx.add_argument('--'+option, action='store_true')
    args=ap.parse_args()
    if os.geteuid()==0:
        ap.error('Execute como usuário normal, sem sudo.')
    if args.check:check()
    elif args.apply:apply()
    elif args.enable:enable()
    elif args.disable:disable()
    else:undo()

if __name__=='__main__':
    try:main()
    except (RuntimeError,OSError,UnicodeError,ValueError) as exc:
        print('[ERRO]',exc,file=sys.stderr);sys.exit(1)
