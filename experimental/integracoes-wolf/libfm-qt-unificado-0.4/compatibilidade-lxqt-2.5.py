#!/usr/bin/env python3
"""Prepare CMake toolchain for libfm-qt 2.4.x with lxqt-build-tools >= 2.5.
Uses an upstream LXQt 2.4.0 module, failing closed if download is invalid.
"""
from pathlib import Path
import urllib.request
import sys
URL = 'https://raw.githubusercontent.com/lxqt/lxqt-build-tools/2.4.0/cmake/find-modules/FindMenuCache.cmake'

def setup(dest):
    dest=Path(dest)
    dest.mkdir(parents=True,exist_ok=True)
    target=dest/'FindMenuCache.cmake'
    if not target.is_file():
        req=urllib.request.Request(URL,headers={'User-Agent':'Wolf-Linux-DevKit/2.2.0'})
        with urllib.request.urlopen(req,timeout=30) as resp:
            body=resp.read(64_000)
        if not (body.startswith(b'# Distributed under the OSI-approved BSD 3-Clause License.') and
                b'find_package_handle_standard_args(MenuCache' in body and
                b'pkg_check_modules(PC_MENUCACHE libmenu-cache)' in body):
            raise RuntimeError('Fonte FindMenuCache 2.4.0 não corresponde ao módulo esperado.')
        target.write_bytes(body)
    text=target.read_text(encoding='utf-8')
    if not ('find_package_handle_standard_args(MenuCache' in text and 'pkg_check_modules(PC_MENUCACHE libmenu-cache)' in text):
        raise RuntimeError('Módulo MenuCache inválido. Não prosseguir.')
    toolchain=dest/'wolf-menucache-toolchain.cmake'
    toolchain.write_text('list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")\nset(CMAKE_C_FLAGS_INIT "${CMAKE_C_FLAGS_INIT} -D_DEFAULT_SOURCE -include unistd.h")\n')
    return toolchain

if __name__=='__main__':
    try: print(setup(Path.home()/'.cache/wolf-linux/menucache-cmake-2.4'))
    except Exception as e:
        print('[BLOQUEADO]',e,file=sys.stderr)
        sys.exit(2)
