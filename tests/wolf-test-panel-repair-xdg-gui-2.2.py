#!/usr/bin/env python3
"""Testes locais e não destrutivos do reparador manual de painéis e das pastas XDG."""
from pathlib import Path
from tempfile import TemporaryDirectory
import importlib.util
import sys

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

root = Path(__file__).resolve().parents[1]
mon = load('wolf_repair_panels', root/'tools/lxqt/wolf_lxqt_monitors.py')
qt_state={'names':['panel1']}
mon._qt_panels=lambda panel: (qt_state['names'], 'list')
def fake_write(panel, ids): qt_state['names']=[f'panel{i}' for i in range(1,len(ids)+1)]
mon._qt_write_panels=fake_write
xdg = load('wolf_repair_xdg', root/'tools/lxqt/wolf-user-dirs-ptbr.py')

with TemporaryDirectory() as d:
    home = Path(d)/'wolf'; panel = home/'.config/lxqt/panel.conf'
    panel.parent.mkdir(parents=True)
    # Caso real: LXQt remove panel2 e seus widgets quando inativo.
    original = ('panels=panel1\n[panel1]\nplugins=menu1,quick1,tasks1,status1,tray1,volume1,clock1,showdesktop1\n'
                'desktop=0\n[menu1]\ntype=fancymenu\n[quick1]\ntype=quicklaunch\n'
                'apps\\1\\desktop=/usr/share/applications/pcmanfm-qt.desktop\n'
                '[tasks1]\ntype=taskbar\n[status1]\ntype=statusnotifier\n'
                '[tray1]\ntype=tray\n[volume1]\ntype=volume\n'
                '[clock1]\ntype=worldclock\n[showdesktop1]\ntype=showdesktop\n')
    panel.write_text(original)
    assert 'necessário aplicar' in mon.status(panel,counts=(0,1))
    assert mon.apply(panel,counts=(0,1),refresh=False)
    after = panel.read_text()
    assert after.startswith('panels=panel1,panel2\n')
    assert mon.root_panels_entries(after)==['panel1,panel2']
    assert all(f'[{x}2]' in after for x in ['panel','menu','quick','tasks','clock','showdesktop'])
    assert 'apps\\1\\desktop=/usr/share/applications/pcmanfm-qt.desktop' in after
    assert 'status1,tray1,volume1' in after
    assert 'sincronizados' in mon.status(panel,counts=(0,1))
    assert mon.apply(panel,counts=(0,1)) is False
    backups = list((home/'wolf-backups/lxqt-panels').glob('*/panel.conf'))
    assert len(backups)==1 and backups[0].read_text()==original
    assert mon.apply(panel,counts=(0,1,2),refresh=False)
    assert 'panels=panel1,panel2,panel3' in panel.read_text()
    assert '[panel3]' in panel.read_text()
    assert mon.apply(panel,counts=(0,None),refresh=False)
    assert panel.read_text().startswith('panels=panel1\n')

with TemporaryDirectory() as d:
    home = Path(d); cfg=home/'.config/user-dirs.dirs'
    cfg.parent.mkdir(parents=True)
    cfg.write_text('XDG_DOCUMENTS_DIR="$HOME/Documents"\n'
                   'XDG_PICTURES_DIR="$HOME/Pictures"\n'
                   'XDG_VIDEOS_DIR="$HOME/Videos"\n'
                   'XDG_MUSIC_DIR="$HOME/Disco/Music"\n')
    (home/'Pictures').mkdir(); (home/'Pictures/foto.jpg').write_bytes(b'foto')
    (home/'Imagens').mkdir(); (home/'Imagens/outra.png').write_bytes(b'original')
    (home/'Pictures/Capturas de tela').mkdir()
    (home/'Pictures/Capturas de tela/a.png').write_bytes(b'captura antiga')
    (home/'Imagens/Capturas de tela').mkdir()
    (home/'Imagens/Capturas de tela/b.png').write_bytes(b'captura atual')
    (home/'Videos').mkdir(); (home/'Videos/filme.mp4').write_bytes(b'video')
    (home/'Vídeos').mkdir(); (home/'Vídeos/filme.mp4').write_bytes(b'nao sobrescrever')
    (home/'Documents').mkdir(); (home/'Documents/texto.txt').write_bytes(b'doc')
    bm=home/'.config/gtk-3.0/bookmarks';bm.parent.mkdir(parents=True)
    bm.write_text((home/'Pictures').as_uri()+' Figuras\nfile:///mnt/extra Compartilhado\n')
    preview = xdg.migrate(home, apply=False)
    assert any('UNIR SEM SOBRESCREVER' in s for s in preview)
    assert any('PENDENTE' in s and 'VIDEOS' in s for s in preview)
    assert (home/'Pictures/foto.jpg').is_file()
    done = xdg.migrate(home, apply=True)
    assert (home/'Imagens/foto.jpg').read_bytes()==b'foto'
    assert (home/'Imagens/Capturas de tela/a.png').read_bytes()==b'captura antiga'
    assert (home/'Imagens/Capturas de tela/b.png').read_bytes()==b'captura atual'
    assert (home/'Imagens/outra.png').read_bytes()==b'original'
    assert (home/'Pictures').is_dir()  # Origem vazia não apagada silenciosamente
    assert (home/'Documentos/texto.txt').read_bytes()==b'doc'
    assert (home/'Vídeos/filme.mp4').read_bytes()==b'nao sobrescrever'
    assert (home/'Videos/filme.mp4').read_bytes()==b'video'
    state=cfg.read_text()
    assert '$HOME/Imagens' in state and '$HOME/Documentos' in state
    assert '$HOME/Videos' in state  # Não ocultar arquivos pendentes de colisão
    assert '$HOME/Disco/Music' in state
    assert (home/'wolf-backups/xdg-ptbr').is_dir()
    bookmarks=bm.read_text()
    assert 'file:///mnt/extra Compartilhado' in bookmarks
    assert (home/'Imagens').as_uri() in bookmarks
    assert (home/'Pictures').as_uri() not in bookmarks
    assert any('ATENÇÃO' in s for s in done)
    assert '$HOME/Imagens' in cfg.read_text()

main=(root/'tools/control-center/main.py').read_text(encoding='utf-8')
for item in ('Aplicar painéis aos monitores', 'Verificar painéis e monitores',
             'Pré-visualizar migração XDG', 'Migrar diretórios para português',
             'def _apply_panels(', 'def _migrate_user_dirs('):
    assert item in main, item
installer=(root/'install/wolf-install.sh').read_text()
assert 'wolf_lxqt_monitors.py' in installer
assert 'wolf-user-dirs-ptbr.py' in installer
print('[OK] Reconstrução de painéis 1/2/3 monitores, backups, idempotência e migração XDG com colisões')
