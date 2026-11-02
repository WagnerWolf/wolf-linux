#!/usr/bin/env python3
"""Testes não destrutivos da etapa experimental de pacote personalizado libfm-qt."""
from pathlib import Path
import importlib.util
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT/'experimental/integracoes-wolf/preparar-pacote-libfm-qt-2.4.0.py'
spec = importlib.util.spec_from_file_location('wolf_build_prep', TOOL)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

RECIPE = '''pkgname=libfm-qt
pkgver=2.4.0
pkgrel=4
url=https://github.com/lxqt/libfm-qt
source=("https://github.com/lxqt/libfm-qt/releases/download/${pkgver}/libfm-qt-${pkgver}.tar.xz")
sha512sums=('SKIP')
build() {
  cmake -B build -S libfm-qt-$pkgver
}
package() {
  DESTDIR="$pkgdir" cmake --install build
}
'''
SOURCE = '''#include "placesview.h"
#include <QMenu>
#include <QTimer>
namespace Fm {
void PlacesView::contextMenuEvent(QContextMenuEvent* event) {
        switch(item->type()) {
        case PlacesModelItem::Volume: {
            PlacesModelVolumeItem* volumeItem = static_cast<PlacesModelVolumeItem*>(item);
            menu->addAction(action);
            break;
        }
        }
}
}
'''
with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    src = root/'libfm-qt/src/placesview.cpp'
    src.parent.mkdir(parents=True)
    src.write_text(SOURCE)
    subprocess.run(['git','init','-q',str(src.parent.parent)],check=True)
    subprocess.run(['git','-C',str(src.parent.parent),'add','src/placesview.cpp'],check=True)
    subprocess.run(['git','-C',str(src.parent.parent),'-c','user.name=Wolf Test',
                    '-c','user.email=test@example.invalid','commit','-qm','fixture'],check=True)
    subprocess.run(['git','-C',str(src.parent.parent),'tag','2.4.0'],check=True)
    pkg = root/'packaging'
    pkg.mkdir()
    (pkg/'PKGBUILD').write_text(RECIPE)
    (pkg/'keys').mkdir()
    (pkg/'keys'/'example.asc').write_text('test-key')
    stage = root/'wolf-build'
    m.prepare(src, pkg, stage)
    modified = (stage/'PKGBUILD').read_text()
    assert 'pkgrel=4.1' in modified
    assert 'wolf-places-usb.patch' in modified
    assert 'sha512sums+=' in modified
    assert 'WOLF-EXPERIMENTAL' in modified
    assert (stage/'keys/example.asc').is_file()
    assert not (stage/'usr/lib').exists()
    assert 'Sem manifesto validated=true' in (stage/'WOLF-BUILD-INFO.txt').read_text()
    result = subprocess.run(['bash','-n',str(stage/'PKGBUILD')],capture_output=True,text=True)
    assert result.returncode==0, result.stderr
    result = subprocess.run(['patch','--dry-run','-p1','-i',str(stage/'wolf-places-usb.patch')], cwd=src.parent.parent,
                            capture_output=True,text=True)
    assert result.returncode==0, result.stdout+result.stderr
    for version in ('2.4.1', '2.3.0'):
        try:
            m.verify_recipe(RECIPE.replace('pkgver=2.4.0', f'pkgver={version}'))
        except ValueError: pass
        else: raise AssertionError('Versão diferente deveria ser bloqueada')
    for rel in ('3', '5'):
        try: m.verify_recipe(RECIPE.replace('pkgrel=4',f'pkgrel={rel}'))
        except ValueError: pass
        else: raise AssertionError('Revisão diferente deveria ser bloqueada')
    try: m.prepare(src,pkg,stage)
    except ValueError: pass
    else: raise AssertionError('Não pode sobrescrever destino existente')
    try: m.verify_recipe(RECIPE+'prepare() { :; }\n')
    except ValueError: pass
    else: raise AssertionError('prepare preexistente deve ser revisado')
    assert not list(root.rglob('*.pkg.tar.zst'))
print('[OK] Preview4: fonte/PKGBUILD estritos, patch --dry-run, pacote não instalado e recusas de regressão')
