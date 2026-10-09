#!/usr/bin/env python3
"""Regressões de UX e segurança do Wolf GUI 0.7 (sem depender do Qt)."""
from __future__ import annotations
import ast
import importlib.util
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
source = (PROJECT / 'live-gui/main.py').read_text(encoding='utf-8')
tree = ast.parse(source)
spec = importlib.util.spec_from_file_location('wolf_gui_ux', PROJECT / 'live-gui/main.py')
ui = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(ui)

# Textos de confirmação precisam descrever perda de dados para a partição
# raiz, /home separada e EFI; não podem confundir com execução nesta versão.
root = ui.format_intent_warning('root', 'in-root', '/dev/vda2')
assert '/dev/vda2' in root and '/home' in root and 'TODOS os arquivos' in root
assert 'MANUAL VM' in root and 'formata a raiz como ext4' in root
separate = ui.format_intent_warning('root', 'separate', '/dev/vda2')
assert 'partição /home separada' in separate
assert 'Windows' in ui.format_intent_warning('esp', 'in-root', '/dev/vda1')
assert 'arquivos pessoais' in ui.format_intent_warning('home', 'separate', '/dev/vda3')

# Inspeciona as ligações UI: aviso acionado por clique real, desmarcado por
# padrão, volta ao índice 0 ao desativar /home e não requer rolagem lateral.
assert 'flag.setChecked(False)  # Nunca presumir consentimento' in source
assert 'flag.clicked.connect(lambda checked, key=role: self.confirm_format_intent(key, checked))' in source
assert 'QMessageBox.StandardButton.No' in source
assert 'home.setCurrentIndex(0)' in source
assert 'flag.setChecked(False)' in source
assert 'self.summary.setLineWrapMode(QPlainTextEdit.LineWrapMode.WidgetWidth)' in source
assert 'self.summary.setWordWrapMode(QTextOption.WrapAtWordBoundaryOrAnywhere)' in source
assert 'review_note.setWordWrap(True)' in source
assert 'self.format_notice.setWordWrap(True)' in source
assert 'APAGAR DISCO INTEIRO' in source and 'APAGARÁ TODAS AS PARTIÇÕES' in source

# O backend deve refletir o risco no JSON/revisão e deixar claro que o Bash
# formata a raiz na reutilização mesmo quando a GUI começou sem marcação.
import sys
sys.path.insert(0, str(PROJECT / 'live-gui'))
import wolf_plan as wp
raw = json.dumps({'blockdevices': [
    {'type':'disk','path':'/dev/vda','size':32000000000,'model':'VM','children':[
        {'type':'part','path':'/dev/vda1','size':500000000,'fstype':'vfat'},
        {'type':'part','path':'/dev/vda2','size':27000000000,'fstype':'ext4'},
        {'type':'part','path':'/dev/vda3','size':4000000000,'fstype':'ext4'}]}]})
disks = wp.inventory(raw)
kwargs = dict(disks=disks, disk_path='/dev/vda', mode='reuse', preset='minimal',
              stacks=(), hostname='wolf', username='wolf', boot_mode='UEFI',
              keyboard={'layout':'br','model':'abnt2','variant':''},
              roles={'root':'/dev/vda2','esp':'/dev/vda1','home':None},
              formats={'root':False,'esp':False,'home':False},home_layout='in-root')
not_marked = wp.build_preview(**kwargs)
assert any('Bash atual SEMPRE formata' in w for w in not_marked['warnings'])
assert 'BLOQUEIO:' in wp.text_summary(not_marked)
assert wp.validate_document(not_marked, disks=disks) == not_marked
marked = wp.build_preview(**(kwargs | {'formats': {'root':True,'esp':False,'home':False}}))
assert any('PERDA DE DADOS' in w for w in marked['warnings'])
assert 'formatar a raiz' in wp.text_summary(marked)
assert wp.validate_document(marked, disks=disks) == marked
assert wp.simulate_document(marked, disks=disks).startswith('WOLF INSTALLER')
assert not_marked['execution'] == marked['execution'] == 'disabled'
assert not_marked['schema'] == marked['schema'] == wp.SCHEMA

print('[OK] UX alpha27: confirmação de formatação, reset de /home, revisão com quebra e contrato read-only')
