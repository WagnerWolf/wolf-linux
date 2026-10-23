#!/usr/bin/env python3
"""Testa fluxos normais e fallback sem pacman, rede, root ou alterações em /mnt real."""
from pathlib import Path
import subprocess, tempfile, re

ROOT = Path(__file__).resolve().parents[1]
source=(ROOT/'install/wolf-install.sh').read_text()
functions=[]
for name in ('chaotic_defer_to_lts','chaotic_retry_or_defer','chaotic_import_bootstrap_key',
             'download_chaotic_bootstrap_file','download_chaotic_bootstrap_with_retry',
             'configure_chaotic_aur','install_cachyos_kernel','configure_bootloader'):
    m=re.search(r'^'+name+r'\(\) \{\n',source,re.M)
    assert m,name
    nxt=source.find('\n}\n',m.end())
    assert nxt>m.end(),name
    functions.append(source[m.start():nxt+3])

with tempfile.TemporaryDirectory() as dirname:
    t=Path(dirname);target=t/'target';(target/'etc/wolf-linux').mkdir(parents=True)
    (target/'var/log').mkdir(parents=True);(target/'boot/grub').mkdir(parents=True)
    (target/'etc').joinpath('pacman.conf').write_text('[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n')
    (target/'etc/default').mkdir(exist_ok=True); (target/'etc/default/grub').write_text('GRUB_DEFAULT=saved\nGRUB_TIMEOUT=2\nGRUB_TIMEOUT_STYLE=hidden\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n')
    (target/'boot/vmlinuz-linux-lts').write_text('kernel');(target/'boot/initramfs-linux-lts.img').write_text('initramfs')
    funcs='\n'.join(functions).replace('/mnt/',str(target)+'/').replace('arch-chroot /mnt ',f'arch-chroot {target} ')
    # Cache file refs: use path mapped from root also
    script=f'''#!/usr/bin/env bash
set -Eeuo pipefail
STATE_DIR={t}/state
mkdir -p "$STATE_DIR"
BOOT_MODE=BIOS
INSTALL_DISK=/dev/null
GPU_PROFILE=nvidia-modern
CHAOTIC_READY=no
CACHYOS_DEFERRED=no
CACHYOS_KERNEL_PACKAGES=(linux-cachyos linux-cachyos-headers)
info() {{ :; }}
ok() {{ :; }}
warn() {{ :; }}
die() {{ echo "UNEXPECTED ERROR: $*" >&2; exit 99; }}
arch-chroot() {{
  if [[ "${{2:-}}" == pacman && "${{3:-}}" == -Q ]]; then
    [[ "${{4:-}}" == linux-cachyos && "${{MOCK_CACHYOS:-no}}" == yes ]] && return 0
    return 1
  fi
  return 0
}}
timeout() {{ return 1; }}
curl() {{ return 1; }}
{funcs}
# Falha na chave -> prompt escolha 2; verificar estado e remoção localizada de repo.
chaotic_import_bootstrap_key() {{ return 1; }}
configure_chaotic_aur < <(printf '2\\n')
[[ "$CHAOTIC_READY" == no && "$CACHYOS_DEFERRED" == yes ]]
[[ -s {target}/etc/wolf-linux/cachyos-pending.txt ]]
grep -Fq '[core]' {target}/etc/pacman.conf
grep -Fq '[extra]' {target}/etc/pacman.conf
! grep -Fq '[chaotic-aur]' {target}/etc/pacman.conf
install_cachyos_kernel
configure_bootloader
[[ $(< {target}/etc/wolf-linux/kernel-default) == linux-lts ]]
grep -Fxq 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-lts"' {target}/etc/default/grub
# Segundo ensaio: kernel Cachy presente, fallback desativado; seleciona Cachy.
printf kernel > {target}/boot/vmlinuz-linux-cachyos
printf initramfs > {target}/boot/initramfs-linux-cachyos.img
CACHYOS_DEFERRED=no MOCK_CACHYOS=yes configure_bootloader
[[ $(< {target}/etc/wolf-linux/kernel-default) == linux-cachyos ]]
grep -Fxq 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' {target}/etc/default/grub
printf 'MOCK_OK\\n'
'''
    run=subprocess.run(['bash','-c',script],text=True,capture_output=True,timeout=30)
    assert run.returncode == 0, f'status={run.returncode}\nstdout={run.stdout}\nstderr={run.stderr}'
    assert 'MOCK_OK' in run.stdout
print('[OK] Chaotic key failure -> LTS fallback; pacman.conf preserved; GRUB LTS/Cachy selection tests simulated')
