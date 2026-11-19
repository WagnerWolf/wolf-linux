#!/usr/bin/env python3
"""Gera um patch de código-fonte (sem compilar/instalar) para libfm-qt 2.4.0.

Valida âncoras textuais contra a versão upstream; recusa arquivos divergentes.
O formatador Wolf valida novamente a unidade, mesmo quando aberto no menu.
"""
import argparse
import difflib
from pathlib import Path
import sys

INCLUDE_ANCHOR = '#include <QMenu>\n'
VOLUME_ANCHOR = """        case PlacesModelItem::Volume: {
            PlacesModelVolumeItem* volumeItem = static_cast<PlacesModelVolumeItem*>(item);
"""
ADDITION = """            // Wolf Linux experimental: somente indica o dispositivo ao formatador.
            // Toda verificacao de USB, montagem e seguranca permanece no backend.
            CStrPtr wolfDevice{g_volume_get_identifier(volumeItem->volume(), G_VOLUME_IDENTIFIER_KIND_UNIX_DEVICE)};
            if(wolfDevice && g_str_has_prefix(wolfDevice.get(), "/dev/")) {
                const QString devicePath = QString::fromUtf8(wolfDevice.get());
                QAction* wolfFormat = menu->addAction(QIcon::fromTheme(QStringLiteral("drive-removable-media")),
                                                      QStringLiteral("Formatar unidade USB…"));
                connect(wolfFormat, &QAction::triggered, this, [devicePath]() {
                    // Retorna do menu Qt6 antes de abrir a janela externa.
                    QTimer::singleShot(0, [devicePath]() {
                        QProcess::startDetached(QStringLiteral("/usr/local/bin/wolf-format-removable"),
                                                QStringList{QStringLiteral("--device"), devicePath});
                    });
                });
                menu->addSeparator();
            }
"""

def transform(source):
    if source.count(INCLUDE_ANCHOR) != 1 or source.count(VOLUME_ANCHOR) != 1:
        raise ValueError('Fonte incompatível: âncoras do libfm-qt 2.4.0 não encontradas uma única vez.')
    if 'Wolf Linux experimental: somente indica' in source:
        raise ValueError('A modificação Wolf já aparece na fonte.')
    if 'void PlacesView::contextMenuEvent(QContextMenuEvent* event)' not in source:
        raise ValueError('Não parece ser placesview.cpp de libfm-qt.')
    return (source.replace(INCLUDE_ANCHOR, INCLUDE_ANCHOR+'#include <QProcess>\n',1)
                  .replace(VOLUME_ANCHOR,VOLUME_ANCHOR+ADDITION,1))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path, help='src/placesview.cpp original da tag 2.4.0')
    parser.add_argument('--output',type=Path,help='arquivo .patch (não modifica a fonte)')
    args=parser.parse_args()
    if not args.source.is_file() or args.source.is_symlink(): parser.error('Fonte ausente ou link simbólico.')
    original=args.source.read_text(encoding='utf-8')
    try: changed=transform(original)
    except ValueError as exc: parser.error(str(exc))
    diff=''.join(difflib.unified_diff(original.splitlines(True),changed.splitlines(True),
                                      fromfile='a/src/placesview.cpp',tofile='b/src/placesview.cpp'))
    if not diff: parser.error('Patch vazio.')
    print('[OK] Âncoras do libfm-qt 2.4.0 identificadas; alteração restrita a placesview.cpp.')
    if args.output:
        if args.output.is_symlink(): parser.error('Saída não pode ser link simbólico.')
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(diff,encoding='utf-8')
        print(f'[OK] Patch gerado em {args.output}; nenhum pacote instalado.')
    else: print('[INFO] Somente conferência. Use --output para gerar patch.')

if __name__=='__main__': main()
