#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
MODE="uefi"
ISO=""
FRESH=0
INSTALLED_ONLY=0
SSH_PORT="${WOLF_SSH_PORT:-2222}"

usage() {
    cat <<USAGE
Uso: $0 [uefi|bios] [/caminho/arquivo.iso] [--fresh|--installed]

  --fresh      remove o qcow2/NVRAM anteriores antes de iniciar
  --installed  inicia SOMENTE o disco já instalado, sem conectar ISO
USAGE
}

for arg in "$@"; do
    case "$arg" in
        uefi|bios) MODE="$arg" ;;
        --fresh) FRESH=1 ;;
        --installed) INSTALLED_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *.iso) ISO="$arg" ;;
        *) echo "Argumento inválido: $arg" >&2; usage; exit 2 ;;
    esac
done

if (( INSTALLED_ONLY == 0 )) && [[ -z "$ISO" ]]; then
    ISO="$(
        find "$PROJECT/out" -maxdepth 1 -type f -name '*.iso' -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            head -n1 |
            cut -d' ' -f2-
    )"
fi

if (( INSTALLED_ONLY == 0 )); then
    [[ -n "$ISO" && -f "$ISO" ]] || {
        echo "Nenhuma ISO encontrada." >&2
        usage
        exit 1
    }
fi

mkdir -p "$PROJECT/vm"
DISK="$PROJECT/vm/wolf-test-${MODE}.qcow2"

if (( FRESH == 1 )); then
    rm -f "$DISK"
    if [[ "$MODE" == "uefi" ]]; then
        rm -f "$PROJECT/vm/OVMF_VARS-wolf.fd"
        rm -f "$PROJECT/vm/OVMF_VARS-wolf-uefi.fd"
    fi
fi

if [[ ! -f "$DISK" ]]; then
    if (( INSTALLED_ONLY == 1 )); then
        echo "[ERRO] Disco instalado não existe: $DISK" >&2
        echo "Crie/instale primeiro com: ./tests/wolf-vm.sh fresh $MODE" >&2
        exit 1
    fi
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
)

if (( INSTALLED_ONLY == 0 )); then
    COMMON+=( -cdrom "$ISO" -boot menu=on )
else
    COMMON+=( -boot "order=c,menu=on" )
fi

echo
echo "SSH da VM:"
echo "  127.0.0.1:${SSH_PORT} -> guest:22"
echo "Disco: $DISK"
if (( INSTALLED_ONLY == 1 )); then
    echo "Boot: somente sistema instalado"
else
    echo "ISO : $ISO"
fi
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
            if [[ -f "$p" ]]; then CODE="$p"; break; fi
        done

        for p in \
            /usr/share/edk2/x64/OVMF_VARS.4m.fd \
            /usr/share/edk2/x64/OVMF_VARS.fd \
            /usr/share/edk2-ovmf/x64/OVMF_VARS.fd; do
            if [[ -f "$p" ]]; then VARS_TEMPLATE="$p"; break; fi
        done

        [[ -n "$CODE" && -n "$VARS_TEMPLATE" ]] || {
            echo "Não encontrei os arquivos OVMF. Verifique edk2-ovmf." >&2
            exit 1
        }

        VARS="$PROJECT/vm/OVMF_VARS-wolf-uefi.fd"
        [[ -f "$VARS" ]] || cp "$VARS_TEMPLATE" "$VARS"

        exec qemu-system-x86_64 \
            "${COMMON[@]}" \
            -drive "if=pflash,format=raw,readonly=on,file=$CODE" \
            -drive "if=pflash,format=raw,file=$VARS"
        ;;
esac
