#!/usr/bin/env bash
# Confere arquivos-testemunha sem formatar ou alterar dados no laboratorio VM.
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Execute com sudo na Live.' >&2; exit 2; }
[[ "$(systemd-detect-virt --vm 2>/dev/null || true)" =~ ^(kvm|qemu)$ ]] || { echo 'Somente QEMU/KVM.' >&2; exit 2; }
[[ -d /run/archiso/airootfs ]] || { echo 'Somente Live Wolf/Archiso.' >&2; exit 2; }
A=$(readlink -f /dev/disk/by-id/virtio-WOLF41EFI)
B=$(readlink -f /dev/disk/by-id/virtio-WOLF41ROOT)
[[ "$A" =~ ^/dev/vd[a-z]+$ && "$B" =~ ^/dev/vd[a-z]+$ && "$A" != "$B" ]] || exit 2
[[ "$(lsblk -dnro SERIAL "$A" | tr -d '[:space:]')" == WOLF41EFI ]] || exit 2
[[ "$(lsblk -dnro SERIAL "$B" | tr -d '[:space:]')" == WOLF41ROOT ]] || exit 2
[[ -b /dev/vg_monstro/lv_projetos ]] || { echo 'LVM não ativo na Live.' >&2; exit 2; }

BASE=/run/wolf41-verify
[[ ! -e "$BASE" ]] || { echo "Ponto ocupado: $BASE" >&2; exit 2; }
mkdir -p "$BASE"
cleanup() {
    for sub in "$BASE/keep" "$BASE/efi" "$BASE/home"; do
        mountpoint -q "$sub" && umount "$sub" || true
    done
    rmdir "$BASE/keep" "$BASE/efi" "$BASE/home" "$BASE" 2>/dev/null || true
}
trap cleanup EXIT
mkdir -p "$BASE"/{efi,home,keep}
mount -o ro,noload /dev/vg_monstro/lv_projetos "$BASE/home"
mount -o ro "${A}1" "$BASE/efi"
mount -t ntfs-3g -o ro "${B}2" "$BASE/keep"

cat "$BASE/home/wolf/Documentos/wolf41-visivel.txt"
cat "$BASE/efi/EFI/Microsoft/Boot/WOLF41-PRESERVAR.txt"
cat "$BASE/keep/WOLF41-PRESERVAR.txt"
[[ -f "$BASE/home/wolf/Documentos/wolf41-visivel.txt" ]] || exit 1
[[ -f "$BASE/efi/EFI/Microsoft/Boot/WOLF41-PRESERVAR.txt" ]] || exit 1
[[ -f "$BASE/keep/WOLF41-PRESERVAR.txt" ]] || exit 1
printf '[OK] EFI, /home multi-PV e partição extra preservadas.\n'
if [[ -e "$BASE/home/wolf/.wolf41-antigo/config.txt" ]]; then
    echo '[INFO] Configuração oculta ainda presente; removê-la é opcional e exige confirmação no instalador.'
else
    echo '[INFO] Configuração oculta ausente (limpeza autorizada anteriormente ou não criada).'
fi
