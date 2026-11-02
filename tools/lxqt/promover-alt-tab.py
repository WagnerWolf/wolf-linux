#!/usr/bin/env python3
"""Promove Wolf Alt+Tab por monitor para o padrão LXQt/Openbox.
Altera apenas o helper e os atalhos do Openbox, com backup/restauração.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HOME=Path.home()
BACKUPS=HOME/'.local/share/wolf-lxqt-backups'
PROGRAM=HOME/'.local/bin/wolf-alt-tab-monitor'
CONFIGS=[HOME/'.config/openbox/lxqt-rc.xml', HOME/'.config/openbox/rc.xml']
TEMPLATE=[Path('/etc/xdg/openbox/lxqt-rc.xml'), Path('/etc/xdg/openbox/rc.xml')]


def abort(msg):
    raise SystemExit('ERRO: '+msg)


def xml_tag(root, name):
    namespace=(root.tag.partition('}')[0]+'}') if root.tag.startswith('{') else ''
    return namespace+name


def patch_xml(text):
    root=ET.fromstring(text, parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True)))
    if not root.tag.endswith('openbox_config'):
        abort('Arquivo XML inesperado (não é configuração Openbox).')
    if root.tag.startswith('{'):
        ET.register_namespace('', root.tag.split('}')[0][1:])
    t=lambda x: xml_tag(root,x)
    kb=root.find(t('keyboard'))
    if kb is None:
        kb=ET.SubElement(root,t('keyboard'))
    keys={'A-Tab', 'A-S-Tab', 'W-Tab', 'W-S-Tab'}
    for binding in list(kb):
        if binding.tag==t('keybind') and binding.get('key') in keys:
            kb.remove(binding)
    def bind(key, action, command=None):
        b=ET.SubElement(kb,t('keybind'), {'key':key})
        a=ET.SubElement(b,t('action'),{'name':action})
        if command:
            ET.SubElement(a,t('command')).text=command
        return b
    bind('A-Tab','Execute', str(PROGRAM))
    bind('A-S-Tab','Execute',str(PROGRAM)+' --reverse')
    # Alternativa nativa imediata caso o helper falhe.
    bind('W-Tab','NextWindow')
    bind('W-S-Tab','PreviousWindow')
    ET.indent(root,space='  ')
    result=ET.tostring(root,encoding='unicode', xml_declaration=True)
    # Verificação de ida e volta e preservação de teclas essenciais.
    parsed=ET.fromstring(result)
    action_names={b.get('key'):next((a.get('name') for a in b if a.tag==t('action')), None)
                  for b in parsed.iter(t('keybind'))}
    assert action_names['A-Tab']=='Execute'
    assert action_names['A-S-Tab']=='Execute'
    assert action_names['W-Tab']=='NextWindow'
    assert action_names['W-S-Tab']=='PreviousWindow'
    return result


def atomic_bytes(dest, blob, mode=0o644):
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix='.wolf-lxqt-',dir=str(dest.parent))
    try:
        with os.fdopen(fd,'wb') as f:
            f.write(blob)
        os.chmod(tmp, mode)
        os.replace(tmp,dest)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)


def openbox_reload():
    try:
        p=subprocess.run(['pgrep','-u',str(os.getuid()),'-x','openbox'],capture_output=True)
        if p.returncode==0 and os.environ.get('XDG_SESSION_TYPE')=='x11':
            q=subprocess.run(['openbox','--reconfigure'],capture_output=True,text=True)
            if q.returncode == 0:
                print('Openbox recarregado; Alt+Tab está pronto para testar.')
            else:
                print('Aviso: Openbox não pôde ser recarregado:',q.stderr.strip())
                print('Saia e entre no LXQt para aplicar os atalhos.')
        else:
            print('Atalhos serão aplicados quando iniciar sessão LXQt/Openbox.')
    except FileNotFoundError:
        print('Aviso: comando Openbox/pgrep ausente; entre novamente no LXQt.')


def target_original(dest):
    if dest.is_file(): return dest.read_bytes(),dest.stat().st_mode & 0o777
    if dest in CONFIGS:
        source=next((p for p in TEMPLATE if p.is_file()),None)
        if source:return source.read_bytes(),source.stat().st_mode & 0o777
    return None,None


def install():
    if os.geteuid()==0: abort('Execute como usuário normal, sem sudo.')
    source=Path(__file__).parent/'alt_tab_visual.py'
    if not source.is_file(): abort('Falta alt_tab_visual.py no pacote.')
    try:
        import tkinter
        import Xlib
    except Exception as exc:
        abort(f'Faltam tkinter/python-xlib: {exc}')
    import ast
    ast.parse(source.read_text())
    for tool in ('wmctrl','xrandr','xdotool','xprop','openbox'):
        if shutil.which(tool) is None: abort(f'Dependência ausente: {tool}')
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    bk=BACKUPS/f'preview11-{stamp}-{os.getpid()}'
    bk.mkdir(parents=True)
    targets=[PROGRAM,*CONFIGS]
    records=[]
    # Prepara e valida tudo antes de alterar arquivos da sessão.
    payload={PROGRAM:(source.read_bytes(),0o755)}
    for dest in CONFIGS:
        data,mode=target_original(dest)
        if data is None: abort('Configuração Openbox de origem não encontrada.')
        payload[dest]=(patch_xml(data.decode('utf-8')).encode(),mode)
    for index,dest in enumerate(targets):
        existed=dest.exists() or dest.is_symlink()
        if existed and not dest.is_file():abort(f'Arquivo inesperado: {dest}')
        original=dest.read_bytes() if existed else b''
        name=f'original-{index}.dat'
        (bk/name).write_bytes(original)
        records.append({'destination':str(dest),'existed':existed,'original':name,
                        'original_mode':(dest.stat().st_mode & 0o777) if existed else None,
                        'new_sha256':hashlib.sha256(payload[dest][0]).hexdigest()})
    (bk/'manifest.json').write_text(json.dumps({'version':11,'records':records},indent=2))
    try:
        for dest in targets:
            blob,mode=payload[dest]
            atomic_bytes(dest,blob,mode)
    except Exception:
        restore(bk, force=True)
        raise
    print('Wolf Alt+Tab por monitor promovido para o padrão do Openbox.')
    print('Alt+Tab: seletor Wolf | Alt+Shift+Tab: inverso | Super+Tab: nativo (reserva).')
    print('Backup e restauração:')
    print(f'python3 {Path(__file__).resolve()} --restaurar {bk}')
    openbox_reload()


def restore(folder,force=False):
    folder=folder.resolve()
    if not folder.is_relative_to(BACKUPS.resolve()) or not folder.name.startswith('preview11-'):
        abort('Backup fora da pasta prevista ou de outra versão.')
    manifest=json.loads((folder/'manifest.json').read_text())
    if manifest.get('version')!=11:abort('Manifesto de backup incompatível.')
    for item in manifest['records']:
        dest=Path(item['destination'])
        if dest not in [PROGRAM,*CONFIGS]:abort('Manifesto aponta para um arquivo inesperado.')
        blob=(folder/item['original']).read_bytes()
        if not force and dest.is_file():
            digest=hashlib.sha256(dest.read_bytes()).hexdigest()
            if digest!=item['new_sha256']:
                abort(f'Arquivo modificado desde a aplicação: {dest}. Backup preservado.')
        if item['existed']:
            atomic_bytes(dest,blob,item['original_mode'] or 0o644)
        else:
            dest.unlink(missing_ok=True)
    print('Configurações anteriores restauradas.')
    openbox_reload()


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--restaurar',type=Path)
    args=ap.parse_args()
    if args.restaurar:restore(args.restaurar)
    else:install()
