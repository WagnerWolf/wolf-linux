#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
MODE="${1:-uefi}"
ISO="${2:-}"
FRESH="${3:-}"
SSH_PORT="${WOLF_SSH_PORT:-2222}"

if [[ -z "$ISO" ]]; then
    ISO="$(
        find "$PROJECT/out" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            head -n1 |
            cut -d' ' -f2-
    )"
fi

[[ -n "$ISO" && -f "$ISO" ]] || {
    echo "Nenhuma ISO encontrada."
    echo
    echo "Uso:"
    echo "  $0 [uefi|bios] [/caminho/arquivo.iso] [--fresh]"
    echo
    echo "Você também pode informar uma ISO oficial do Arch para testar"
    echo "o wolf-install.sh antes de termos uma ISO Wolf Linux pronta."
    exit 1
}

mkdir -p "$PROJECT/vm"
DISK="$PROJECT/vm/wolf-test-${MODE}.qcow2"

if [[ "$FRESH" == "--fresh" ]]; then
    rm -f "$DISK"

    # OVMF_VARS é a NVRAM UEFI da VM. Ela guarda entradas de boot com
    # referência à ESP do disco anterior; ao recriar o qcow2 precisamos
    # recriar também a NVRAM.
    if [[ "$MODE" == "uefi" ]]; then
        rm -f "$PROJECT/vm/OVMF_VARS-wolf.fd"
        rm -f "$PROJECT/vm/OVMF_VARS-wolf-uefi.fd"
    fi
fi

if [[ ! -f "$DISK" ]]; then
    qemu-img create -f qcow2 "$DISK" 80G
fi

COMMON=(
    -enable-kvm
    -machine "q35,accel=kvm"
    -cpu host
    -smp 4
    -m 8192
    -device virtio-vga
    -display gtk
    -device ich9-intel-hda
    -device hda-duplex
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
    -drive "file=$DISK,if=virtio,format=qcow2"
    -cdrom "$ISO"
    -boot menu=on
)

echo
echo "SSH da VM:"
echo "  127.0.0.1:${SSH_PORT} -> guest:22"
echo

case "$MODE" in
    bios)
        echo "Iniciando teste BIOS/Legacy..."
        exec qemu-system-x86_64 "${COMMON[@]}"
        ;;

    uefi)
        echo "Iniciando teste UEFI..."

        CODE=""
        VARS_TEMPLATE=""

        for p in \
            /usr/share/edk2/x64/OVMF_CODE.4m.fd \
            /usr/share/edk2/x64/OVMF_CODE.fd \
            /usr/share/edk2-ovmf/x64/OVMF_CODE.fd; do
            if [[ -f "$p" ]]; then
                CODE="$p"
                break
            fi
        done

        for p in \
            /usr/share/edk2/x64/OVMF_VARS.4m.fd \
            /usr/share/edk2/x64/OVMF_VARS.fd \
            /usr/share/edk2-ovmf/x64/OVMF_VARS.fd; do
            if [[ -f "$p" ]]; then
                VARS_TEMPLATE="$p"
                break
            fi
        done

        [[ -n "$CODE" && -n "$VARS_TEMPLATE" ]] || {
            echo "Não encontrei os arquivos OVMF."
            echo "Verifique se edk2-ovmf está instalado."
            exit 1
        }

        VARS="$PROJECT/vm/OVMF_VARS-wolf-uefi.fd"
        [[ -f "$VARS" ]] || cp "$VARS_TEMPLATE" "$VARS"

        exec qemu-system-x86_64 \
            "${COMMON[@]}" \
            -drive "if=pflash,format=raw,readonly=on,file=$CODE" \
            -drive "if=pflash,format=raw,file=$VARS"
        ;;

    *)
        echo "Modo inválido: $MODE"
        echo "Use: uefi ou bios"
        exit 1
        ;;
esac
