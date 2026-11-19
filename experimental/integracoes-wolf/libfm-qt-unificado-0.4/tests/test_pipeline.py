import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

def load(file, name):
    spec=importlib.util.spec_from_file_location(name, ROOT/file)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

build=load('reconstruir-libfm-wolf.py','wolf_builder_auto')
links=load('wolf-symlink-actions.py','wolf_symlinks_auto')
installer=load('instalar-helper.py','wolf_installer_auto')
patch_links=load('patch_links.py','wolf_patch_links_auto')

FILE_FIXTURE='''#include <QMessageBox>\nnamespace Fm {\nFileMenu::FileMenu() {}\n'''+patch_links.FILE_ANCHOR+'''\n}\n'''
FOLDER_FIXTURE='''#include <QMessageBox>\nnamespace Fm {\nFolderMenu::FolderMenu() {}\n'''+patch_links.FOLDER_ANCHOR+'''\n}\n'''
PLACES_FIXTURE='''#include <QMenu>\n#include <QTimer>\nnamespace Fm {\nvoid PlacesView::contextMenuEvent(QContextMenuEvent* event) {}\n'''+load('patch_usb.py','wolf_patch_usb_auto').VOLUME_ANCHOR+'''\n}\n'''
LEGACY_FIXTURE='''#include "fm-app-info.h"
#include <string.h>
int example(void) { return getpgid(getppid()); }
'''
MENU_CACHE_FIXTURE='''# Distributed under the OSI-approved BSD 3-Clause License. See accompanying
# BSD-3-Clause file for details.
find_package(PkgConfig)
pkg_check_modules(PC_MENUCACHE libmenu-cache)
find_package_handle_standard_args(MenuCache REQUIRED_VARS MENUCACHE_LIBRARIES)
'''
MODULE_SHA='0' * 128
RECIPE='''pkgname=libfm-qt
pkgver=2.4.0
pkgrel=4
pkgdesc='LXQt library'
arch=('x86_64')
source=("https://github.com/lxqt/libfm-qt/releases/download/${pkgver}/libfm-qt-${pkgver}.tar.xz")
sha512sums=('00000000')
build() { cmake -B build -S libfm-qt-$pkgver; }
package() { DESTDIR="$pkgdir" cmake --install build; }
'''

def git(*args, cwd=None):
    p=subprocess.run(['git',*args],cwd=cwd,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    return p.stdout.strip()

def new_repo(path, payload, *, tag=None):
    path.mkdir(parents=True)
    git('init','-q',str(path))
    git('config','user.name','Wolf Test',cwd=path)
    git('config','user.email','wolf-test@example.invalid',cwd=path)
    for name,txt in payload.items():
        f=path/name; f.parent.mkdir(parents=True,exist_ok=True); f.write_text(txt)
    git('add','.',cwd=path)
    git('commit','-qm','version 2.4.0',cwd=path)
    if tag: git('tag',tag,cwd=path)
    return git('rev-parse','HEAD',cwd=path)

class PipelineTests(unittest.TestCase):
    def test_arch_recipe_rejects_latest_and_accepts_exact(self):
        self.assertTrue(build.is_arch_recipe(RECIPE))
        self.assertFalse(build.is_arch_recipe(RECIPE.replace('pkgver=2.4.0','pkgver=2.5.0')))
        self.assertFalse(build.is_arch_recipe(RECIPE.replace('pkgrel=4','pkgrel=5')))
        self.assertFalse(build.is_arch_recipe(RECIPE+'\nprepare() { echo wrong; }'))

    def test_unified_recipe_and_patch_order(self):
        patches={'wolf-places-usb.patch':'USB', 'wolf-symlinks-native.patch':'LINK'}
        patches['wolf-legacy-getpgid.patch']='LEGACY'
        new=build.prepare_recipe(RECIPE, patches, rel='4.2', menu_cache_sha512=MODULE_SHA)
        self.assertIn('pkgrel=4.2',new)
        self.assertEqual(new.count('patch --forward'),3)
        self.assertLess(new.index('patch --forward --fuzz=0 -Np1 -i "$srcdir/wolf-places-usb.patch"'),
                        new.index('patch --forward --fuzz=0 -Np1 -i "$srcdir/wolf-symlinks-native.patch"'))
        self.assertIn('sha512sums+=',new)
        self.assertIn('wolf-symlinks-native.patch',new)
        self.assertIn('FindMenuCache.cmake',new)
        self.assertIn('install -Dm644',new)
        self.assertIn('wolf-legacy-getpgid.patch',new)
        old=build.prepare_recipe(RECIPE, patches,rel='4.1',menu_cache_sha512=MODULE_SHA)
        self.assertIn('wolf-places-usb.patch',old)
        self.assertNotIn('wolf-symlinks-native.patch',old)
        self.assertEqual(old.count('patch --forward'),2)

    def test_sources_generated_by_two_independent_patch_generators(self):
        with tempfile.TemporaryDirectory() as d:
            src=Path(d)
            for name,txt in [('filemenu.cpp',FILE_FIXTURE), ('foldermenu.cpp',FOLDER_FIXTURE),
                             ('placesview.cpp', PLACES_FIXTURE),
                             ('core/legacy/fm-app-info.c',LEGACY_FIXTURE)]:
                f=src/'src'/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(txt)
            patches=build.generate_patches(src)
            self.assertEqual(set(patches), {'wolf-places-usb.patch','wolf-symlinks-native.patch',
                                            'wolf-legacy-getpgid.patch'})
            self.assertIn('#include <unistd.h>',patches['wolf-legacy-getpgid.patch'])
            self.assertIn('Formatar unidade USB',patches['wolf-places-usb.patch'])
            self.assertIn('Criar link simbólico aqui',patches['wolf-symlinks-native.patch'])
            self.assertIn('Colar como links simbólicos nesta pasta',patches['wolf-symlinks-native.patch'])
            self.assertNotIn('Colar como links simbólicos nesta pasta',patches['wolf-places-usb.patch'])
            self.assertNotIn('Criar link simbólico aqui',(src/'src/filemenu.cpp').read_text())

    def test_clone_and_prepare_without_previous_build_folder(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d)
            upstream=d/'upstream-local'
            commit=new_repo(upstream, {'src/placesview.cpp':PLACES_FIXTURE,
                                       'src/filemenu.cpp':FILE_FIXTURE,
                                       'src/foldermenu.cpp':FOLDER_FIXTURE,
                                       'src/core/legacy/fm-app-info.c':LEGACY_FIXTURE},tag='2.4.0')
            archived=d/'arch-local'
            arch_commit=new_repo(archived,{'PKGBUILD':RECIPE,'LICENSE':'license','libfm-qt.install':'install'})
            (archived/'PKGBUILD').write_text(RECIPE.replace('pkgver=2.4.0','pkgver=2.5.0'))
            git('add','.',cwd=archived);git('commit','-qm','new version',cwd=archived)
            original=build.UPSTREAM_COMMIT_PREFIX
            try:
                build.UPSTREAM_COMMIT_PREFIX=commit[:7]
                fetched, source_commit=build.get_tag_source(d/'source-new',clone_url=str(upstream))
            finally:
                build.UPSTREAM_COMMIT_PREFIX=original
            repo, version_commit, rec=build.fetch_arch_recipe(d/'recipe-new',url=str(archived))
            self.assertEqual(source_commit,commit)
            self.assertEqual(version_commit,arch_commit)
            self.assertIn('pkgver=2.4.0',rec)
            patches=build.generate_patches(fetched)
            module=d/'FindMenuCache.cmake'; module.write_text(MENU_CACHE_FIXTURE)
            out=build.prepare_build(repo,version_commit,rec,patches,d/'build-4.2','4.2',
                                    menu_cache_module=module)
            self.assertTrue((out/'libfm-qt.install').is_file())
            self.assertTrue((out/'LICENSE').is_file())
            self.assertEqual((out/'PKGBUILD').read_text().count('patch --forward'),3)
            self.assertEqual((out/'FindMenuCache.cmake').read_text(),MENU_CACHE_FIXTURE)
            self.assertIn('install -Dm644', (out/'PKGBUILD').read_text())
            self.assertIn('wolf-places-usb.patch',(out/'PKGBUILD').read_text())
            self.assertIn('wolf-symlinks-native.patch',(out/'PKGBUILD').read_text())
            self.assertEqual((archived/'PKGBUILD').read_text().count('pkgver=2.5.0'),1)
            # Emulates makepkg prepare() with synthetic pinned 2.4.0 sources,
            # proving the final CMake source module and legacy header exist.
            srcdir=d/'pkgsrc'; project=srcdir/'libfm-qt-2.4.0';project.mkdir(parents=True)
            for name, txt in [('placesview.cpp', PLACES_FIXTURE),
                              ('filemenu.cpp',FILE_FIXTURE),
                              ('foldermenu.cpp',FOLDER_FIXTURE),
                              ('core/legacy/fm-app-info.c',LEGACY_FIXTURE)]:
                file=project/'src'/name
                file.parent.mkdir(parents=True,exist_ok=True)
                file.write_text(txt)
            for name in ('wolf-places-usb.patch','wolf-symlinks-native.patch',
                         'wolf-legacy-getpgid.patch','FindMenuCache.cmake'):
                (srcdir/name).write_bytes((out/name).read_bytes())
            env=os.environ.copy();env['srcdir']=str(srcdir)
            p=subprocess.run(['bash','-c',f'source "{out / "PKGBUILD"}"; prepare'],
                             cwd=out,env=env,text=True,capture_output=True)
            self.assertEqual(p.returncode,0,p.stdout+'\n'+p.stderr)
            self.assertEqual((project/'cmake/FindMenuCache.cmake').read_text(), MENU_CACHE_FIXTURE)
            self.assertIn('#include <unistd.h>',
                          (project/'src/core/legacy/fm-app-info.c').read_text())

    def test_menu_cache_sha512_fail_closed(self):
        patches={'wolf-places-usb.patch':'USB', 'wolf-symlinks-native.patch':'LINK',
                 'wolf-legacy-getpgid.patch':'LEGACY'}
        with self.assertRaises(RuntimeError):
            build.prepare_recipe(RECIPE, patches, rel='4.2', menu_cache_sha512='SKIP')
        with tempfile.TemporaryDirectory() as d:
            candidate=Path(d)/'FindMenuCache.cmake'
            candidate.write_text('invalid')
            with self.assertRaises(RuntimeError):
                build.validate_menu_cache_module(candidate)

    def test_cmake_locates_embedded_menu_cache_module(self):
        # Proves source-tree placement works without CMAKE_TOOLCHAIN_FILE.
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);src=d/'source';src.mkdir()
            (src/'cmake').mkdir()
            (src/'cmake/FindMenuCache.cmake').write_text('set(MenuCache_FOUND TRUE)\n')
            (src/'CMakeLists.txt').write_text("cmake_minimum_required(VERSION 3.18)\n"
              "project(menucheck NONE)\n"
              "list(APPEND CMAKE_MODULE_PATH \"${PROJECT_SOURCE_DIR}/cmake\")\n"
              "find_package(MenuCache REQUIRED)\n")
            env=os.environ.copy(); env.pop('CMAKE_TOOLCHAIN_FILE',None)
            r=subprocess.run(['cmake','-S',str(src),'-B',str(d/'build')],env=env,
                             text=True,capture_output=True)
            self.assertEqual(r.returncode,0,r.stdout+'\n'+r.stderr)

    def test_backend_links_preserve_source(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d)
            orig=d/'orig.png'; orig.write_bytes(b'photo')
            dest=d/'out'; dest.mkdir()
            a, errors=links.create_links([str(orig)],dest)
            self.assertFalse(errors)
            self.assertTrue(a[0].is_symlink())
            self.assertEqual(a[0].read_bytes(),b'photo')
            self.assertEqual(orig.read_bytes(),b'photo')

    def test_installer_removes_legacy_actions_only_with_backups(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d)
            path=home/'.local/share/file-manager/actions'; path.mkdir(parents=True)
            for name in installer.FILES:
                (path/name).write_text('OLD')
            installer.install(ROOT,home)
            self.assertTrue((home/'.local/bin/wolf-symlink-actions').exists())
            self.assertFalse(any((path/name).exists() for name in installer.FILES))
            self.assertEqual(len(list((home/'.local/share/wolf-symlinks/backups').rglob('*.desktop'))),3)


    def test_source_version_anchor_rejects_unknown_code(self):
        with tempfile.TemporaryDirectory() as d:
            src=Path(d)/'src';src.mkdir()
            (src/'placesview.cpp').write_text(PLACES_FIXTURE.replace('case PlacesModelItem::Volume:', 'case PlacesModelItem::Other:'))
            (src/'filemenu.cpp').write_text(FILE_FIXTURE)
            (src/'foldermenu.cpp').write_text(FOLDER_FIXTURE)
            (src/'core/legacy').mkdir(parents=True)
            (src/'core/legacy/fm-app-info.c').write_text(LEGACY_FIXTURE)
            with self.assertRaises(ValueError):
                build.generate_patches(Path(d))

    def test_menu_actions_do_not_overlap(self):
        file=patch_links.transform_filemenu(FILE_FIXTURE)
        folder=patch_links.transform_foldermenu(FOLDER_FIXTURE)
        self.assertIn('Criar link simbólico aqui',file)
        self.assertIn('Criar link simbólico em…',file)
        self.assertNotIn('Colar como links simbólicos nesta pasta',file)
        self.assertIn('Colar como links simbólicos nesta pasta',folder)
        self.assertNotIn('Criar link simbólico aqui',folder)
        self.assertNotIn('Criar link simbólico em…',folder)

    def test_guard_patch_is_narrow_and_reversible(self):
        pm=load('ajustar-guard-pm.py','wolf_pm_guard_tests')
        old="WOLF_VERSION = '2.4.0-4.1'\nactive = installed == WOLF_VERSION\n"
        new=pm.transform(old)
        self.assertIn("active = installed in (WOLF_VERSION, '2.4.0-4.2')",new)
        with self.assertRaises(ValueError):
            pm.transform(new)

    def test_links_collision_and_files_with_spaces(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d)
            src=d/'Minha foto.jpg';src.write_text('ok')
            dest=d/'Destino pessoal';dest.mkdir()
            first,erra=links.create_links([src],dest)
            second,errb=links.create_links([src],dest)
            self.assertFalse(erra+errb)
            self.assertEqual(first[0].name,'Minha foto.jpg')
            self.assertEqual(second[0].name,'Minha foto.jpg - link')
            self.assertEqual(first[0].read_text(),'ok')

    def test_missing_source_is_error_and_preserves_destination(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d); target=d/'target';target.mkdir()
            files, errors=links.create_links([str(d/'missing')],target)
            self.assertEqual(files,[])
            self.assertEqual(len(errors),1)
            self.assertEqual(list(target.iterdir()),[])

    def test_legacy_action_symlinks_block_install(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d); a=home/'.local/share/file-manager/actions';a.mkdir(parents=True)
            other=home/'outside';other.write_text('do-not-touch')
            (a/installer.FILES[0]).symlink_to(other)
            with self.assertRaises(RuntimeError): installer.install(ROOT,home)
            self.assertEqual(other.read_text(),'do-not-touch')

    def test_clipboard_parses_only_local_file_urls(self):
        self.assertEqual(links._paths_from_uri_text('copy\nfile:///tmp/Ol%C3%A1.txt\nhttps://example.org/a\n'),
                         ['/tmp/Olá.txt'])

    def test_reject_duplicate_patch_generation(self):
        with self.assertRaises(ValueError):
            patch_links.transform_filemenu(patch_links.transform_filemenu(FILE_FIXTURE))
        with self.assertRaises(ValueError):
            patch_links.transform_foldermenu(patch_links.transform_foldermenu(FOLDER_FIXTURE))

if __name__ == '__main__': unittest.main()
