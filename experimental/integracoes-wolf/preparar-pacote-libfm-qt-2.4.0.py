#!/usr/bin/env python3
"""Prepare um diretório de build Arch do libfm-qt 2.4.0-4 com patch Wolf.

Não executa makepkg, pkgctl, pacman, sudo, nem instala arquivos.
O pacote gerado, se compilado, é EXPERIMENTAL e NÃO é validado.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import importlib.util

DIR = Path(__file__).resolve().parent
PATCHER = DIR / 'gerar-patch-libfm-qt-2.4.0.py'


def load_patcher():
    spec = importlib.util.spec_from_file_location('wolf_patch_generator', PATCHER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def verify_recipe(s: str) -> None:
    # Fail-closed: an unexpected upstream PKGBUILD must be reviewed manually.
    requirements = {
        'nome': r'(?m)^pkgname=libfm-qt\s*$',
        'versão': r'(?m)^pkgver=2\.4\.0\s*$',
        'revisão': r'(?m)^pkgrel=4\s*$',
        'fonte oficial': r'(?s)source=\(.*?(?:libfm-qt|\$\{?pkgname\}?)[^\n]*(?:2\.4\.0|\$\{?pkgver\}?)',
        'checksum': r'(?m)^sha512sums=\(',
        'compilação': r'(?m)^build\(\)\s*\{',
        'empacotamento': r'(?m)^package\(\)\s*\{',
    }
    missing = [name for name, regex in requirements.items() if not re.search(regex, s)]
    if missing:
        raise ValueError('PKGBUILD inesperado; revisão manual necessária: ' + ', '.join(missing))
    if re.search(r'(?m)^prepare\(\)\s*\{', s):
        raise ValueError('PKGBUILD já tem prepare(); integrar patch manualmente antes de compilar.')
    if 'wolf-places-usb.patch' in s or 'WOLF-EXPERIMENTAL' in s:
        raise ValueError('PKGBUILD já parece modificado pela Wolf.')
    if re.search(r'(?m)^(?:pkgname|pkgbase|pkgver|pkgrel)\+=', s):
        raise ValueError('PKGBUILD dinâmico inesperado.')


def prepare(source: Path, packaging: Path, out: Path):
    if source.expanduser().is_symlink() or packaging.expanduser().is_symlink():
        raise ValueError('Origem não pode ser um link simbólico.')
    source = source.expanduser().resolve(strict=True)
    packaging = packaging.expanduser().resolve(strict=True)
    if source.name != 'placesview.cpp' or source.parent.name != 'src':
        raise ValueError('Informe o src/placesview.cpp original da tag 2.4.0.')
    if source.is_symlink() or not source.is_file():
        raise ValueError('Fonte inválida.')
    repo = source.parent.parent
    def git_cmd(*args, input=None):
        return subprocess.run(['git', '-C', str(repo), *args], input=input,
                              text=True, capture_output=True, timeout=12)
    try:
        tag = git_cmd('tag', '--points-at', 'HEAD')
        status = git_cmd('status', '--porcelain', '--', 'src/placesview.cpp')
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValueError('Não foi possível verificar a tag/source Git.') from exc
    if tag.returncode or '2.4.0' not in tag.stdout.splitlines() or status.returncode or status.stdout.strip():
        raise ValueError('Fonte deve ser a tag Git 2.4.0 exata e placesview.cpp deve estar sem alterações.')
    if not packaging.is_dir() or packaging.is_symlink():
        raise ValueError('Diretório da receita do Arch inválido.')
    recipe = packaging / 'PKGBUILD'
    if not recipe.is_file() or recipe.is_symlink():
        raise ValueError('PKGBUILD oficial ausente.')
    original_recipe = recipe.read_text(encoding='utf-8')
    verify_recipe(original_recipe)
    module = load_patcher()
    original = source.read_text(encoding='utf-8')
    changed = module.transform(original)
    import difflib
    patch = ''.join(difflib.unified_diff(original.splitlines(keepends=True), changed.splitlines(keepends=True),
        fromfile='a/src/placesview.cpp', tofile='b/src/placesview.cpp'))
    if not patch:
        raise ValueError('Patch vazio.')
    try:
        check = git_cmd('apply', '--check', '-', input=patch)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ValueError('Não foi possível testar o patch contra a fonte Git.') from exc
    if check.returncode:
        raise ValueError('git apply --check falhou na fonte 2.4.0: ' + check.stderr.strip()[:700])
    out = out.expanduser().absolute()
    if out.exists() or out.is_symlink():
        raise ValueError(f'Destino já existe; não sobrescrever: {out}')
    if out == packaging or packaging in out.parents or out in packaging.parents:
        raise ValueError('Destino deve ser separado da receita oficial.')
    digest = hashlib.sha512(patch.encode('utf-8')).hexdigest()
    # No auto-validation marker: audit should continue to report PENDENTE.
    additions = f'''
# WOLF-EXPERIMENTAL: substitui apenas a mesma revisao 2.4.0-4 do Arch.
# Nao instala nem declara integracao validada no Wolf Package Manager.
pkgrel=4.1
source+=("wolf-places-usb.patch")
sha512sums+=("{digest}")
prepare() {{
  cd "$srcdir/libfm-qt-$pkgver"
  patch --forward -Np1 -i "$srcdir/wolf-places-usb.patch"
}}
'''
    # Copy only packaging inputs, not potentially huge cloned histories/build outputs.
    out.mkdir(parents=True, exist_ok=False)
    (out / 'PKGBUILD').write_text(original_recipe.rstrip() + '\n' + additions, encoding='utf-8')
    (out / 'wolf-places-usb.patch').write_text(patch, encoding='utf-8')
    if (packaging / 'keys').is_dir():
        shutil.copytree(packaging / 'keys', out / 'keys', symlinks=False)
    # Arch PKGBUILD can refer to companion files; do not silently omit them.
    sidecars = [p for p in packaging.iterdir() if p.is_file() and p.name not in ('PKGBUILD', '.SRCINFO')
                and not p.name.endswith(('.pkg.tar.zst', '.pkg.tar.xz', '.log', '.tar.xz', '.tar.gz'))]
    for item in sidecars:
        if item.is_symlink():
            raise ValueError(f'Não seguir symlink em arquivo de receita: {item}')
        shutil.copy2(item, out / item.name)
    (out / 'WOLF-BUILD-INFO.txt').write_text(
        f'WOLF EXPERIMENTAL - NAO INSTALAR NO COMPUTADOR PRINCIPAL\n'
        f'Pacote base exigido: libfm-qt 2.4.0-4\n'
        f'Pacote experimental gerado: libfm-qt 2.4.0-4.1\n'
        f'Patch sha512: {digest}\n'
        f'Fonte de referência: tag upstream 2.4.0, placesview.cpp\n'
        'Sem manifesto validated=true; auditoria Wolf deve continuar pendente.\n'
        'Build: em VM Arch, executar pkgctl build neste diretório.\n'
        'NÃO usar pkgctl build -i ou sudo pacman -U na estação principal.\n'
        'Reverter em VM: sudo pacman -S libfm-qt após confirmar versão do repositório.\n',
        encoding='utf-8')
    return out


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', required=True, type=Path, help='Clone upstream src/placesview.cpp da tag 2.4.0')
    p.add_argument('--packaging', required=True, type=Path, help='Checkout da receita oficial Arch libfm-qt 2.4.0-4')
    p.add_argument('--output', required=True, type=Path, help='Pasta NOVA para compilar, sem sobrescrever')
    a = p.parse_args(argv)
    try:
        created = prepare(a.source, a.packaging, a.output)
    except (ValueError, OSError) as exc:
        p.exit(2, '[BLOQUEADO] ' + str(exc) + '\n')
    print('[OK] Receita experimental gerada:', created)
    print('[OK] Patch local com SHA512. Nenhuma biblioteca ou pacote instalado.')
    print('[PRÓXIMO] Em VM Arch, revise o PKGBUILD e execute: cd', created, '&& pkgctl build')

if __name__ == '__main__':
    main()
