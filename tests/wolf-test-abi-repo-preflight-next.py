#!/usr/bin/env python3
"""Isolated test: fake pacman -Si; never touches network or system packages."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import os

ROOT = Path(__file__).resolve().parents[1]
script = ROOT/'tools/wolf-integration-monitor/verificar-abi-lxqt-24.sh'
with TemporaryDirectory() as d:
    d=Path(d)
    fake=d/'pacman'
    fake.write_text('#!/bin/sh\nif [ "$1" != \'-Si\' ]; then exit 9; fi\ncase "$2" in\n extra/libfm-qt) version="${MOCK_LIBFM:-2.4.0-4}" ;;\n extra/pcmanfm-qt) version="${MOCK_PCMAN:-2.4.1-1}" ;;\n *) exit 8 ;;\nesac\nprintf \'Repository : extra\\nName : %s\\nVersion : %s\\n\' "$2" "$version"\n')
    fake.chmod(0o755)
    env=os.environ.copy()
    env['PATH']=str(d)+os.pathsep+env['PATH']
    r=subprocess.run(['bash',str(script)],env=env,capture_output=True,text=True)
    assert r.returncode == 0, (r.returncode,r.stdout,r.stderr)
    for value in ('2.5.0-1','2.3.0-1','0.0.0-1'):
        env['MOCK_LIBFM']=value
        r=subprocess.run(['bash',str(script)],env=env,capture_output=True,text=True)
        assert r.returncode != 0, (value,r.stdout,r.stderr)
    env['MOCK_LIBFM']='2.4.0-4'
    env['MOCK_PCMAN']='2.5.0-1'
    r=subprocess.run(['bash',str(script)],env=env,capture_output=True,text=True)
    assert r.returncode != 0, (r.stdout,r.stderr)
print('[OK] Pré-verificação ABI: oficial 2.4 permitido, LXQt 2.5 bloqueado antes da formatação')
