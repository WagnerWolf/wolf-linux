"""Auditoria SOMENTE LEITURA das integrações Wolf Linux.

Nenhum estado 'compatível' é inferido de uma versão de pacote simplesmente presente.
Um pacote customizado precisa distribuir um manifesto, de propriedade verificada via Pacman,
e coincidir exatamente com a versão registrada; um hook pendente força revisão.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess

MANIFEST = Path('/usr/share/wolf-linux/integrations/libfm-qt-usb-format.json')
PENDING = Path('/var/lib/wolf-linux/integrations/libfm-qt.changed')


@dataclass(frozen=True)
class IntegrationResult:
    name: str
    status: str
    description: str
    details: str


def _run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=8,
                              check=False, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None


def _pkg_version(name):
    result = _run(['pacman', '-Q', name])
    if result is None or result.returncode != 0:
        return None
    line = result.stdout.strip().split()
    return line[1] if len(line) == 2 and line[0] == name else None


def _owned_by_libfm(path):
    result = _run(['pacman', '-Qoq', str(path)])
    if result is None or result.returncode != 0:
        return False
    return result.stdout.strip() == 'libfm-qt'


def _safe_manifest(path):
    try:
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 32_768:
            return None
        obj = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(obj, dict):
            return None
        return obj
    except (OSError, ValueError, UnicodeError):
        return None


def check_libfm(*, manifest=MANIFEST, pending=PENDING):
    version = _pkg_version('libfm-qt')
    if version is None:
        return IntegrationResult('PCManFM-Qt · Formatação USB', 'Indisponível',
                                 'libfm-qt não identificado pelo Pacman.',
                                 'Verifique a instalação do PCManFM-Qt.')
    pending_event = pending.is_file()
    # A revisão compilada/confirmada no hardware tem esta identificação.
    # Pacote/versionamento NÃO provam que a janela do menu funciona.
    if version == '2.4.0-4.1' and not manifest.is_file():
        formatter = Path('/usr/local/bin/wolf-format-removable')
        has_device = (formatter.is_file() and not formatter.is_symlink() and
                      b'--device' in formatter.read_bytes()[:100000])
        if pending_event:
            return IntegrationResult('PCManFM-Qt · Formatação USB', 'Revisar',
                'O Pacman registrou uma atualização de libfm-qt.',
                'Verifique a compatibilidade antes de continuar usando a integração Wolf.')
        return IntegrationResult('PCManFM-Qt · Formatação USB',
            'Detectada' if has_device else 'Incompleta',
            'Pacote Wolf localizado; confirmação gráfica e versão do formatador são necessárias.'
            if has_device else 'O formatador não reconhece --device.',
            f'libfm-qt {version}; suporte --device: {"sim" if has_device else "não"}.')
    data = _safe_manifest(manifest)
    if not data:
        message = ('O hook registrou uma atualização de libfm-qt. ' if pending_event else '')
        return IntegrationResult('PCManFM-Qt · Formatação USB', 'Pendente',
                                 'Extensão do menu de dispositivos ainda não instalada.',
                                 message + f'libfm-qt instalado: {version}. O formatador atual continua disponível no menu de aplicativos.')

    # Autodeclarações não bastam: precisa haver manifesto incorporado e possuído pelo pacote customizado.
    if not _owned_by_libfm(manifest):
        return IntegrationResult('PCManFM-Qt · Formatação USB', 'Revisar',
                                 'Manifesto não pertence ao pacote libfm-qt.',
                                 'Não é possível comprovar a origem da integração.')
    pkg_match = (data.get('package') == 'libfm-qt' and
                 data.get('installed_version') == version and
                 data.get('feature') == 'places-usb-format' and
                 data.get('validated') is True and
                 isinstance(data.get('build_id'), str) and len(data['build_id']) >= 8)
    if not pkg_match or pending_event:
        return IntegrationResult('PCManFM-Qt · Formatação USB', 'Revisar',
                                 'Versão ou validação da integração exige revisão.',
                                 f'Pacote: {version}. Registro de atualização pendente: {"sim" if pending_event else "não"}.')
    return IntegrationResult('PCManFM-Qt · Formatação USB', 'Validada',
                             'Pacote Wolf e manifesto coincidem com a versão instalada.',
                             f'Pacote libfm-qt: {version}. Validação declarada no manifesto da compilação Wolf.')


def check_all():
    results = [check_libfm()]
    formatter = shutil.which('wolf-format-removable') or '/usr/local/bin/wolf-format-removable'
    if os.path.isfile(formatter):
        results.append(IntegrationResult('Formatador USB Wolf', 'Disponível',
                       'Utilitário de formatação localizado.',
                       f'{formatter} · a presença do arquivo não comprova a formatação real.'))
    else:
        results.append(IntegrationResult('Formatador USB Wolf', 'Ausente',
                       'Utilitário não encontrado.', 'O formatador não será instalado pela auditoria.'))
    cc = shutil.which('wolf-control-center') or '/usr/local/bin/wolf-control-center'
    if os.path.isfile(cc):
        results.append(IntegrationResult('Wolf Control Center', 'Disponível',
                       'Lançador do Control Center localizado.',
                       f'{cc} · monitores e painéis requerem validação gráfica independente.'))
    else:
        results.append(IntegrationResult('Wolf Control Center', 'Ausente',
                       'Lançador não encontrado.', 'A auditoria não modifica atalhos.'))
    return results


def format_report(results=None):
    results = check_all() if results is None else results
    lines = ['=== INTEGRAÇÕES WOLF · VERIFICAÇÃO SOMENTE LEITURA ===']
    for result in results:
        lines += [f'[{result.status}] {result.name}', f'  {result.description}', f'  {result.details}']
    lines.append('Nenhuma correção ou atualização foi executada.')
    return '\n'.join(lines)
