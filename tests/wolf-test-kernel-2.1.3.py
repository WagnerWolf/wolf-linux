#!/usr/bin/env python3
"""Contrato de kernels 2.1.3; teste local não destrutivo, sem pacman ou acesso aos discos."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
i=(ROOT/'install/wolf-install.sh').read_text()
p=(ROOT/'package-profiles/packages.conf').read_text()
rehearsal=(ROOT/'live-gui/wolf_physical_rehearsal.py').read_text()
assert 'linux-zen' not in p, 'Zen não pode ser pacote base.'
base=re.search(r'^BASE_PACKAGES=\((.*?)^\)',p,re.M|re.S).group(1)
assert 'linux-lts linux-lts-headers' in base
assert 'linux-cachyos' not in base, 'CachyOS não está nos repositórios oficiais do pacstrap'
assert 'CACHYOS_KERNEL_PACKAGES=(linux-cachyos linux-cachyos-headers)' in p
main=re.search(r'^main\(\)\s*\{(.*?)^\}',i,re.S|re.M).group(1)
stages=re.findall(r'^\s*stage "([^\"]+)" ([a-zA-Z0-9_]+)',main,re.M)
names=[stage for stage,fn in stages]
for name in ('30-pacstrap','63-chaotic-aur','63a-kernel-cachyos','69-video','69b2-validar-nvidia-dkms','70-bootloader','72-validar-boot'):
    assert name in names, name
assert names.index('30-pacstrap') < names.index('63-chaotic-aur') < names.index('63a-kernel-cachyos') < names.index('69-video') < names.index('69b2-validar-nvidia-dkms') < names.index('70-bootloader') < names.index('72-validar-boot')
assert 'stage "63-chaotic-aur" configure_chaotic_aur\n    stage "63a-kernel-cachyos" install_cachyos_kernel' in main, 'Chaotic e CachyOS precisam rodar até no Minimal'
assert main.index('stage "63a-kernel-cachyos"') < main.index('if (( ${#SELECTED_STACKS[@]} > 0 )); then')
assert 'arch-chroot /mnt pacman -Si "chaotic-aur/$pkg"' in i
assert 'chaotic-aur/linux-cachyos chaotic-aur/linux-cachyos-headers' in i
assert 'arch-chroot /mnt pacman -Q linux-cachyos linux-cachyos-headers linux-lts linux-lts-headers' in i
assert 'GRUB_DEFAULT=0' in i
assert 'GRUB_TOP_LEVEL="/boot/vmlinuz-%s"' in i
for filename in ('vmlinuz-linux-cachyos','vmlinuz-linux-lts','initramfs-linux-cachyos.img','initramfs-linux-lts.img'):
    assert filename in i, filename
assert 'arch-chroot /mnt modinfo -k "$release" -F vermagic nvidia' in i
assert 'validate_nvidia_dkms_for_both_kernels' in i
assert 'stage "63a-kernel-cachyos"' in i and "'63a-kernel-cachyos':" in rehearsal
assert 'stage "69b2-validar-nvidia-dkms"' in i and "'69b2-validar-nvidia-dkms':" in rehearsal
assert 'linux-lts' in rehearsal
assert 'linux-cachyos-headers" ;;' in i # helper gamepad
# Sem mudanças destrutivas na política de preservação existente:
for token in ('--no-nvram','if [[ "$FORMAT_ESP" == \'yes\' || ! -e "$fallback_path" ]]','findmnt -rn --mountpoint /mnt/boot/efi'):
    assert token in i, token
version=(ROOT/'VERSION').read_text().strip()
assert re.fullmatch(r'2\.1\.3(?:-rc[1-9]\d*)?',version)
assert (ROOT/f'RELEASE-NOTES-{version}.md').is_file()
print('[OK] 2.1.3: Minimal tenta Chaotic, LTS pacstrap, CachyOS preferencial, NVIDIA DKMS condicionada, GRUB seguro')
