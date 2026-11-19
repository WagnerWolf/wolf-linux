#!/usr/bin/env python3
"""Wolf libfm-qt reproducible builder: official 2.4.0 sources + all Wolf patches.

No previous local source/build is required. No silent upstream upgrades. The default
command prepares and builds a package; never installs or alters the running LXQt.
"""
from __future__ import annotations
import argparse
from datetime import datetime
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
VERSION = '2.4.0'
BASE_REL = '4'
WOLF_REL = '4.2'
ARCH_URL = 'https://gitlab.archlinux.org/archlinux/packaging/packages/libfm-qt.git'
UPSTREAM_URL = 'https://github.com/lxqt/libfm-qt.git'
UPSTREAM_COMMIT_PREFIX = '4294f29'  # signed upstream release tag 2.4.0
FILES = ('PKGBUILD', 'wolf-places-usb.patch', 'wolf-symlinks-native.patch',
         'wolf-legacy-getpgid.patch', 'FindMenuCache.cmake')


def run(args: list[str], *, cwd: Path | None = None, capture=False, timeout=600) -> subprocess.CompletedProcess:
    print(' +', ' '.join(map(str, args)), flush=True)
    return subprocess.run([str(x) for x in args], cwd=str(cwd) if cwd else None,
                          text=True, check=True, capture_output=capture, timeout=timeout)


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    if spec is None or spec.loader is None:
        raise RuntimeError('Não foi possível carregar gerador ' + name)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def git(repo: Path, *args: str) -> str:
    return run(['git', '-C', str(repo), *args], capture=True).stdout.strip()


def verify_prerequisites(*, need_build: bool):
    needed = ['git', 'patch', 'tar', 'pacman'] + (['makepkg'] if need_build else [])
    missing = [x for x in needed if not shutil.which(x)]
    if missing:
        raise RuntimeError('Comandos ausentes: ' + ', '.join(missing) +
                           '. No Arch: sudo pacman -S --needed base-devel git')
    if os.geteuid() == 0:
        raise RuntimeError('Não execute como root/sudo: makepkg precisa de usuário comum.')
    if need_build and sys.platform != 'linux':
        raise RuntimeError('Compilação requer Linux/Arch.')


def get_tag_source(target: Path, *, clone_url: str = UPSTREAM_URL) -> tuple[Path, str]:
    run(['git', 'clone', '--depth', '1', '--branch', VERSION, '--', clone_url, str(target)], timeout=240)
    full = git(target, 'rev-parse', 'HEAD')
    tag = git(target, 'tag', '--points-at', 'HEAD').splitlines()
    if not full.startswith(UPSTREAM_COMMIT_PREFIX) or VERSION not in tag:
        raise RuntimeError('Tag 2.4.0 upstream não corresponde ao commit homologado: ' + full)
    if git(target, 'status', '--porcelain'):
        raise RuntimeError('Árvore upstream suja; interrompido.')
    for name in ('placesview.cpp', 'filemenu.cpp', 'foldermenu.cpp'):
        if not (target / 'src' / name).is_file():
            raise RuntimeError('Arquivo upstream ausente: src/' + name)
    return target, full


def is_arch_recipe(recipe: str) -> bool:
    # Fail closed if the official packaging changes its recipe shape.
    required = [r'(?m)^pkgname=libfm-qt\s*$',
                r'(?m)^pkgver=2\.4\.0\s*$',
                r'(?m)^pkgrel=4\s*$',
                r'(?m)^sha512sums=\(',
                r'(?m)^build\(\)\s*\{',
                r'(?m)^package\(\)\s*\{',
                r'(?s)source=\(.*?(?:libfm-qt|\$\{?pkgname\}?)[^\n]*(?:2\.4\.0|\$\{?pkgver\}?)']
    return (all(re.search(p, recipe) for p in required)
            and not re.search(r'(?m)^prepare\(\)\s*\{', recipe)
            and 'wolf-places-usb.patch' not in recipe)


def select_arch_revision(repo: Path) -> tuple[str, str]:
    # Prefer exact Arch package tag, if any, otherwise historic commit search.
    refs = git(repo, 'tag', '--list', VERSION + '-' + BASE_REL).splitlines()
    commits = []
    if VERSION + '-' + BASE_REL in refs:
        commits.append('refs/tags/' + VERSION + '-' + BASE_REL)
    commits += git(repo, 'log', '--all', '--format=%H', '--', 'PKGBUILD').splitlines()
    for n, commit in enumerate(dict.fromkeys(commits)):
        if n >= 1000:
            break
        try:
            txt = git(repo, 'show', f'{commit}:PKGBUILD')
        except subprocess.CalledProcessError:
            continue
        if is_arch_recipe(txt):
            return git(repo, 'rev-parse', f'{commit}^{{commit}}'), txt + '\n'
    raise RuntimeError('Não encontrei receita oficial libfm-qt 2.4.0-4 no histórico do Arch. '
                       'Não usarei PKGBUILD de outra versão.')


def fetch_arch_recipe(target: Path, *, url: str = ARCH_URL) -> tuple[Path, str, str]:
    # Git history, not the potentially newer PKGBUILD currently on Arch Linux.
    run(['git', 'clone', '--filter=blob:none', '--no-checkout', '--', url, str(target)], timeout=300)
    commit, recipe = select_arch_revision(target)
    return target, commit, recipe


def patch_text(name: str, orig: str, changed: str) -> str:
    return ''.join(difflib.unified_diff(orig.splitlines(keepends=True),
                  changed.splitlines(keepends=True),
                  fromfile='a/src/' + name, tofile='b/src/' + name, n=4))


def generate_patches(src: Path) -> dict[str, str]:
    usb_gen, links_gen = load('patch_usb'), load('patch_links')
    def read(name):
        f = src / 'src' / name
        if f.is_symlink() or not f.is_file():
            raise RuntimeError('Arquivo de fonte inesperado: ' + str(f))
        return f.read_text(encoding='utf-8')
    usb_orig = read('placesview.cpp')
    usb = patch_text('placesview.cpp', usb_orig, usb_gen.transform(usb_orig))
    links = []
    for n, fun in (('filemenu.cpp', links_gen.transform_filemenu),
                   ('foldermenu.cpp', links_gen.transform_foldermenu)):
        orig = read(n)
        links.append(patch_text(n, orig, fun(orig)))
    # Fix a glibc feature-test regression in this pinned upstream 2.4.0 file.
    # Unlike CMAKE_TOOLCHAIN_FILE, an actual source patch is independent of
    # the build environment and survives makepkg -C clean extraction.
    legacy = read('core/legacy/fm-app-info.c')
    legacy_anchor = '#include "fm-app-info.h"'
    if legacy.count(legacy_anchor) != 1 or 'getpgid(getppid())' not in legacy:
        raise RuntimeError('Código upstream de getpgid desconhecido; parar para revisão.')
    legacy_new = legacy.replace(legacy_anchor,
        '#ifndef _DEFAULT_SOURCE\n#define _DEFAULT_SOURCE 1\n#endif\n'
        '#include <unistd.h>\n' + legacy_anchor, 1)
    legacy_patch = patch_text('core/legacy/fm-app-info.c', legacy, legacy_new)
    out = {'wolf-places-usb.patch': usb, 'wolf-symlinks-native.patch': ''.join(links),
           'wolf-legacy-getpgid.patch': legacy_patch}
    for name, contents in out.items():
        if not contents:
            raise RuntimeError('Patch vazio: ' + name)
        chk = subprocess.run(['patch', '--batch', '--fuzz=0', '-p1', '--dry-run'],
                             cwd=src, input=contents, text=True, capture_output=True, timeout=30)
        if chk.returncode:
            raise RuntimeError(f'Patch {name} incompatível com fonte 2.4.0: '\
                               + (chk.stdout + chk.stderr)[-900:])
    return out


def archive_arch_files(repo: Path, commit: str, out: Path):
    # Extract repository tree (with original license/sidecar build inputs), excluding .git.
    out.mkdir(parents=True, exist_ok=False)
    archive = subprocess.Popen(['git', '-C', str(repo), 'archive', '--format=tar', commit],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    extract = subprocess.run(['tar', '-x', '-C', str(out), '--no-same-owner', '--no-same-permissions'],
                             stdin=archive.stdout, capture_output=True, text=True, timeout=60)
    archive.stdout.close()
    stderr = archive.stderr.read().decode('utf-8', 'replace')
    archive.stderr.close()
    code = archive.wait(timeout=60)
    if code or extract.returncode:
        raise RuntimeError('Falha ao extrair receita histórica Arch: ' + stderr + extract.stderr)
    if (out / 'PKGBUILD').is_symlink() or not (out / 'PKGBUILD').is_file():
        raise RuntimeError('Receita Arch não encontrada no arquivo extraído')


def validate_menu_cache_module(path: Path) -> bytes:
    """Only a reviewed LXQt 2.4.0-style Find module is accepted as source."""
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('FindMenuCache.cmake indisponível ou symlink: ' + str(path))
    body = path.read_bytes()
    if not (100 < len(body) < 64_000
            and body.startswith(b'# Distributed under the OSI-approved BSD 3-Clause License.')
            and b'find_package_handle_standard_args(MenuCache' in body
            and b'pkg_check_modules(PC_MENUCACHE libmenu-cache)' in body):
        raise RuntimeError('FindMenuCache.cmake não corresponde ao módulo LXQt 2.4.0 esperado.')
    return body


def prepare_recipe(original: str, patches: dict[str, str], *, rel: str,
                   menu_cache_sha512: str) -> str:
    if not is_arch_recipe(original):
        raise RuntimeError('PKGBUILD Arch desconhecido; não acrescentar patches.')
    if rel not in ('4.1', '4.2'):
        raise RuntimeError('Revisão Wolf inesperada')
    if not re.fullmatch('[a-f0-9]{128}', menu_cache_sha512):
        raise RuntimeError('SHA512 de MenuCache ausente ou inválido')
    names = (['wolf-places-usb.patch']
             + (['wolf-symlinks-native.patch'] if rel == '4.2' else [])
             + ['wolf-legacy-getpgid.patch'])
    sha = [hashlib.sha512(patches[n].encode('utf-8')).hexdigest() for n in names]
    commands = '\n'.join(f'  patch --forward --fuzz=0 -Np1 -i "$srcdir/{n}"' for n in names)
    suffix = ('\n# WOLF-CUSTOM: libfm-qt upstream 2.4.0, patches versionados e integrais\n'
              f'pkgrel={rel}\n'
              'source+=(' + ' '.join('"' + n + '"' for n in [*names, 'FindMenuCache.cmake']) + ')\n'
              'sha512sums+=(' + ' '.join('"' + h + '"' for h in [*sha, menu_cache_sha512]) + ')\n'
              'prepare() {\n'
              '  cd "$srcdir/libfm-qt-$pkgver"\n'
              + commands + '\n'
              # The upstream project explicitly searches ${PROJECT_SOURCE_DIR}/cmake.
              # This makes lookup independent of toolchain env and makepkg clean builds.
              '  test ! -e "cmake/FindMenuCache.cmake" || { echo "WOLF: módulo já existe; revisar upstream" >&2; return 1; }\n'
              '  install -Dm644 "$srcdir/FindMenuCache.cmake" "cmake/FindMenuCache.cmake"\n'
              '}\n')
    return original.rstrip() + '\n' + suffix


def prepare_build(recipe_repo: Path, commit: str, original: str,
                  patches: dict[str, str], out: Path, rel: str,
                  *, menu_cache_module: Path):
    module_body = validate_menu_cache_module(menu_cache_module)
    archive_arch_files(recipe_repo, commit, out)
    archived = (out / 'PKGBUILD').read_text(encoding='utf-8')
    if archived.strip() != original.strip():
        raise RuntimeError('Receita extraída não corresponde ao commit auditado.')
    (out / 'PKGBUILD').write_text(prepare_recipe(
        original, patches, rel=rel,
        menu_cache_sha512=hashlib.sha512(module_body).hexdigest()), encoding='utf-8')
    for patch_name in ('wolf-places-usb.patch', 'wolf-symlinks-native.patch', 'wolf-legacy-getpgid.patch'):
        if patch_name in patches and (rel == '4.2' or patch_name != 'wolf-symlinks-native.patch'):
            (out / patch_name).write_text(patches[patch_name], encoding='utf-8')
    (out / 'FindMenuCache.cmake').write_bytes(module_body)
    return out


def find_rollback(workdir: Path) -> Path | None:
    found = list((workdir / 'rollback-4.1').glob('libfm-qt-2.4.0-4.1-*.pkg.tar.*'))
    found.extend(Path('/var/cache/pacman/pkg').glob('libfm-qt-2.4.0-4.1-*.pkg.tar.*'))
    found.extend((Path.home() / 'wolf-libfm-build').glob('**/libfm-qt-2.4.0-4.1-*.pkg.tar.*'))
    found = [x for x in found if x.is_file() and not x.name.endswith('.sig')]
    return found[0] if found else None


def check_installed_version():
    ver = run(['pacman', '-Q', 'libfm-qt'], capture=True).stdout.strip()
    if ver not in ('libfm-qt 2.4.0-4.1', 'libfm-qt 2.4.0-4.2'):
        raise RuntimeError('Versão instalada não é Wolf 2.4.0-4.1/4.2: ' + ver +
                           '. Atualização upstream requer revisão de todos os patches.')
    return ver


def perform_build(build_dir: Path):
    run(['makepkg', '--verifysource'], cwd=build_dir, timeout=300)
    run(['makepkg', '-s', '-C'], cwd=build_dir, timeout=3600)
    matches = list(build_dir.glob('libfm-qt-2.4.0-4.2-*.pkg.tar.*'))
    if len(matches) != 1:
        raise RuntimeError('Esperava um único pacote 4.2 após makepkg, encontrei: ' + str(matches))
    package = matches[0]
    full = run(['pacman', '-Qp', str(package)], capture=True).stdout.strip()
    if full != 'libfm-qt 2.4.0-4.2':
        raise RuntimeError('Versão inesperada no pacote compilado: ' + full)
    return package


def build_rollback(repo: Path, commit: str, original: str, patches: dict[str,str],
                   target: Path, menu_cache_module: Path):
    prepare_build(repo, commit, original, patches, target, '4.1',
                  menu_cache_module=menu_cache_module)
    run(['makepkg', '--verifysource'], cwd=target, timeout=300)
    run(['makepkg', '-s', '-C'], cwd=target, timeout=3600)
    packages = list(target.glob('libfm-qt-2.4.0-4.1-*.pkg.tar.*'))
    if len(packages) != 1:
        raise RuntimeError('Não foi possível construir pacote de rollback 4.1.')
    pkg = packages[0]
    if run(['pacman', '-Qp', str(pkg)], capture=True).stdout.strip() != 'libfm-qt 2.4.0-4.1':
        raise RuntimeError('Pacote de rollback não está na versão 4.1.')
    return pkg


def install_package(package: Path, rollback: Path):
    # Preflight before touching the Package Manager or the installed libfm-qt.
    helper = Path.home() / '.local/bin/wolf-symlink-actions'
    actions = Path.home() / '.local/share/file-manager/actions'
    for target in (helper, *(actions / n for n in ('wolf-link-here.desktop',
                      'wolf-link-choose.desktop', 'wolf-paste-link-folder.desktop'))):
        if target.is_symlink():
            raise RuntimeError('Arquivo inesperado é link simbólico; revisão manual antes de instalar: ' + str(target))
    if not (HERE / 'wolf-symlink-actions.py').is_file():
        raise RuntimeError('Backend Wolf de links ausente.')
    if not shutil.which('sudo'):
        raise RuntimeError('sudo indisponível para instalação explícita')
    guard = Path('/usr/local/lib/wolf-linux/package-manager/wolfpkg/upgrade_guard.py')
    if not guard.is_file():
        raise RuntimeError('Wolf Package Manager guard não encontrado: ' + str(guard) +
                           '; instalação bloqueada até resolver proteção do pacote.')
    # Check exact Guard 0.3.7 structures BEFORE any mutation.
    current = guard.read_text(encoding='utf-8')
    if "active = installed in (WOLF_VERSION, '2.4.0-4.2')" not in current:
        if ("WOLF_VERSION = '2.4.0-4.1'" not in current or
            'active = installed == WOLF_VERSION' not in current):
            raise RuntimeError('Wolf Package Manager guard incompatível; não instalar 4.2.')
    ignore = run(['pacman-conf', 'IgnorePkg'], capture=True).stdout
    if not re.search(r'\blibfm-qt\b', ignore):
        raise RuntimeError('IgnorePkg não protege libfm-qt. Instalação bloqueada.')
    if not rollback.is_file():
        raise RuntimeError('Arquivo 4.1 de rollback não encontrado.')
    if run(['pacman', '-Qp', str(rollback)], capture=True).stdout.strip() != 'libfm-qt 2.4.0-4.1':
        raise RuntimeError('Rollback não é um pacote libfm-qt 2.4.0-4.1 válido.')
    # Upgrade guard first so new package remains protected. Backup script handles it.
    if "active = installed == WOLF_VERSION" in current:
        run(['sudo', sys.executable, str(HERE / 'ajustar-guard-pm.py'), 'apply', '--path', str(guard)])
    run(['sudo', 'pacman', '-U', '--', str(package)], timeout=600)
    run([sys.executable, str(HERE / 'instalar-helper.py')], timeout=60)
    print('[OK] Pacote instalado e helper preparado. Reinicie a sessão LXQt para carregar a nova biblioteca.')
    print('[REVERSÃO] sudo pacman -U', rollback)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--destino', type=Path, default=Path.home() / 'wolf-libfm-build',
                    help='Pasta que receberá uma nova subpasta única; preserva todos os builds anteriores.')
    ap.add_argument('--preparar-apenas', action='store_true',
                    help='Clona e gera patches/PKGBUILD mas não executa makepkg.')
    ap.add_argument('--instalar', action='store_true',
                    help='Instala somente após compilar, guardar rollback 4.1 e revisar guard do Package Manager.')
    args = ap.parse_args(argv)
    if args.preparar_apenas and args.instalar:
        ap.error('--instalar não pode ser combinado com --preparar-apenas')
    root = args.destino.expanduser().absolute()
    try:
        verify_prerequisites(need_build=not args.preparar_apenas)
        # Always stage the reviewed upstream FindMenuCache module into PKGBUILD
        # sources. CMAKE_TOOLCHAIN_FILE is intentionally NOT relied upon.
        compat_dir = Path.home() / '.cache/wolf-linux/menucache-cmake-2.4'
        load('compatibilidade-lxqt-2.5').setup(compat_dir)
        menu_cache_module = compat_dir / 'FindMenuCache.cmake'
        validate_menu_cache_module(menu_cache_module)
        print('[WOLF] FindMenuCache com checksum será incluído no PKGBUILD:', menu_cache_module)
        check_installed_version()
        if root.is_symlink():
            raise RuntimeError('Pasta de trabalho não pode ser link simbólico')
        root.mkdir(parents=True, exist_ok=True)
        work = root / ('wolf-libfm-2.4.0-4.2-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        work.mkdir(mode=0o700)
        print('[WOLF] Diretório novo:', work)
        source, source_commit = get_tag_source(work / 'upstream')
        arch, arch_commit, original = fetch_arch_recipe(work / 'arch-packaging')
        patches = generate_patches(source)
        build = prepare_build(arch, arch_commit, original, patches, work / 'build-4.2',
                              '4.2', menu_cache_module=menu_cache_module)
        manifest = {'upstream': UPSTREAM_URL, 'tag': VERSION,
                    'upstream_commit': source_commit, 'arch_packaging': ARCH_URL,
                    'arch_commit': arch_commit, 'base': '2.4.0-4', 'wolf': '2.4.0-4.2',
                    'patches_sha512': {k: hashlib.sha512(v.encode()).hexdigest() for k,v in patches.items()},
                    'FindMenuCache_sha512': hashlib.sha512(menu_cache_module.read_bytes()).hexdigest()}
        (work / 'MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print('[OK] Clone upstream verificado e receita histórica Arch auditada.')
        print('[OK] Três patches Wolf (USB, links, getpgid) recriados com --dry-run (sem fuzz).')
        print('[OK] FindMenuCache.cmake inserido como fonte verificada e copiado em prepare().')
        print('[OK] Receita única contém USB + menus de links simbólicos.')
        if args.preparar_apenas:
            print('[PREPARADO] Para compilar: cd', build, '&& makepkg --verifysource && makepkg -s -C')
            return 0
        package = perform_build(build)
        print('[OK] Pacote 4.2 compilado e verificado:', package)
        rollback = None
        if args.instalar:
            print('[WOLF] Compilando também pacote 4.1 de rollback, com patch USB verificado.')
            rollback = build_rollback(arch, arch_commit, original, patches,
                                      work / 'rollback-4.1', menu_cache_module)
        if args.instalar:
            install_package(package, rollback)
        else:
            print('[SEGURO] Não instalei nada. Para compilar+instalar em execução futura:')
            print('   python3', HERE / 'reconstruir-libfm-wolf.py', '--instalar')
            print('[INFO] Guarde este pacote 4.2 e o manifesto antes de homologar na sessão física.')
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as e:
        print('[BLOQUEADO]', e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
