#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Execute com sudo.' >&2; exit 1; }
pacman -S --noconfirm linux-zen linux-zen-headers linux-lts linux-lts-headers
mkinitcpio -P
if [[ -f /etc/default/grub ]]; then
    grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub && sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub || echo 'GRUB_TIMEOUT_STYLE=menu' >> /etc/default/grub
    grep -q '^GRUB_TIMEOUT=' /etc/default/grub && sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub || echo 'GRUB_TIMEOUT=5' >> /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
fi
echo '[OK] linux-zen reconstruído e linux-lts preparado como kernel de recuperação.'
