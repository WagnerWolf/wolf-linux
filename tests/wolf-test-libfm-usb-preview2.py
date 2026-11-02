#!/usr/bin/env python3
"""Verifica somente a geração do patch e segurança do roteamento USB; não instala nada."""
from pathlib import Path
import importlib.util
import sys
ROOT=Path(__file__).resolve().parents[1]
PATCHER=ROOT/'experimental/integracoes-wolf/gerar-patch-libfm-qt-2.4.0.py'
spec=importlib.util.spec_from_file_location('wolf_gen_patch',PATCHER)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
fixture = '#include <QMenu>\nvoid PlacesView::contextMenuEvent(QContextMenuEvent* event) {}\n' + mod.VOLUME_ANCHOR
out=mod.transform(fixture)
assert '#include <QProcess>' in out
assert out.count('Formatar unidade USB') == 1
assert 'QProcess::startDetached' in out
assert 'QStringLiteral("--device")' in out
assert 'G_VOLUME_IDENTIFIER_KIND_UNIX_DEVICE' in out
for bad in (fixture.replace('case PlacesModelItem::Volume:', 'case PlacesModelItem::Mount:'),fixture+mod.VOLUME_ANCHOR):
    try: mod.transform(bad)
    except ValueError: pass
    else: raise AssertionError('A fonte incompatível deveria ter sido recusada')
path=ROOT/'experimental/integracoes-wolf/wolf-format-removable-device-experimental'
text=path.read_text()
assert "group.add_argument('--device'" in text
assert "candidate = _find_candidate(args.device)" in text
assert "return gui(initial=candidate['device'])" in text
print('[OK] Preview2: gerador do patch C++ e validação de dispositivo USB (sem formatar)')
