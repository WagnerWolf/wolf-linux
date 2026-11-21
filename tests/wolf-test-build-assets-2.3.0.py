#!/usr/bin/env python3
"""Smoke de integridade da identidade Wolf e recuperação de projeto parcial."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
helper = root / 'tests/wolf-reconcile-assets-2.3.0.py'
assert helper.is_file(), 'helper de recuperação ausente'
assert (root/'assets/kde/wolf-linux-kickoff.svg').is_file(), 'SVG Kickoff ausente do DevKit'
assert (root/'assets/wallpapers/wolf-linux-wallpaper.png').is_file(), 'Wallpaper ausente do DevKit'
pre = (root/'preparar_ambiente_wolf_linux.sh').read_text()
gen = (root/'gerar-iso.sh').read_text()
assert '--resume' in pre and 'cmp -s "$SELF_DIR/install/wolf-install.sh"' in pre
assert '--repair' in pre and 'wolf-reconcile-assets-2.3.0.py' in pre
assert '--staged' in pre and '--check' in gen and '--staged' in gen

def run(*args, success=True):
    r=subprocess.run([sys.executable, str(helper), *map(str, args)], text=True,
                     capture_output=True)
    if success and r.returncode:
        raise AssertionError(r.stderr or r.stdout)
    if not success and not r.returncode:
        raise AssertionError('A proteção deveria rejeitar o estado perigoso')
    return r

# Teste real de integridade do pacote.
run('--source',root,'--project',root,'--check')

with tempfile.TemporaryDirectory(prefix='wolf-assets-') as d:
    tmp=Path(d)
    source=tmp/'devkit'; project=tmp/'build'
    for base in ('assets','branding-assets'):
        (source/base/'wallpapers').mkdir(parents=True)
        (source/base/'kde').mkdir(parents=True)
        (source/base/'wallpapers/wolf-linux-wallpaper.png').write_bytes(b'Wolf wallpaper de teste')
        (source/base/'kde/wolf-linux-kickoff.svg').write_bytes(b'<svg>Wolf</svg>')
    (project/'assets/kde').mkdir(parents=True)
    (project/'assets/kde/wolf-linux-kickoff.svg').write_bytes(b'<svg>Wolf</svg>')
    # Faltam wallpaper e cópias de reserva; jamais gerar ISO assim.
    run('--source',source,'--project',project,'--check',success=False)
    run('--source',source,'--project',project,'--repair')
    run('--source',source,'--project',project,'--check')
    staged=project/'iso-profile/airootfs/root/wolf-linux/assets'
    staged.mkdir(parents=True)
    run('--source',source,'--project',project,'--staged',staged,success=False)
    shutil.copytree(project/'assets',staged,dirs_exist_ok=True)
    run('--source',source,'--project',project,'--staged',staged)
    # Regressão: nunca substituir um logo intencionalmente diferente.
    (project/'assets/kde/wolf-linux-kickoff.svg').write_bytes(b'arquivo diferente')
    run('--source',source,'--project',project,'--repair',success=False)
    assert (project/'assets/kde/wolf-linux-kickoff.svg').read_bytes()==b'arquivo diferente'
    # Segurança: negar árvore com pasta symlinkada.
    (project/'assets/kde/wolf-linux-kickoff.svg').unlink()
    (project/'assets/kde').rmdir()
    (project/'assets/kde').symlink_to(source/'assets/kde',target_is_directory=True)
    run('--source',source,'--project',project,'--repair',success=False)

for f in ('preparar_ambiente_wolf_linux.sh','gerar-iso.sh'):
    subprocess.run(['bash','-n',str(root/f)],check=True)
print('[OK] Integridade de assets Wolf, recuperação de projeto incompleto, staging, proteção de divergências e symlinks.')
