#!/usr/bin/env bash
# Wolf alpha41: laboratorio isolado de DOIS discos QEMU.
# O host NUNCA faz mount, mkfs, wipefs ou particionamento.
set -Eeuo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
LAB="$PROJECT/vm/lab-alpha41-multidisk"
EFI_IMAGE="$LAB/wolf41-efi-lvm.qcow2"
ROOT_IMAGE="$LAB/wolf41-root-lvm.qcow2"
MODE="${1:-status}"
PORT="${WOLF41_SSH_PORT:-2231}"

help_msg() {
    cat <<USAGE
Laboratorio Wolf alpha41 (2 discos VIRTUAIS, UEFI somente)
  $0 create       cria dois qcow2 novos (64 GiB + 96 GiB), sem tocar em discos fisicos
  $0 live         inicia VM com ISO Wolf conectada (NAO recria discos)
  $0 installed    inicia a VM pelo disco instalado (SEM ISO)
  $0 status       informa os arquivos e comandos

ISO: usa a ISO mais recente em PROJECT/out, ou WOLF41_ISO=/caminho/wolf.iso
Dentro da Live execute, em ordem:
  sudo wolf-lab41-particionar --check
  sudo wolf-lab41-particionar --apply
NAO execute wolf-vm.sh fresh: este laboratorio e isolado da VM comum.
USAGE
}

case "$MODE" in
    -h|--help) help_msg; exit 0 ;;
    create)
        command -v qemu-img >/dev/null || { echo 'Instale qemu-img no host.' >&2; exit 1; }
        [[ ! -e "$EFI_IMAGE" && ! -e "$ROOT_IMAGE" ]] || {
            echo '[BLOQUEIO] Laboratorio ja criado. Nao sobrescrevendo discos.' >&2; exit 2; }
        mkdir -p "$LAB"
        qemu-img create -f qcow2 "$EFI_IMAGE" 64G || exit 1
        if ! qemu-img create -f qcow2 "$ROOT_IMAGE" 96G; then
            rm -f -- "$EFI_IMAGE"; exit 1
        fi
        printf '[OK] Dois discos qcow2 novos criados:\n  %s\n  %s\n' "$EFI_IMAGE" "$ROOT_IMAGE"
        echo 'Proximo: ./tests/wolf-vm-multidisk.sh live'
        exit 0 ;;
    status)
        help_msg
        for image in "$EFI_IMAGE" "$ROOT_IMAGE"; do
            if [[ -f "$image" ]]; then
                echo "[OK] $(basename "$image") — $(du -h "$image" | cut -f1) ocupado no host"
            else
                echo "[NÃO CRIADO] $image"
            fi
        done
        exit 0 ;;
    live|installed) ;;
    *) help_msg >&2; exit 2 ;;
esac

[[ -f "$EFI_IMAGE" && -f "$ROOT_IMAGE" ]] || {
    echo '[ERRO] Crie primeiro os discos: ./tests/wolf-vm-multidisk.sh create' >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null || { echo 'QEMU nao encontrado no host.' >&2; exit 1; }
ISO="${WOLF41_ISO:-}"
if [[ "$MODE" == live ]]; then
    if [[ -z "$ISO" ]]; then
        ISO="$(find "$PROJECT/out" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
    fi
    [[ -f "$ISO" ]] || { echo "[ERRO] ISO nao encontrada: $ISO" >&2; exit 1; }
fi
CODE=""; VARS_TEMPLATE=""
for f in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/edk2/x64/OVMF_CODE.fd /usr/share/edk2-ovmf/x64/OVMF_CODE.fd; do
    [[ ! -f "$f" ]] || { CODE="$f"; break; }
done
for f in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/edk2/x64/OVMF_VARS.fd /usr/share/edk2-ovmf/x64/OVMF_VARS.fd; do
    [[ ! -f "$f" ]] || { VARS_TEMPLATE="$f"; break; }
done
[[ -n "$CODE" && -n "$VARS_TEMPLATE" ]] || { echo '[ERRO] edk2-ovmf ausente.' >&2; exit 1; }
VARS="$LAB/OVMF_VARS-wolf41.fd"
[[ -f "$VARS" ]] || cp -- "$VARS_TEMPLATE" "$VARS"

COMMON=(
    -enable-kvm -machine q35,accel=kvm -cpu host -smp 4 -m 8192
    -device virtio-vga -display gtk -device ich9-intel-hda -device hda-duplex
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${PORT}-:22"
    -drive "if=none,id=wolf41efi,file=$EFI_IMAGE,format=qcow2"
    -device 'virtio-blk-pci,drive=wolf41efi,serial=WOLF41EFI'
    -drive "if=none,id=wolf41root,file=$ROOT_IMAGE,format=qcow2"
    -device 'virtio-blk-pci,drive=wolf41root,serial=WOLF41ROOT'
    -drive "if=pflash,format=raw,readonly=on,file=$CODE"
    -drive "if=pflash,format=raw,file=$VARS"
)
if [[ "$MODE" == live ]]; then
    COMMON+=( -cdrom "$ISO" -boot "order=d,menu=on" )
else
    COMMON+=( -boot order=c,menu=on )
fi
printf 'Wolf Lab: disco EFI=%s; disco ROOT=%s; SSH=%s; modo=%s\n' "$EFI_IMAGE" "$ROOT_IMAGE" "$PORT" "$MODE"
exec qemu-system-x86_64 "${COMMON[@]}"
