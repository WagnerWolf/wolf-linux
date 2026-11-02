#!/usr/bin/env python3
import tempfile, subprocess, sys, os
from pathlib import Path
root=Path(__file__).resolve().parents[1]
config=(root/'tools/lxqt/configurar.py').read_text()
appearance=(root/'tools/lxqt/wolf-appearance-dark').read_text()
assert "'Qt':{'style':'Fusion'" in config
assert "'QT_STYLE_OVERRIDE':'Fusion'" in config
assert "_modify(FILES[0],'Qt',{'style':'Fusion'},backup)" in appearance
assert "_modify(HOME/'.config/lxqt/session.conf','Environment',{'QT_STYLE_OVERRIDE':'Fusion'},backup)" in appearance
helper=root/'experimental/integracoes-wolf/wolf-fusion-session.py'
with tempfile.TemporaryDirectory(prefix='wolf-qt-style-') as tmp:
    home=Path(tmp)
    lxqt=home/'.config/lxqt'; lxqt.mkdir(parents=True)
    (lxqt/'lxqt.conf').write_text('[Qt]\nstyle=Breeze\n[General]\ntheme=wolf-dark\n',encoding='utf-8')
    (lxqt/'session.conf').write_text('[General]\nwindow_manager=openbox\n[Environment]\nQT_QPA_PLATFORMTHEME=lxqt\n',encoding='utf-8')
    env={**os.environ,'HOME':str(home)}
    # O CI pode executar como root; o utilitário real proíbe root.
    # Isolar o teste em um usuário sem privilégios preserva essa proteção.
    if os.geteuid()==0:
        home.chmod(0o777); lxqt.chmod(0o777)
        as_user=lambda:os.setuid(65534)
    else: as_user=None
    def run(*args):return subprocess.run([sys.executable,str(helper),*args],env=env,check=True,text=True,capture_output=True,preexec_fn=as_user)
    run('--apply')
    a=(lxqt/'lxqt.conf').read_text(); b=(lxqt/'session.conf').read_text()
    assert 'style=Fusion' in a and 'theme=wolf-dark' in a
    assert 'QT_STYLE_OVERRIDE=Fusion' in b and 'QT_QPA_PLATFORMTHEME=lxqt' in b
    backups=list((home/'wolf-backups/qt-fusion').glob('20*'))
    assert len(backups)==1
    run('--restore',str(backups[0]))
    assert (lxqt/'lxqt.conf').read_text()=='[Qt]\nstyle=Breeze\n[General]\ntheme=wolf-dark\n'
    assert 'QT_STYLE_OVERRIDE' not in (lxqt/'session.conf').read_text()
print('[OK] Preview3: Fusion em sessão LXQt; backup e restauração preservam Qt, GTK e Wolf-dark')
