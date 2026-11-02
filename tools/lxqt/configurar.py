#!/usr/bin/env python3
"""Configuração Wolf LXQt X11 2.2.0: painel adaptável e favoritos PCManFM-Qt."""
import argparse
import configparser
import datetime as dt
import json
import os
import re
import shutil
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse
import subprocess
import xml.etree.ElementTree as ET

HOME = Path.home()
CONFIG = HOME / '.config'
DATA = HOME / '.local/share'
BASE = HOME / 'wolf-backups/lxqt'

THEME_QSS = '''/* Wolf LXQt Dark — superfície sem efeitos de composição */
QMenu { background-color: #1d222c; color: #e6edf7; border: 1px solid #3b4656; padding: 4px; }
QMenu::item { padding: 7px 17px; border-radius: 5px; }
QMenu::item:selected { background-color: #324e69; color: #f6fbff; }
QToolTip { background-color: #232d3b; color: #ecf4ff; border: 1px solid #40546b; padding: 5px; }
QToolButton { border: 0px; color: #e6edf7; padding: 3px 5px; }
QToolButton:hover { background-color: #324356; border-radius: 5px; }
QToolButton:pressed { background-color: #416487; border-radius: 5px; }
LXQtPanelPlugin { padding: 0px 2px; }
#MainMenu, #FancyMenu { qproperty-icon: url(mainmenu.svg); }
'''
RUNNER_QSS = '''QWidget { background-color: #1d222c; color: #e6edf7; } QLineEdit { background-color: #121820; color: #f0f5ff; border: 1px solid #43546b; border-radius: 6px; padding: 7px; }'''
NOTIFICATION_QSS = '''QWidget { background-color: #1d222c; color: #e6edf7; } QPushButton { background-color: #33465c; color: #e6edf7; border-radius: 4px; padding: 4px; }'''
PALETTE = {
    'base_color':'#171c25','highlight_color':'#4b8dbb',
    'highlighted_text_color':'#ffffff','link_color':'#78baf0',
    'link_visited_color':'#b29bd6','text_color':'#e9edf5',
    'tooltip_base_color':'#263244','tooltip_text_color':'#f1f5fc',
    'window_color':'#242a34','window_text_color':'#e9edf5'
}

class Installer:
    def __init__(self):
        self.backup_dir = BASE / dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        self.manifest = []
        self.paths_seen = set()
        self.backup_dir.mkdir(parents=True, exist_ok=False)
    def backup(self, path):
        path = Path(path).expanduser()
        assert path.is_relative_to(HOME), f'Fora do HOME: {path}'
        if str(path) in self.paths_seen:
            return
        self.paths_seen.add(str(path))
        relative = path.relative_to(HOME)
        entry = {'path':str(relative), 'existed':path.exists()}
        if path.exists():
            target = self.backup_dir / 'original' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if path.is_dir():
                shutil.copytree(path, target)
            else:
                shutil.copy2(path, target)
        self.manifest.append(entry)
    def write(self, path, data):
        path = Path(path)
        self.backup(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding='utf-8')
    def write_ini(self, path, changes):
        cp = configparser.RawConfigParser(interpolation=None)
        cp.optionxform = str
        if path.exists():
            original = path.read_text(encoding='utf-8')
            # O QSettings admite chaves no nível raiz; configparser exige uma seção.
            if path.name == 'panel.conf' and not original.lstrip().startswith('['):
                original = '[DEFAULT]\n' + original
            cp.read_string(original)
        for section, values in changes.items():
            if section != 'DEFAULT' and not cp.has_section(section):
                cp.add_section(section)
            for key, value in values.items():
                cp.set(section, key, str(value))
        import io
        out = io.StringIO()
        cp.write(out, space_around_delimiters=False)
        self.write(path, out.getvalue())
    def remove_file(self, path):
        path = Path(path)
        if path.is_symlink() or not path.is_file():
            return
        self.backup(path)
        path.unlink()
    def complete(self):
        (self.backup_dir / 'manifest.json').write_text(json.dumps(self.manifest, indent=2, ensure_ascii=False))
        return self.backup_dir

def find_wallpaper(explicit):
    if explicit:
        p = Path(explicit).expanduser().resolve()
        if not p.is_file():
            raise ValueError(f'Wallpaper não existe: {p}')
        return p
    plasma = CONFIG / 'plasma-org.kde.plasma.desktop-appletsrc'
    if plasma.is_file():
        for line in plasma.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.startswith('Image='):
                uri = line.partition('=')[2].strip()
                p = Path(unquote(urlparse(uri).path if uri.startswith('file://') else uri))
                if p.is_file() and p.suffix.lower() in {'.png','.jpg','.jpeg','.webp'}:
                    return p
    for base in (Path('/usr/share/wallpapers'), Path('/usr/share/backgrounds'), HOME / 'Pictures'):
        if base.exists():
            try:
                paths = list(base.rglob('*wolf*.jpg')) + list(base.rglob('*wolf*.png')) + list(base.rglob('*Wolf*.png'))
                for p in paths[:50]:
                    if p.is_file(): return p
            except PermissionError:
                pass
    return None


def find_icon(explicit):
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if not path.is_file():
            raise ValueError(f'Ícone não encontrado: {path}')
        return path
    # Não copiar arte nem inventar logotipo: reutilizar a logo Wolf existente.
    patterns=('newwolf-linux-kickoff.svg','wolf-linux-kickoff.svg','*wolf*linux*menu*.svg',
              'newwolf-linux-kickoff.png','wolf-linux-kickoff.png')
    bases=(Path('/usr/share/icons'),Path('/usr/share/pixmaps'),Path('/usr/local/share/icons'),
           HOME/'.local/share/icons')
    for pattern in patterns:
        for base in bases:
            if base.is_dir():
                for path in base.rglob(pattern):
                    if path.is_file():return path
    return None

def desktop_file(candidates):
    for name in candidates:
        for base in (HOME/'.local/share/applications',Path('/usr/share/applications')):
            candidate=base/name
            if candidate.is_file():return candidate
    return None

def add_shortcut(root, key, command):
    ns='{http://openbox.org/3.4/rc}'
    keyboard=root.find(ns+'keyboard')
    if keyboard is None: keyboard=ET.SubElement(root,ns+'keyboard')
    # Elimina atalho antigo para kfmclient e qualquer conflito da mesma tecla.
    for old in list(keyboard):
        if old.tag==ns+'keybind' and old.get('key')==key: keyboard.remove(old)
    kb=ET.SubElement(keyboard,ns+'keybind',{'key':key})
    action=ET.SubElement(kb,ns+'action',{'name':'Execute'})
    ET.SubElement(action,ns+'command').text=command

def setup_launcher_shortcuts(inst):
    """Monitor passivo Super_L via XRecord, sem capturas exclusivas de teclas."""
    helper=HOME/'.local/bin/wolf-lxqt-super-menu'
    source=Path(__file__).parent/'super_menu_monitor.py'
    import importlib.util
    if importlib.util.find_spec('Xlib') is None:
        print('AVISO: python-xlib ausente; Super continuará em modo compatível via xcape (pode não fechar).')
        print('Instale python-xlib com o Pacman e reaplique a configuração fora do LXQt.')
        data='#!/bin/sh\n[ "$XDG_SESSION_TYPE" = x11 ] || exit 0\ncommand -v xcape >/dev/null || exit 0\nsleep 3\nexec xcape -e \'Super_L=Alt_L|F1\'\n'
    else:
        data=source.read_text(encoding='utf-8')
    inst.write(helper,data)
    helper.chmod(0o755)
    entry=CONFIG/'autostart/wolf-lxqt-super-menu.desktop'
    # A Preview 3 utilizava xcape; este arquivo a substitui (na próxima sessão).
    inst.write(entry,f"""[Desktop Entry]\nType=Application\nName=Wolf LXQt Super Menu\nComment=Super isolado alterna Fancy Menu sem capturar atalhos do Openbox\nExec={helper}\nOnlyShowIn=LXQt;\nNoDisplay=true\nX-LXQt-Need-Tray=false\n""")


def setup_openbox(inst, alttab=False):
    sources = [Path('/etc/xdg/openbox/lxqt-rc.xml'), Path('/etc/xdg/openbox/rc.xml')]
    source = next((p for p in sources if p.is_file()), None)
    if source is None:
        print('AVISO: configuração padrão Openbox ausente; não sobrescrita.')
        return
    ET.register_namespace('', 'http://openbox.org/3.4/rc')
    ET.register_namespace('xi', 'http://www.w3.org/2001/XInclude')
    tree = ET.parse(source)
    root = tree.getroot()
    ns = '{http://openbox.org/3.4/rc}'
    def setxml(section, tag, value):
        parent = root.find(ns + section)
        if parent is None: parent = ET.SubElement(root, ns + section)
        child = parent.find(ns + tag)
        if child is None: child = ET.SubElement(parent, ns + tag)
        child.text = value
    setxml('placement', 'monitor', 'Mouse')
    setxml('placement', 'primaryMonitor', 'Mouse')
    setxml('theme','name','Onyx')
    setxml('theme','titleLayout','NLIMC')
    setxml('desktops','number','1')
    setxml('desktops','firstdesk','1')
    # Openbox: rolagem no desktop troca de workspace; na barra de titulo
    # faz shade/unshade (que parece alternar janelas). Remover apenas esses
    # binds, sem afetar rolagem dentro dos aplicativos.
    mouse = root.find(ns+'mouse')
    if mouse is not None:
        for context in mouse.findall(ns+'context'):
            if context.get('name') in {'Desktop','Root','Titlebar','Frame'}:
                for bind in list(context.findall(ns+'mousebind')):
                    if bind.get('button') in {'Up','Down'} and bind.get('action') in {'Click','Press'}:
                        context.remove(bind)
    add_shortcut(root,'W-e','pcmanfm-qt')
    # Ctrl+Alt+T e Print sao atalhos de lxqt-globalkeysd; configurar la evita conflito com Openbox.
    # Remover o atalho anterior Super+Enter; padrao foi trocado.
    keyboard=root.find(ns+'keyboard')
    if keyboard is not None:
        for kb in list(keyboard.findall(ns+'keybind')):
            if kb.get('key')=='W-Return':keyboard.remove(kb)
    # Fundamental: sempre preservar Alt+Tab nativo (a Preview 3 o quebrou).
    # Ao segurar Alt, Openbox gerencia o ciclo completo e o diálogo de janelas.
    def native_cycle(key, action_name):
        for kb in list(keyboard.findall(ns+'keybind')):
            if kb.get('key')==key: keyboard.remove(kb)
        kb=ET.SubElement(keyboard,ns+'keybind',{'key':key})
        action=ET.SubElement(kb,ns+'action',{'name':action_name})
        ET.SubElement(action,ns+'allDesktops').text='no'
    native_cycle('A-Tab','NextWindow')
    native_cycle('A-S-Tab','PreviousWindow')
    # Seletor por monitor usa Super+Tab, não substitui Alt+Tab.
    if alttab:
        helper = str(HOME/'.local/bin/wolf-alt-tab-monitor')
        add_shortcut(root,'W-Tab',helper)
        add_shortcut(root,'W-S-Tab',helper+' --reverse')
    else:
        for kb in list(keyboard.findall(ns+'keybind')):
            if kb.get('key') in ('W-Tab','W-S-Tab'): keyboard.remove(kb)
    ET.indent(tree, space='  ')
    import io
    buf=io.BytesIO()
    tree.write(buf,encoding='utf-8',xml_declaration=True)
    inst.write(CONFIG/'openbox/lxqt-rc.xml',buf.getvalue().decode())
    inst.write(CONFIG/'openbox/rc.xml',buf.getvalue().decode())

def setup_panel(inst, screens, icon=None):
    # Uma mesma estrutura por monitor, mas tray/volume/notifier apenas na tela primaria.
    # O sistema instalado ainda nao sabe quantos monitores tera na sessao final.
    # Inicia SEMPRE com panel1 (com tray) e deixa o segundo preparado, inativo.
    # wolf-lxqt-monitors o ativa apos detectar dois monitores X11 de verdade.
    changes={'DEFAULT':{'panels':'panel1'}}
    pids=[('panel1',0,'menu1,quick1,tasks1,status1,tray1,volume1,clock1,showdesktop1'),
          ('panel2',1,'menu2,quick2,tasks2,clock2,showdesktop2')]
    for name, screen, plugins in pids:
        changes[name]={'plugins':plugins,'position':'Bottom','desktop':str(screen),
                       'panelSize':'38','iconSize':'24','width':'100','lineCount':'1'}
    for k in ('menu1','menu2'):
        changes[k]={'type':'fancymenu','alignment':'Left','filterClear':'true'}
        if icon: changes[k].update({'ownIcon':'true','icon':str(icon)})
    for k in ('tasks1','tasks2'):
        changes[k]={'type':'taskbar','buttonWidth':'200','closeOnMiddleClick':'true',
                    'groupingEnabled':'false','showOnlyCurrentScreenTasks':'true',
                    'showOnlyMinimizedTasks':'false','showOnlyOneDesktopTasks':'false'}
    for k in ('clock1','clock2'):
        changes[k]={'type':'worldclock','alignment':'Right'}
    for k in ('showdesktop1','showdesktop2'):
        changes[k]={'type':'showdesktop','alignment':'Right'}
    launchers=[desktop_file(('google-chrome.desktop','google-chrome-stable.desktop','chromium.desktop')),
               desktop_file(('pcmanfm-qt.desktop',)),
               desktop_file(('org.kde.konsole.desktop','konsole.desktop'))]
    launchers=[p for p in launchers if p]
    for key in ('quick1','quick2'):
        quick={'type':'quicklaunch','alignment':'Left'}
        for i,path in enumerate(launchers,1):
            quick[f'apps\\{i}\\desktop']=str(path)
        quick['apps\\size']=str(len(launchers))
        changes[key]=quick
    changes.update({'status1':{'type':'statusnotifier','alignment':'Right'},
                    'tray1':{'type':'tray','alignment':'Right'},
                    'volume1':{'type':'volume','alignment':'Right'}})
    panel_file=CONFIG/'lxqt/panel.conf'
    # Recria apenas o painel Wolf para remover itens antigos (inclusive
    # quicklaunch Dolphin e secoes de plugins de previews anteriores).
    # Installer faz backup antes da remocao.
    inst.remove_file(panel_file)
    inst.write_ini(panel_file,changes)
    # Remove prefixo [DEFAULT] para a opcao root usada por QSettings LXQt.
    content=panel_file.read_text(encoding='utf-8')
    content=content.replace('[DEFAULT]\npanels=', 'panels=', 1)
    inst.write(panel_file,content)

def setup_monitor_autostart(inst):
    """Ajusta paineis uma vez por login, sem watcher persistente."""
    inst.write(CONFIG/'autostart/wolf-lxqt-monitors.desktop', """[Desktop Entry]
Type=Application
Name=Wolf - Painéis por monitor
Comment=Ativa o painel secundário apenas se houver duas telas conectadas
Exec=/usr/local/bin/wolf-lxqt-monitors --session
TryExec=/usr/local/bin/wolf-lxqt-monitors
OnlyShowIn=LXQt;
X-LXQt-Need-Tray=false
NoDisplay=true
Terminal=false
""")


def setup_ptbr_user_dirs(inst):
    """No /home novo, fixar os diretórios XDG em português antes do primeiro login.

    Reutilizações com user-dirs.dirs existente nunca são reescritas: uma
    pasta personalizada pode conter dados em outro volume.
    """
    target = CONFIG/'user-dirs.dirs'
    if target.exists() or target.is_symlink():
        return False
    names = [
        ('DESKTOP', 'Área de Trabalho'), ('DOWNLOAD', 'Downloads'),
        ('TEMPLATES', 'Modelos'), ('PUBLICSHARE', 'Público'),
        ('DOCUMENTS', 'Documentos'), ('MUSIC', 'Músicas'),
        ('PICTURES', 'Imagens'), ('VIDEOS', 'Vídeos'),
    ]
    lines = ['# Pastas XDG do Wolf Linux (pt_BR). Não mover dados automaticamente.']
    for key, folder in names:
        path = HOME/folder
        if path.is_symlink():
            raise RuntimeError(f'Pasta XDG é um link simbólico: {path}')
        path.mkdir(parents=True, exist_ok=True)
        lines.append(f'XDG_{key}_DIR="$HOME/{folder}"')
    inst.write(target, '\n'.join(lines)+'\n')
    inst.write(CONFIG/'user-dirs.locale', 'pt_BR\n')
    return True


def setup_mouse_flat(inst):
    """X11: corrigir preferências restauradas pelo LXQt sem afetar touchpads."""
    inst.write(CONFIG/'autostart/wolf-lxqt-mouse-flat.desktop', """[Desktop Entry]
Type=Application
Name=Wolf - Mouse sem aceleração
Comment=Perfil flat para mouses libinput na sessão LXQt/X11
Exec=/usr/local/bin/wolf-lxqt-mouse-flat
TryExec=/usr/local/bin/wolf-lxqt-mouse-flat
OnlyShowIn=LXQt;
NoDisplay=true
X-LXQt-Need-Tray=false
""")


def _xdg_user_path(kind):
    """Usa caminhos XDG locais existentes ou padroes, sem interpretar shell."""
    cfg = CONFIG/'user-dirs.dirs'
    if cfg.is_file():
        for line in cfg.read_text(encoding='utf-8',errors='replace').splitlines():
            m = re.match(r'^\s*XDG_'+re.escape(kind)+r'_DIR="([^"\n]*)"\s*$',line)
            if m:
                value=m.group(1).replace('$HOME',str(HOME))
                result=Path(value).expanduser()
                if result.is_absolute() and result.is_relative_to(HOME):
                    return result
    # Preferencias do sistema podem deixar user-dirs sem entradas em /home novo.
    fallback={'DOCUMENTS':'Documents','DOWNLOAD':'Downloads','PICTURES':'Pictures',
              'MUSIC':'Music','VIDEOS':'Videos'}
    return HOME/fallback[kind]


def setup_pcmanfm_places(inst):
    """Pastas XDG em favoritos do PCManFM-Qt; preserva favoritos proprios."""
    if shutil.which('xdg-user-dirs-update'):
        subprocess.run(['xdg-user-dirs-update'],check=False,stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL,
                       env={**os.environ,'HOME':str(HOME),'XDG_CONFIG_HOME':str(CONFIG)})
    # Pastas configuradas no user-dirs.dirs: nao sobrescrever o idioma/nome real.
    desired=[]
    for kind,label in [('DOCUMENTS','Documentos'),('DOWNLOAD','Downloads'),
                       ('PICTURES','Imagens'),('MUSIC','Músicas'),('VIDEOS','Vídeos')]:
        path=_xdg_user_path(kind)
        if path==HOME or not path.is_relative_to(HOME):
            continue
        path.mkdir(parents=True,exist_ok=True)
        desired.append((path.as_uri(),label))
    bookmarks=CONFIG/'gtk-3.0/bookmarks'
    existing=bookmarks.read_text(encoding='utf-8').splitlines() if bookmarks.is_file() else []
    canonical={uri for uri,_ in desired}
    # Evita entradas em duplicidade, inclusive nomes antigos como Pictures.
    custom=[]
    for line in existing:
        uri=line.split(' ',1)[0]
        if uri not in canonical and line not in custom:
            custom.append(line)
    new='\n'.join(f'{uri} {label}' for uri,label in desired)+('\n' if desired else '')
    if custom:
        new+='\n'.join(custom)+'\n'
    if not bookmarks.is_file() or bookmarks.read_text(encoding='utf-8') != new:
        inst.write(bookmarks,new)


def write_desktop_mime(inst):
    """Mapeia os aplicativos de preferencia para todos os DEs; com backup."""
    browser=desktop_file(('google-chrome.desktop','google-chrome-stable.desktop','chromium.desktop'))
    fileman=desktop_file(('pcmanfm-qt.desktop',))
    if not fileman:
        raise RuntimeError('PCManFM-Qt: entrada pcmanfm-qt.desktop ausente. Verifique o pacote LXQt.')
    terminal=desktop_file(('org.kde.konsole.desktop','konsole.desktop'))
    kate=desktop_file(('org.kde.kate.desktop','kate.desktop'))
    video=desktop_file(('io.github.mpc_qt.mpc-qt.desktop','mpc-qt.desktop','mpcqt.desktop'))
    audio=desktop_file(('audacious.desktop',))
    pdf=desktop_file(('org.kde.okular.desktop','okular.desktop'))
    archive=desktop_file(('lxqt-archiver.desktop',))
    default={}
    if browser:
        for mime in ('x-scheme-handler/http','x-scheme-handler/https','text/html','application/xhtml+xml'):
            default[mime]=browser.name+';'
    if fileman: default['inode/directory']=fileman.name+';'
    if kate: default['text/plain']=kate.name+';'
    if video:
        for mime in ('video/mp4','video/x-matroska','video/webm','video/x-msvideo'):
            default[mime]=video.name+';'
    if audio:
        for mime in ('audio/mpeg','audio/flac','audio/ogg','audio/x-wav'):
            default[mime]=audio.name+';'
    if pdf: default['application/pdf']=pdf.name+';'
    if archive:
        for mime in ('application/zip','application/x-zip-compressed','application/x-7z-compressed','application/vnd.rar'):
            default[mime]=archive.name+';'
    if default:
        for file in (CONFIG/'mimeapps.list', CONFIG/'lxqt-mimeapps.list'):
            inst.write_ini(file, {'Default Applications':default,
                                 'Added Associations':{'inode/directory':fileman.name+';'}} if fileman
                           else {'Default Applications':default})
            # Um /home preservado pode ter exclusões antigas do PCManFM-Qt.
            if fileman and file.is_file():
                cp=configparser.RawConfigParser(interpolation=None,strict=False)
                cp.optionxform=str
                cp.read(file,encoding='utf-8')
                if cp.has_option('Removed Associations','inode/directory'):
                    removed=[v for v in cp.get('Removed Associations','inode/directory').split(';')
                             if v and v != fileman.name]
                    if removed:
                        cp.set('Removed Associations','inode/directory',';'.join(removed)+';')
                    else:
                        cp.remove_option('Removed Associations','inode/directory')
                    import io
                    out=io.StringIO()
                    cp.write(out,space_around_delimiters=False)
                    inst.write(file,out.getvalue())
    # Preferencias LXQt: terminal e gerenciador de arquivos (sem instalar pacotes).
    changes={}
    if browser:changes['DefaultApplications']={'webBrowser':browser.stem}
    if fileman:changes.setdefault('DefaultApplications',{})['fileManager']='pcmanfm-qt'
    if terminal:changes.setdefault('DefaultApplications',{})['terminal']='konsole'
    if changes:inst.write_ini(CONFIG/'lxqt/session.conf',changes)
    print(f'Aplicativos: navegador={browser.name if browser else "não identificado"}, PCManFM-Qt={bool(fileman)}, Konsole={bool(terminal)}')

def setup_pcmanfm_vscode_action(inst):
    """Ação nativa do PCManFM-Qt (sem dependência de serviços KDE KIO)."""
    target = DATA / 'file-manager/actions/wolf-open-vscode.desktop'
    if shutil.which('code'):
        source=Path(__file__).parent.parent.parent/'assets/pcmanfm-qt/wolf-open-vscode.desktop'
        # No sistema instalado, assets ficam no DevKit, não em /usr/local/lib.
        # O instalador deixa a ação oficial em /usr/share/wolf-linux/lxqt/.
        if not source.is_file():
            source=Path('/usr/share/wolf-linux/lxqt/wolf-open-vscode.desktop')
        if source.is_file():
            inst.write(target, source.read_text(encoding='utf-8'))
        else:
            inst.write(target, """[Desktop Entry]
Type=Action
Name=Abrir pasta no Visual Studio Code
Icon=visual-studio-code
Profiles=wolf-vscode;

[X-Action-Profile wolf-vscode]
Name=Abrir pasta no Visual Studio Code
MimeTypes=inode/directory;
SelectionCount==1
Exec=wolf-open-vscode-monitor %f
""")
    elif target.is_file() and not target.is_symlink() and 'Profiles=wolf-vscode;' in target.read_text(encoding='utf-8', errors='replace'):
        inst.remove_file(target)
    # Limpeza limitada a um arquivo legado gerado pelo Wolf; backup antes.
    old = DATA / 'kio/servicemenus/wolf-open-vscode.desktop'
    if old.is_file() and not old.is_symlink() and 'wolfOpenVSCode' in old.read_text(encoding='utf-8', errors='replace'):
        inst.remove_file(old)


def setup_keyring_autostart(inst):
    """Secret Service/gnome-keyring no LXQt; substitui o autostart homônimo.

    PAM do SDDM desbloqueia o cofre com a senha do login. O autostart só
    inicia o componente secrets, não salva senha nem substitui PAM.
    """
    inst.write(CONFIG/'autostart/gnome-keyring-secrets.desktop', """[Desktop Entry]
Type=Application
Name=Chaveiro seguro Wolf LXQt
Comment=Armazenamento de credenciais via Secret Service
Exec=gnome-keyring-daemon --start --components=secrets
TryExec=gnome-keyring-daemon
OnlyShowIn=LXQt;
NoDisplay=true
X-LXQt-Need-Tray=false
""")


def setup_network_tray(inst):
    """Um unico nm-applet por sessao LXQt, com menu StatusNotifier Qt.

    O pacote fornece /etc/xdg/autostart/nm-applet.desktop. Criar um override
    com O MESMO basename em ~/.config/autostart, em vez de um segundo arquivo
    Wolf, evita lancamentos duplicados. O Installer preserva /home em backup.
    """
    inst.write(CONFIG/'autostart/nm-applet.desktop', """[Desktop Entry]
Type=Application
Name=Conexões de rede (Wolf LXQt)
Comment=Wi-Fi, Ethernet e VPN pelo NetworkManager na bandeja do LXQt
Exec=nm-applet --indicator
TryExec=nm-applet
OnlyShowIn=LXQt;
X-LXQt-Need-Tray=true
Terminal=false
NoDisplay=true
""")


def setup_removable_media(inst):
    """Somente tray (sem automontador concorrente) e ação com guarda de montagem."""
    # Inibe udiskie anterior (autostart do usuário) e usa indicador Qt próprio
    # com menu integralmente pt_BR, sem criar automontagem concorrente.
    inst.write(CONFIG/'autostart/wolf-udiskie.desktop', """[Desktop Entry]
Type=Application
Name=Udiskie legado (desativado)
Hidden=true
""")
    inst.write(CONFIG/'autostart/wolf-removable-tray.desktop', """[Desktop Entry]
Type=Application
Name=Dispositivos removíveis (Wolf Linux)
Exec=/usr/local/bin/wolf-removable-tray
TryExec=/usr/local/bin/wolf-removable-tray
OnlyShowIn=LXQt;
X-LXQt-Need-Tray=true
NoDisplay=true
""")
    # A integração exclusiva é no menu de dispositivos da libfm-qt Wolf.
    # Remover somente o antigo lançador de pasta criado pelo Wolf, com backup.
    old_action = DATA/'file-manager/actions/wolf-format-removable.desktop'
    if old_action.is_file() and not old_action.is_symlink():
        content = old_action.read_text(encoding='utf-8', errors='replace')
        if ('Type=Action' in content and 'wolf-format-removable --format %f' in content
                and 'Folders=/run/media/*;/media/*;' in content):
            inst.remove_file(old_action)



def setup_lxqt_settings_icon(inst,menu_icon):
    source=desktop_file(('lxqt-config.desktop',))
    if source and source.is_file():
        try:
            original=source.read_text(encoding='utf-8')
            edited=patch_ini_key(original,'Desktop Entry','Icon',str(menu_icon))
            inst.write(DATA/'applications/lxqt-config.desktop',edited)
        except (OSError,UnicodeDecodeError):
            print('AVISO: não foi possível personalizar o ícone do Centro de Configurações LXQt.')

def setup_wolf_monitors_menu(inst):
    """No LXQt, apresentar somente editor Wolf; preservar o pacote lxqt-config."""
    inst.write(DATA/'applications/lxqt-config-monitor.desktop', """[Desktop Entry]
Type=Application
Name=Configuração de monitores LXQt (oculta pelo Wolf)
Exec=lxqt-config-monitor
Icon=preferences-desktop-display
Categories=Settings;DesktopSettings;Qt;LXQt;HardwareSettings;
OnlyShowIn=LXQt;
NoDisplay=true
""")


def setup_global_shortcuts(inst):
    # Atalhos de LXQt possuem IDs especificos: substituir comandos e manter o mesmo ID.
    # Ao contrario de binds duplicados no Openbox, nao conflitam com lxqt-globalkeysd.
    inst.write_ini(CONFIG/'lxqt/globalkeyshortcuts.conf',{
        'Control%2BAlt%2BT.1':{'Comment':'Konsole','Enabled':'true','Exec':'env, QT_QPA_PLATFORMTHEME=kde, konsole'},
        'Print.8':{'Comment':'Spectacle','Enabled':'true','Exec':'env, QT_QPA_PLATFORMTHEME=kde, spectacle'},
        'Control%2BAlt%2BE.6':{'Comment':'PCManFM-Qt','Enabled':'true','Exec':'pcmanfm-qt'},
        'Control%2BAlt%2BI.7':{'Comment':'Navegador padrão','Enabled':'true',
                               'Exec':'xdg-open, about:blank'},
        'Shift%2BPrint.50':{'Comment':'Spectacle - região','Enabled':'true',
                            'Exec':'env, QT_QPA_PLATFORMTHEME=kde, spectacle, -r'},
    })

def patch_ini_key(original,section,key,value):
    """Edita apenas uma chave KDE sem reescrever toda a estrutura do kdeglobals."""
    lines=original.splitlines(keepends=True)
    current=None; target=False
    for idx,line in enumerate(lines):
        if line.startswith('[') and line.rstrip().endswith(']'):
            if target:
                lines.insert(idx,f'{key}={value}\n');return ''.join(lines)
            current=line.strip()[1:-1];target=current==section
        elif target and re.match(r'^'+re.escape(key)+r'\s*=',line):
            lines[idx]=f'{key}={value}\n';return ''.join(lines)
    if target:
        if lines and not lines[-1].endswith('\n'):lines[-1]+='\n'
        lines.append(f'{key}={value}\n')
    else:
        if lines and not lines[-1].endswith('\n'):lines[-1]+='\n'
        lines.extend([f'[{section}]\n',f'{key}={value}\n'])
    return ''.join(lines)

def setup_kde_app_dark(inst, system_apps_dir=Path("/usr/share/applications")):
    """Mantém o tema LXQt nativo, mas ativa o tema KDE em aplicativos KDE.

    O plugin QPA "lxqt" pode fazer KColorScheme escolher Breeze Light apesar do
    kdeglobals. A substituição .desktop aplica o tema KDE ao iniciar pelo menu,
    associação MIME ou atalhos de aplicativo. Só reescreve as entradas existentes;
    salva cópias originais para reversão.
    """
    kde_globals = CONFIG/'kdeglobals'
    original=kde_globals.read_text(encoding='utf-8') if kde_globals.exists() else ''
    original=patch_ini_key(original,'General','ColorScheme','BreezeDark')
    original=patch_ini_key(original,'UiSettings','ColorScheme','BreezeDark')
    original=patch_ini_key(original,'Icons','Theme','Papirus-Dark')
    inst.write(kde_globals,original)

    apps={
        'Kate':('org.kde.kate.desktop','kate.desktop'),
        'Okular':('org.kde.okular.desktop','okular.desktop'),
        'Konsole':('org.kde.konsole.desktop','konsole.desktop'),
        'Spectacle':('org.kde.spectacle.desktop','spectacle.desktop'),
        'Ark':('org.kde.ark.desktop','ark.desktop'),
        'Gwenview':('org.kde.gwenview.desktop','gwenview.desktop'),
    }
    for label,names in apps.items():
        # Usar a versão do sistema como base evita empilhar env nos overrides.
        src=next((system_apps_dir/name for name in names
                  if (system_apps_dir/name).is_file()),None)
        if not src:
            print(f'KDE: {label} não encontrado em /usr/share/applications; ignorado')
            continue
        raw=src.read_text(encoding='utf-8')
        cp=configparser.RawConfigParser(interpolation=None,strict=False)
        cp.optionxform=str
        try:cp.read_string(raw)
        except configparser.Error:
            print(f'KDE: {src.name}: .desktop não pode ser interpretado; ignorado')
            continue
        if not cp.has_option('Desktop Entry','Exec'):
            continue
        orig_exec=cp.get('Desktop Entry','Exec')
        # Não alterar as ações secundárias do .desktop: elas podem ter Exec próprio.
        if orig_exec.startswith('env QT_QPA_PLATFORMTHEME=kde '):
            continue
        raw=patch_ini_key(raw,'Desktop Entry','Exec',
                          'env QT_QPA_PLATFORMTHEME=kde '+orig_exec)
        # DBusActivatable=true pode ignorar Exec e reabrir o aplicativo sem env.
        raw=patch_ini_key(raw,'Desktop Entry','DBusActivatable','false')
        inst.write(DATA/'applications'/src.name,raw)
        print(f'KDE: tema Breeze Dark para {label} pelo lançador {src.name}')
def configure(args):
    if os.geteuid()==0:
        raise SystemExit('Execute como usuário normal, sem sudo.')
    if os.environ.get('XDG_CURRENT_DESKTOP','').upper().find('LXQT') >= 0:
        raise SystemExit('Saia do LXQt antes de configurar os arquivos; execute pelo Plasma ou TTY.')
    if args.screens not in (1,2):
        raise SystemExit('Prévia suporta um ou dois monitores.')
    wall = find_wallpaper(args.wallpaper)
    icon = find_icon(args.icon) if args.icon else None
    # SVG Wolf simplificado, legivel ate em 24px. Icone oficial pode ser passado em --icone.
    menu_icon = DATA/'icons/hicolor/scalable/apps/wolf-lxqt-menu.svg'
    if args.alttab_monitor:
        faltando=[p for p in ('xdotool','wmctrl','xrandr','xprop') if shutil.which(p) is None]
        if faltando:
            print('AVISO: Alt+Tab por monitor não ativado; faltam: '+', '.join(faltando))
            print('Instale: sudo pacman -Syu --needed xdotool wmctrl xorg-xrandr xorg-xprop')
            args.alttab_monitor=False
    inst = Installer()
    inst.write_ini(CONFIG/'lxqt/lxqt.conf',{
        'General':{'theme':'wolf-dark','icon_theme':'Papirus-Dark','icon_follow_color_scheme':'true',
                   'single_click_activate':'false','palette_override':'true'},
        'Palette':PALETTE,
        'Qt':{'style':'Fusion', 'font':'Noto Sans,10,-1,5,50,0,0,0,0,0'}})
    palette_lines='[Palette]\n'+''.join(f'{k}={v}\n' for k,v in PALETTE.items())
    inst.write(DATA/'lxqt/palettes/wolf-dark.conf',palette_lines)
    inst.write_ini(CONFIG/'lxqt/session.conf',{'General':{'window_manager':'openbox'}, 'Environment':{'QT_QPA_PLATFORMTHEME':'lxqt', 'QT_STYLE_OVERRIDE':'Fusion'}})
    # O tema LXQt é QSS e NÃO controla apps GTK; Blueman requer tema GTK.
    for gtk_dir in ('gtk-3.0', 'gtk-4.0'):
        inst.write_ini(CONFIG/f'{gtk_dir}/settings.ini',
                       {'Settings':{'gtk-theme-name':'Breeze-Dark',
                                    'gtk-icon-theme-name':'Papirus-Dark',
                                    'gtk-application-prefer-dark-theme':'true'}})

    theme = DATA/'lxqt/themes/wolf-dark'
    for name, data in {'lxqt-panel.qss':THEME_QSS, 'lxqt-runner.qss':RUNNER_QSS,
                       'lxqt-notificationd.qss':NOTIFICATION_QSS}.items():
        inst.write(theme/name,data)
    inst.write(menu_icon, (Path(__file__).parent/'wolf-lxqt-menu.svg').read_text(encoding='utf-8'))
    setup_openbox(inst,args.alttab_monitor)
    setup_kde_app_dark(inst)
    setup_panel(inst,args.screens, icon or menu_icon)
    setup_monitor_autostart(inst)
    setup_ptbr_user_dirs(inst)
    setup_pcmanfm_places(inst)
    setup_mouse_flat(inst)
    write_desktop_mime(inst)
    setup_global_shortcuts(inst)
    setup_lxqt_settings_icon(inst,menu_icon)
    setup_wolf_monitors_menu(inst)
    setup_launcher_shortcuts(inst)
    setup_pcmanfm_vscode_action(inst)
    setup_removable_media(inst)
    inst.write(CONFIG/'autostart/wolf-xsettingsd.desktop', """[Desktop Entry]
Type=Application
Name=Wolf - Tema GTK/X11
Exec=/usr/local/bin/wolf-gtk-xsettings
TryExec=/usr/local/bin/wolf-gtk-xsettings
OnlyShowIn=LXQt;
NoDisplay=true
""")
    inst.write(CONFIG/'xsettingsd/xsettingsd.conf',
               'Net/ThemeName "Breeze-Dark"\nNet/IconThemeName "Papirus-Dark"\n'
               'Gtk/CursorThemeName "breeze_cursors"\n')
    setup_network_tray(inst)
    setup_keyring_autostart(inst)
    # Tema proprio exporta mainmenu.svg para #FancyMenu / #MainMenu.
    inst.write(theme/'mainmenu.svg', (Path(__file__).parent/'wolf-lxqt-menu.svg').read_text(encoding='utf-8'))
    if args.alttab_monitor:
        helper=HOME/'.local/bin/wolf-alt-tab-monitor'
        inst.write(helper,(Path(__file__).parent/'alt_tab_visual.py').read_text())
        helper.chmod(0o755)
    # PCManFM-Qt controla desktop, pastas e dispositivos pelo mesmo perfil LXQt.
    # Configuracões em ~/.config/pcmanfm-qt/lxqt/.
    # PerScreenWallpaper repete e escala a imagem por cada monitor X11.
    desktop_options = {'PerScreenWallpaper':'true', 'WallpaperMode':'zoom', 'BgColor':'#131923'}
    if wall:
        desktop_options['Wallpaper'] = str(wall)
    inst.write_ini(CONFIG/'pcmanfm-qt/lxqt/settings.conf',{
        'Desktop':desktop_options,
        'System':{'IconThemeName':'Papirus-Dark','FallbackIconThemeName':'breeze-dark','Terminal':'konsole'}})
    # SDDM, mouse, drivers e boot preservados; MIME e kdeglobals afetam outros desktops também (backup).
    path = inst.complete()
    print(f'\nCONFIGURAÇÃO CRIADA. Backup: {path}')
    print('Tema LXQt preservado; KDE: BreezeDark por aplicativo; ícones Papirus-Dark')
    print('Atalhos: Alt+Tab nativo; Super+Tab: seletor por monitor (tkinter/Xlib, Rofi reserva); Super via XRecord.')
    print(f'Alt+Tab: nativo do Openbox; Super+Tab: {"por monitor (experimental)" if args.alttab_monitor else "desativado"}')
    print(f'Ícone do menu: {icon or menu_icon}')
    print('Painel principal com bandeja; painel secundário habilitado automaticamente se houver outra tela.')
    if wall: print(f'Wallpaper reaproveitado: {wall}')
    else: print('Wallpaper Wolf não localizado. Selecione manualmente em Preferências da Área de Trabalho.')
    print(f'Reverter: python3 configurar.py --restaurar "{path}"')

def restore(path):
    base = Path(path).expanduser().resolve()
    assert base.is_relative_to(BASE.resolve()), 'Backup externo não aceito'
    entries = json.loads((base/'manifest.json').read_text())
    for ent in reversed(entries):
        rel = Path(ent['path'])
        if rel.is_absolute() or '..' in rel.parts:
            raise ValueError('Caminho de backup inválido')
        dest = HOME/rel
        if dest.is_dir(): shutil.rmtree(dest)
        elif dest.exists(): dest.unlink()
        if ent['existed']:
            origin = base/'original'/rel
            dest.parent.mkdir(parents=True,exist_ok=True)
            if origin.is_dir(): shutil.copytree(origin,dest)
            else: shutil.copy2(origin,dest)
    print('Configurações restauradas. Pacotes não foram removidos.')

if __name__=='__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--telas','--screens',type=int,choices=[1,2],default=2,dest='screens')
    ap.add_argument('--wallpaper',help='Imagem Wolf existente, caso a detecção automática não encontre')
    ap.add_argument('--icone','--icon',dest='icon',help='Caminho da logo SVG/PNG do Wolf Linux no menu')
    ap.add_argument('--alt-tab-monitor',action='store_true',dest='alttab_monitor',default=True,help='Ativa Super+Tab com confirmação ao soltar Super; Alt+Tab nativo permanece')
    ap.add_argument('--alt-tab-original',action='store_false',dest='alttab_monitor',help='Desativa Super+Tab experimental; Alt+Tab permanece nativo')
    ap.add_argument('--restaurar',type=Path)
    a = ap.parse_args()
    if a.restaurar: restore(a.restaurar)
    else: configure(a)
