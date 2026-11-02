#!/usr/bin/env python3
"""Regressões seguras do monitor de origem e do cofre Secret Service."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch, Mock
import runpy
import json

ROOT=Path(__file__).resolve().parents[1]
launcher=ROOT/'tools/lxqt/wolf-open-vscode-monitor'
ns={'__name__':'_test'}
exec(compile(launcher.read_text(), str(launcher), 'exec'), ns)
monitor_under_pointer=ns['monitor_under_pointer']
main=ns['main']

outputs={
 'xdotool': Mock(returncode=0,stdout='X=-300\nY=220\nSCREEN=0\n'),
 'xrandr': Mock(returncode=0,stdout='Monitors: 2\n 0: +DP-0 1920/540x1080/300+0+0 DP-0\n 1: +*HDMI-1 1920/480x1080/270-1920+0 HDMI-1\n'),
}
with patch.dict(ns,{'run':lambda cmd,*args:outputs[cmd]}):
 with patch.object(ns['shutil'],'which',lambda name: '/usr/bin/'+name):
  with patch.dict(ns['os'].environ,{'DISPLAY':':0'}):
   assert monitor_under_pointer()==(-1920,0,1920,1080)
assert ns['CODE_CLASS'].search('code.Code')
assert ns['CODE_CLASS'].search('code-oss.Code-oss')
assert not ns['CODE_CLASS'].search('notepad.Notepad')
with TemporaryDirectory() as tmp:
 folder=Path(tmp)
 with patch.dict(ns,{'monitor_under_pointer':lambda:None}):
  with patch.object(ns['shutil'],'which',lambda name:'/usr/bin/'+name):
   with patch.object(ns['subprocess'],'Popen') as popen:
    assert main([str(folder)])==0
    popen.assert_called_once()
    assert popen.call_args.args[0][:2]==['code','--new-window']
 assert main([])==2

profiles=(ROOT/'package-profiles/packages.conf').read_text()
assert 'gnome-keyring libsecret seahorse' in profiles
assert (ROOT/'assets/pcmanfm-qt/wolf-open-vscode.desktop').read_text().count('wolf-open-vscode-monitor')==1
installer=(ROOT/'install/wolf-install.sh').read_text()
assert 'configure_wolf_lxqt_keyring' in installer
assert 'pam_gnome_keyring.so' in installer
assert 'wolf-open-vscode-monitor' in installer
setup=(ROOT/'tools/lxqt/configurar.py').read_text()
assert 'setup_keyring_autostart(inst)' in setup
assert 'gnome-keyring-secrets.desktop' in setup

source=runpy.run_path(str(ROOT/'tests/wolf-configure-user-defaults.py'))
with TemporaryDirectory() as tmp:
 home=Path(tmp)
 c=source['configure_vscode_keyring']
 path=c(home)
 assert json.loads(path.read_text())['password-store']=='gnome-libsecret'
 path.write_text('{"locale":"pt-br","password-store":"basic"}')
 c(home)
 assert json.loads(path.read_text()) == {'locale':'pt-br','password-store':'gnome-libsecret'}
 before=path.read_bytes()
 c(home)
 assert path.read_bytes()==before
 path.write_text('// Comentários do usuário\n{"locale":"pt-br"}\n')
 c(home)
 assert path.read_text().startswith('// Comentários do usuário'), 'JSONC deve permanecer intacto'

print('[OK] VS Code monitor de origem + XRandR + cofre Secret Service + argv.json preservado')

# Evento real: janela já existente deve permanecer intacta; move só ID novo.
with TemporaryDirectory() as tmp:
    folder = Path(tmp)
    sightings = iter(({'0xa'}, {'0xa'}, {'0xa', '0xc'}))
    moved=[]
    def current():
        return next(sightings)
    with patch.dict(ns, {
        'monitor_under_pointer':lambda:(1920,0,1920,1080),
        'code_windows':current,
        'move_window':lambda wid, screen:(moved.append((wid,screen)) or True),
    }):
        with patch.object(ns['shutil'],'which',lambda name:'/usr/bin/'+name):
            with patch.object(ns['subprocess'],'Popen'):
                with patch.object(ns['time'],'sleep',lambda _:None):
                    assert main([str(folder)]) == 0
    assert moved == [('0xc',(1920,0,1920,1080))], moved

# O DevKit de origem tem branding-assets/ e assets/. O preparador copia
# branding-assets/ para assets/ do projeto, mas NÃO mantém branding-assets/.
# Portanto, a instalação preparada deve ser validada pelo destino efetivo.
action = ROOT/'assets/pcmanfm-qt/wolf-open-vscode.desktop'
assert action.is_file(), f'Ação PCManFM-Qt ausente no projeto: {action}'
assert action.read_text(encoding='utf-8').count('Exec=wolf-open-vscode-monitor %f') == 1
preparer = (ROOT/'preparar_ambiente_wolf_linux.sh').read_text(encoding='utf-8')
assert 'cp -a "$SELF_DIR/branding-assets/." "$PROJECT/assets/"' in preparer
assert 'cmp -s "$SELF_DIR/branding-assets/pcmanfm-qt/wolf-open-vscode.desktop"' in preparer
assert 'cmp -s "$PROJECT/assets/pcmanfm-qt/wolf-open-vscode.desktop"' in preparer
branding_action = ROOT/'branding-assets/pcmanfm-qt/wolf-open-vscode.desktop'
if branding_action.exists():
    assert branding_action.read_bytes() == action.read_bytes(), 'Cópias da ação divergem no DevKit'
    print('[OK] Fonte do DevKit e ação PCManFM-Qt idênticas')
else:
    print('[OK] Projeto preparado: ação PCManFM-Qt presente em assets/ (sem exigir branding-assets/)')
print('[OK] VS Code: movimentação isolada da janela criada, sem alterar janelas preexistentes')
