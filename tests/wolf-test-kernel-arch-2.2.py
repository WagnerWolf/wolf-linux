#!/usr/bin/env python3
"""Regressão estática + simulação Chaotic segura (não toca /mnt nem pacman real)."""
import ast
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
installer = (ROOT / 'install/wolf-install.sh').read_text()
packages = (ROOT / 'package-profiles/packages.conf').read_text()
rehearsal = (ROOT / 'live-gui/wolf_physical_rehearsal.py').read_text()
profile = (ROOT / 'tests/wolf-configure-user-defaults.py').read_text()
base = re.search(r'^BASE_PACKAGES=\((.*?)^\)', packages, re.S | re.M).group(1)
for pkg in ('linux', 'linux-headers', 'linux-lts', 'linux-lts-headers'):
    assert re.search(r'(?<![a-z-])' + re.escape(pkg) + r'(?![a-z-])', base), pkg
for label, content in (('installer', installer), ('packages', packages), ('rehearsal', rehearsal),
                       ('postcheck', (ROOT / 'tools/package-manager/wolfpkg/postcheck.py').read_text())):
    assert 'cachyos' not in content.lower(), label
main = re.search(r'^main\(\)\s*\{(?P<body>.*?)^\}', installer, re.M | re.S).group('body')
stages = re.findall(r'^\s*stage "([^"]+)" \w+', main, re.M)
assert stages.index('30-pacstrap') < stages.index('63a-kernel-arch') < stages.index('69b2-validar-nvidia-dkms') < stages.index('70-bootloader') < stages.index('72-validar-boot')
module = ast.parse(rehearsal)
labels = next(ast.literal_eval(stmt.value) for stmt in module.body if isinstance(stmt, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'STAGE_LABELS' for t in stmt.targets))
assert set(stages) == set(labels), f'Ensaio físico diverge: {set(stages) ^ set(labels)}'
assert 'local main_kernel="linux"' in installer
assert 'GRUB_DEFAULT=0' in installer and 'GRUB_TOP_LEVEL=' in installer
assert 'kernels=(linux-lts linux)' in installer
assert 'pacman -Q linux linux-headers linux-lts linux-lts-headers' in installer
assert 'vmlinuz-linux-lts' in installer and 'initramfs-linux-lts.img' in installer
assert 'Chaotic-AUR indisponível: kernel linux continua principal' in installer
assert 'Continuar SEM Chaotic-AUR' in installer
assert 'kwinrc =' not in profile and 'wolf-first-login-plasma.desktop' not in profile
assert 'MultiScreenMode' not in profile
assert '    install_baloo_qt_offscreen\n' not in installer

def fn(name):
    match = re.search(r'^' + re.escape(name) + r'\(\) \{\n', installer, re.M)
    assert match, name
    end = installer.find('\n}\n', match.end())
    assert end > 0
    return installer[match.start():end + 3]

with tempfile.TemporaryDirectory() as tmp:
    target = Path(tmp) / 'target'
    (target / 'etc/wolf-linux').mkdir(parents=True)
    pacman = target / 'etc/pacman.conf'
    pacman.write_text('[core]\nInclude=/etc/pacman.d/mirrorlist\n[chaotic-aur]\nInclude=/etc/pacman.d/chaotic-mirrorlist\n[extra]\nInclude=/etc/pacman.d/mirrorlist\n')
    funcs = (fn('chaotic_skip_unavailable_repo') + '\n' + fn('chaotic_retry_or_skip')).replace('/mnt/', str(target) + '/')
    shell = '\n'.join([
        'set -Eeuo pipefail',
        f'STATE_DIR="{tmp}/state"',
        'warn() { :; }',
        'mkdir -p "$STATE_DIR"', funcs,
        "chaotic_retry_or_skip 'Chave indisponível' < <(printf '2\\n') && exit 21",
        '[[ "${CHAOTIC_READY:-unset}" == no ]]',
        f'[[ -s "{target}/etc/wolf-linux/chaotic-aur-pending.txt" ]]',
        f'[[ ! -e "{target}/etc/wolf-linux/cachyos-pending.txt" ]]',
        f'grep -Fq "[core]" "{pacman}"',
        f'grep -Fq "[extra]" "{pacman}"',
        f'! grep -Fq "[chaotic-aur]" "{pacman}"',
    ])
    run = subprocess.run(['bash', '-c', shell], capture_output=True, text=True, timeout=12)
    assert run.returncode == 0, f'{run.returncode}\n{run.stdout}\n{run.stderr}'
print('[OK] Kernel Arch/LTS, Chaotic independente, DKMS, GRUB, perfil LXQt e ensaio físico')
