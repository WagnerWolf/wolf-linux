#!/usr/bin/env bash

# O shell interativo da ISO oficial do Arch é Zsh, mas este instalador é Bash.
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -Eeuo pipefail

WOLF_VERSION="1.0.6"
DRY_RUN=0
PLAN_ONLY=0
RESET_STATE=0
VM_INSTALL=0
REAL_INSTALL=0

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || true)"
PACKAGES_FILE="${WOLF_PACKAGES_FILE:-$PROJECT_DIR/package-profiles/packages.conf}"
ASSET_DIR="${WOLF_ASSET_DIR:-}"
ASSET_BASE_URL="${WOLF_ASSET_BASE_URL:-}"

STATE_DIR="/tmp/wolf-linux-installer"
LOG_FILE="$STATE_DIR/wolf-install.log"
PROBE_DIR="$STATE_DIR/probe"
CHECKPOINT_FILE="$STATE_DIR/checkpoints"

BOOT_MODE=""
CPU_VENDOR=""
GPU_INFO=""
GPU_PROFILE=""
GPU_HAS_INTEL=0
GPU_HAS_AMD=0
GPU_HAS_NVIDIA=0

KEYBOARD_PROFILE="abnt2"
XKB_LAYOUT="br"
XKB_VARIANT="abnt2"
CINNAMON_LAYOUT="br"
MATE_LAYOUT="br\tabnt2"

DESKTOP=""
HOSTNAME_VALUE="wolf-linux"
USERNAME_VALUE="wolf"

STORAGE_MODE=""
INSTALL_DISK=""
ROOT_DEVICE=""
ESP_DEVICE=""
HOME_DEVICE=""

FORMAT_ROOT="yes"
FORMAT_ESP="no"
FORMAT_HOME="no"
CLEAN_HOME_DOTFILES="no"

DETECTED_INSTALLATION=0
DETECTED_OS=""
DETECTED_HOSTNAME=""

VM_TYPE="none"
USER_PASSWORD=""

AUR_TEMP_SUDOERS="/mnt/etc/sudoers.d/90-wolf-aur-temporary"
CHAOTIC_KEYRING_PACKAGE=""
CHAOTIC_MIRRORLIST_PACKAGE=""

CURRENT_STAGE="inicialização"
ERROR_HANDLER_ACTIVE=0

cleanup_temporary_privileges() {
    if [[ -n "${AUR_TEMP_SUDOERS:-}" && -f "$AUR_TEMP_SUDOERS" ]]; then
        rm -f "$AUR_TEMP_SUDOERS" 2>/dev/null || true
    fi
}

trap cleanup_temporary_privileges EXIT

usage() {
    cat <<'EOF'
Wolf Linux Installer v0.4-vm

Uso:
  ./wolf-install.sh [opções]

Opções:
  --dry-run       Detecta hardware, executa menus e mostra o plano.
                  Nunca formata, monta ou instala.
  --plan-only     Gera o plano e encerra.
  --vm-install    Instalação real somente quando QEMU/KVM for detectado.
  --install       Instalação real em hardware físico.
                  Exige confirmação explícita antes das alterações.
  --reset-state   Limpa checkpoints temporários.
  -h, --help      Mostra esta ajuda.

SEGURANÇA:
  --vm-install é recusado fora de QEMU/KVM.
  --install é recusado quando QEMU/KVM é detectado.
  Em ambos os casos o plano é exibido antes da confirmação destrutiva.
EOF
}

while (($#)); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --plan-only)
            PLAN_ONLY=1
            ;;
        --vm-install)
            VM_INSTALL=1
            ;;
        --install)
            REAL_INSTALL=1
            ;;
        --reset-state)
            RESET_STATE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1"
            usage
            exit 2
            ;;
    esac
    shift
done

mkdir -p "$STATE_DIR" "$PROBE_DIR"

if (( RESET_STATE == 1 )); then
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR" "$PROBE_DIR"
fi

touch "$LOG_FILE" "$CHECKPOINT_FILE"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

info() {
    log "[INFO] $*"
}

ok() {
    log "[OK] $*"
}

warn() {
    log "[AVISO] $*"
}

die() {
    log "[ERRO] $*"
    exit 1
}

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local command="$3"

    # Evita recursão caso alguma coisa dentro do próprio handler falhe.
    if (( ERROR_HANDLER_ACTIVE == 1 )); then
        exit "$exit_code"
    fi
    ERROR_HANDLER_ACTIVE=1

    # ERR também pode ser disparado em contextos controlados; código 0 não é erro.
    (( exit_code != 0 )) || return 0

    echo
    echo "============================================================"
    echo "                  FALHA NA INSTALAÇÃO"
    echo "============================================================"
    printf 'Etapa ..............: %s\n' "${CURRENT_STAGE:-desconhecida}"
    printf 'Código de saída ....: %s\n' "$exit_code"
    printf 'Linha ..............: %s\n' "$line_no"
    printf 'Último comando .....: %s\n' "$command"
    echo
    echo "Estado dos mounts:"
    findmnt /mnt 2>/dev/null || true
    findmnt /mnt/boot/efi 2>/dev/null || true
    findmnt /mnt/home 2>/dev/null || true
    echo
    echo "Checkpoints:"
    cat "$CHECKPOINT_FILE" 2>/dev/null || true
    echo
    echo "Log:"
    echo "  $LOG_FILE"
    echo "============================================================"
    echo

    exit "$exit_code"
}

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

print_cmd() {
    printf '   +'
    printf ' %q' "$@"
    printf '\n'
}

run() {
    if (( DRY_RUN == 1 )); then
        print_cmd "$@"
        return 0
    fi
    "$@"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório ausente: $1"
}

checkpoint_done() {
    grep -Fxq "$1" "$CHECKPOINT_FILE" 2>/dev/null
}

checkpoint_mark() {
    checkpoint_done "$1" || printf '%s\n' "$1" >> "$CHECKPOINT_FILE"
}

stage() {
    local name="$1"
    shift

    CURRENT_STAGE="$name"

    echo
    echo "============================================================"
    echo "ETAPA: $name"
    echo "============================================================"

    if checkpoint_done "$name"; then
        ok "Etapa já concluída nesta sessão: $name"
        return 0
    fi

    "$@"
    checkpoint_mark "$name"
    ok "Etapa concluída: $name"
}

banner() {
    cat <<EOF
============================================================
                     WOLF LINUX
                  Installer $WOLF_VERSION
============================================================
EOF

    if (( DRY_RUN == 1 )); then
        echo "                    *** DRY RUN ***"
    elif (( VM_INSTALL == 1 )); then
        echo "              *** INSTALAÇÃO EM VM ***"
    elif (( REAL_INSTALL == 1 )); then
        echo "           *** INSTALAÇÃO EM HARDWARE ***"
    fi
    echo
}

detect_virtualization() {
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VM_TYPE="$(systemd-detect-virt 2>/dev/null || true)"
        [[ -n "$VM_TYPE" ]] || VM_TYPE="none"
    fi

    if [[ "$VM_TYPE" == "none" ]]; then
        local product=""
        product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
        case "$product" in
            *QEMU*|*KVM*|*Virtual*)
                VM_TYPE="qemu"
                ;;
        esac
    fi
}

check_runtime() {
    [[ -n "${BASH_VERSION:-}" ]] || die "O instalador precisa de Bash."

    detect_virtualization
    info "Virtualização detectada: $VM_TYPE"

    if (( VM_INSTALL == 1 && REAL_INSTALL == 1 )); then
        die "Use apenas um modo: --vm-install OU --install."
    fi

    if (( DRY_RUN == 0 && PLAN_ONLY == 0 )); then
        (( EUID == 0 )) || die "A instalação real precisa ser executada como root."

        if (( VM_INSTALL == 1 )); then
            case "$VM_TYPE" in
                qemu|kvm)
                    ok "QEMU/KVM confirmado. Operações destrutivas liberadas para a VM."
                    ;;
                *)
                    die "--vm-install recusado: QEMU/KVM não foi detectado."
                    ;;
            esac

        elif (( REAL_INSTALL == 1 )); then
            case "$VM_TYPE" in
                qemu|kvm)
                    die "--install recusado dentro de QEMU/KVM. Use --vm-install."
                    ;;
                *)
                    warn "MODO HARDWARE REAL ATIVADO."
                    warn "O instalador poderá formatar os dispositivos mostrados no plano."
                    ;;
            esac

        else
            die "Escolha o modo real: --install no hardware ou --vm-install na VM."
        fi
    fi

    for cmd in lsblk lspci grep sed awk findmnt blkid curl bsdtar; do
        require_command "$cmd"
    done

    [[ -r "$PACKAGES_FILE" ]] ||
        die "Manifesto de pacotes não encontrado: $PACKAGES_FILE"

    # shellcheck disable=SC1090
    source "$PACKAGES_FILE"
}

detect_boot() {
    if [[ -d /sys/firmware/efi ]]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    ok "Modo de boot detectado: $BOOT_MODE"
}

detect_cpu() {
    local vendor
    vendor="$(
        lscpu 2>/dev/null |
            awk -F: '/Vendor ID|ID de fornecedor/ {
                gsub(/^[ \t]+/, "", $2)
                print $2
                exit
            }'
    )"

    case "$vendor" in
        AuthenticAMD)
            CPU_VENDOR="AMD"
            ;;
        GenuineIntel)
            CPU_VENDOR="Intel"
            ;;
        *)
            CPU_VENDOR="${vendor:-desconhecido}"
            ;;
    esac

    ok "CPU: $CPU_VENDOR"
}

detect_gpu() {
    local controller_lines

    GPU_INFO="$(
        lspci -nnk |
            grep -EA4 'VGA compatible controller|3D controller|Display controller' ||
            true
    )"

    echo
    echo "GPU(s) detectada(s):"
    echo "------------------------------------------------------------"
    printf '%s\n' "${GPU_INFO:-Nenhuma GPU identificada}"
    echo "------------------------------------------------------------"

    controller_lines="$(
        lspci -nn |
            grep -Ei 'VGA compatible controller|3D controller|Display controller' ||
            true
    )"

    GPU_HAS_INTEL=0
    GPU_HAS_AMD=0
    GPU_HAS_NVIDIA=0
        GPU_PROFILE="generic"

    # Detecta pelo fabricante da controladora, não por fragmentos genéricos.
    # Ex.: "compatible" contém "ati", portanto grep -i 'ATI' gera falso positivo.
    grep -qiE \
        'Intel Corporation|Intel.*(Graphics|Display|VGA|Arc)' \
        <<< "$controller_lines" && GPU_HAS_INTEL=1

    grep -qiE \
        'Advanced Micro Devices.*\[AMD/ATI\]|AMD.*Radeon|ATI Technologies' \
        <<< "$controller_lines" && GPU_HAS_AMD=1

    grep -qiE \
        'NVIDIA Corporation|NVIDIA.*(GeForce|Quadro|RTX|GTX)' \
        <<< "$controller_lines" && GPU_HAS_NVIDIA=1

    # VM: usa a GPU virtual, nunca a GPU física do host.
    if [[ "$VM_TYPE" == "qemu" || "$VM_TYPE" == "kvm" ]] \
       && grep -qiE 'Virtio|Red Hat|QXL' <<< "$controller_lines"; then
        GPU_PROFILE="virtio"

    elif (( GPU_HAS_NVIDIA == 1 )); then
        # Turing / Ampere / Ada / Blackwell.
        if grep -qiE \
            'NVIDIA.*(TU[0-9]{3}|GA[0-9]{3}|AD[0-9]{3}|GB[0-9]{3}|GeForce RTX|GeForce GTX 16)' \
            <<< "$controller_lines"; then
            GPU_PROFILE="nvidia-modern"

        elif grep -qiE 'NVIDIA.*GK[0-9]{3}' <<< "$controller_lines"; then
            GPU_PROFILE="nvidia-kepler-nouveau"

        else
            # Não arriscamos nvidia-open em hardware legado não identificado.
            GPU_PROFILE="nvidia-legacy-or-unknown"
        fi

    elif (( GPU_HAS_AMD == 1 )); then
        GPU_PROFILE="amd"

    elif (( GPU_HAS_INTEL == 1 )); then
        GPU_PROFILE="intel"
    fi

    ok "Perfil gráfico selecionado: $GPU_PROFILE"

    if (( GPU_HAS_INTEL == 1 && GPU_HAS_NVIDIA == 1 )); then
        info "Sistema híbrido Intel + NVIDIA detectado."
    elif (( GPU_HAS_AMD == 1 && GPU_HAS_NVIDIA == 1 )); then
        info "Sistema híbrido AMD + NVIDIA detectado."
    fi
}

detect_keyboard() {
    local dmi_info=""

    for file in \
        /sys/class/dmi/id/sys_vendor \
        /sys/class/dmi/id/product_name \
        /sys/class/dmi/id/product_family \
        /sys/class/dmi/id/product_version; do

        if [[ -r "$file" ]]; then
            dmi_info+=" $(cat "$file" 2>/dev/null || true)"
        fi
    done

    if grep -qi "thinkpad" <<< "$dmi_info"; then
        KEYBOARD_PROFILE="thinkpad"
        XKB_LAYOUT="br"
        XKB_VARIANT="thinkpad"
        CINNAMON_LAYOUT="br+thinkpad"
        MATE_LAYOUT=$'br\tthinkpad'
    else
        KEYBOARD_PROFILE="abnt2"
        XKB_LAYOUT="br"
        XKB_VARIANT="abnt2"
        CINNAMON_LAYOUT="br"
        MATE_LAYOUT=$'br\tabnt2'
    fi

    ok "Perfil de teclado: $KEYBOARD_PROFILE ($XKB_LAYOUT/$XKB_VARIANT)"
}

check_network() {
    info "Verificando conectividade..."

    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        ok "Conectividade IP disponível."
        return 0
    fi

    warn "Não foi detectada conectividade IP."

    if (( DRY_RUN == 1 )); then
        warn "No dry-run a configuração Wi-Fi não será iniciada."
        return 0
    fi

    if command -v iwctl >/dev/null 2>&1; then
        echo
        read -r -p "Deseja abrir o iwctl para configurar Wi-Fi? (s/N): " answer
        if [[ "$answer" =~ ^[sS]$ ]]; then
            iwctl
            ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 ||
                die "Ainda não há conectividade após o iwctl."
        else
            die "Internet necessária para continuar."
        fi
    else
        die "Sem internet e iwctl não está disponível."
    fi
}

choose_desktop() {
    echo
    echo "Escolha o ambiente gráfico:"
    echo
    echo "  1) MATE"
    echo "  2) Cinnamon"
    echo "  3) KDE Plasma"
    echo

    while true; do
        read -r -p "Opção [1-3]: " choice
        case "$choice" in
            1)
                DESKTOP="mate"
                break
                ;;
            2)
                DESKTOP="cinnamon"
                break
                ;;
            3)
                DESKTOP="plasma"
                break
                ;;
            *)
                echo "Opção inválida."
                ;;
        esac
    done

    ok "Desktop selecionado: $DESKTOP"
}

collect_identity() {
    echo
    read -r -p "Hostname [wolf-linux]: " value
    HOSTNAME_VALUE="${value:-wolf-linux}"

    read -r -p "Usuário principal [wolf]: " value
    USERNAME_VALUE="${value:-wolf}"

    [[ "$USERNAME_VALUE" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
        die "Nome de usuário inválido."

    ok "Hostname: $HOSTNAME_VALUE"
    ok "Usuário: $USERNAME_VALUE"
}

show_block_devices_detailed() {
    echo
    echo "Discos e partições detectados:"
    echo "------------------------------------------------------------"
    lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
    echo "------------------------------------------------------------"
}

resolve_fstab_spec() {
    local spec="$1"

    case "$spec" in
        UUID=*)
            blkid -U "${spec#UUID=}" 2>/dev/null || true
            ;;
        PARTUUID=*)
            blkid -t "PARTUUID=${spec#PARTUUID=}" -o device 2>/dev/null | head -n1
            ;;
        LABEL=*)
            blkid -L "${spec#LABEL=}" 2>/dev/null || true
            ;;
        /dev/*)
            printf '%s\n' "$spec"
            ;;
    esac
}

fstab_spec_for_mountpoint() {
    local fstab="$1"
    local mountpoint="$2"

    awk -v mp="$mountpoint" '
        $0 !~ /^[[:space:]]*#/ && NF >= 2 && $2 == mp {
            print $1
            exit
        }
    ' "$fstab"
}

read_os_name() {
    local root="$1"

    if [[ -f "$root/etc/os-release" ]]; then
        (
            # shellcheck disable=SC1091
            source "$root/etc/os-release"
            printf '%s\n' "${PRETTY_NAME:-${NAME:-Linux}}"
        )
    else
        echo "Linux"
    fi
}

read_hostname() {
    local root="$1"

    if [[ -s "$root/etc/hostname" ]]; then
        head -n1 "$root/etc/hostname"
    else
        echo "desconhecido"
    fi
}

detect_current_running_layout() {
    local root_src home_src esp_src root_fs

    root_src="$(findmnt -rn -o SOURCE / 2>/dev/null || true)"
    root_fs="$(findmnt -rn -o FSTYPE / 2>/dev/null || true)"

    case "$root_fs" in
        overlay|squashfs|tmpfs|rootfs)
            return 1
            ;;
    esac

    [[ "$root_src" == /dev/* ]] || return 1
    [[ -b "$root_src" ]] || return 1

    ROOT_DEVICE="$root_src"

    home_src="$(findmnt -rn -o SOURCE /home 2>/dev/null || true)"
    if [[ "$home_src" == /dev/* && "$home_src" != "$ROOT_DEVICE" ]]; then
        HOME_DEVICE="$home_src"
    else
        HOME_DEVICE=""
    fi

    esp_src="$(findmnt -rn -o SOURCE /boot/efi 2>/dev/null || true)"
    if [[ -z "$esp_src" ]]; then
        local boot_src boot_fs
        boot_src="$(findmnt -rn -o SOURCE /boot 2>/dev/null || true)"
        boot_fs="$(findmnt -rn -o FSTYPE /boot 2>/dev/null || true)"

        if [[ "$boot_fs" == "vfat" || "$boot_fs" == "fat" || "$boot_fs" == "fat32" ]]; then
            esp_src="$boot_src"
        fi
    fi

    if [[ "$esp_src" == /dev/* ]]; then
        ESP_DEVICE="$esp_src"
    else
        ESP_DEVICE=""
    fi

    DETECTED_OS="$(read_os_name /)"
    DETECTED_HOSTNAME="$(read_hostname /)"
    DETECTED_INSTALLATION=1
    return 0
}

probe_one_root_candidate() {
    local dev="$1"
    local probe="$2"
    local fstab root_spec home_spec esp_spec resolved_root

    mkdir -p "$probe"

    if findmnt -rn -S "$dev" >/dev/null 2>&1; then
        return 1
    fi

    mount -o ro "$dev" "$probe" 2>/dev/null || return 1

    fstab="$probe/etc/fstab"

    if [[ ! -f "$fstab" || ! -f "$probe/etc/os-release" ]]; then
        umount "$probe" 2>/dev/null || true
        return 1
    fi

    root_spec="$(fstab_spec_for_mountpoint "$fstab" /)"

    if [[ -z "$root_spec" ]]; then
        umount "$probe" 2>/dev/null || true
        return 1
    fi

    resolved_root="$(resolve_fstab_spec "$root_spec")"

    if [[ -n "$resolved_root" && "$resolved_root" != "$dev" ]]; then
        umount "$probe" 2>/dev/null || true
        return 1
    fi

    ROOT_DEVICE="$dev"

    home_spec="$(fstab_spec_for_mountpoint "$fstab" /home)"
    HOME_DEVICE="$(resolve_fstab_spec "$home_spec")"

    esp_spec="$(fstab_spec_for_mountpoint "$fstab" /boot/efi)"
    [[ -n "$esp_spec" ]] || esp_spec="$(fstab_spec_for_mountpoint "$fstab" /boot)"
    ESP_DEVICE="$(resolve_fstab_spec "$esp_spec")"

    DETECTED_OS="$(read_os_name "$probe")"
    DETECTED_HOSTNAME="$(read_hostname "$probe")"
    DETECTED_INSTALLATION=1

    umount "$probe" 2>/dev/null || true
    return 0
}

detect_existing_installation_from_disk() {
    (( EUID == 0 )) || return 1

    if command -v vgchange >/dev/null 2>&1; then
        vgchange -ay >/dev/null 2>&1 || true
    fi

    local dev type fstype idx=0

    while read -r dev type fstype; do
        case "$type:$fstype" in
            part:ext4|part:xfs|part:f2fs|lvm:ext4|lvm:xfs|lvm:f2fs)
                ;;
            *)
                continue
                ;;
        esac

        idx=$((idx + 1))

        if probe_one_root_candidate "$dev" "$PROBE_DIR/root-$idx"; then
            return 0
        fi
    done < <(lsblk -prno NAME,TYPE,FSTYPE)

    return 1
}

detect_existing_installation() {
    ROOT_DEVICE=""
    ESP_DEVICE=""
    HOME_DEVICE=""
    DETECTED_INSTALLATION=0

    if detect_current_running_layout; then
        return 0
    fi

    detect_existing_installation_from_disk
}

show_detected_layout() {
    echo
    echo "============================================================"
    echo "          INSTALAÇÃO LINUX EXISTENTE DETECTADA"
    echo "============================================================"
    printf 'Sistema ............: %s\n' "${DETECTED_OS:-Linux}"
    printf 'Hostname ...........: %s\n' "${DETECTED_HOSTNAME:-desconhecido}"
    echo
    echo "O Wolf Linux pode reutilizar automaticamente este layout:"
    echo
    printf '  /          %-30s  SERÁ FORMATADO\n' "$ROOT_DEVICE"

    if [[ -n "$ESP_DEVICE" ]]; then
        printf '  /boot/efi  %-30s  SERÁ PRESERVADO\n' "$ESP_DEVICE"
    fi

    if [[ -n "$HOME_DEVICE" ]]; then
        printf '  /home      %-30s  SERÁ PRESERVADO\n' "$HOME_DEVICE"
    else
        printf '  /home      %-30s  ficará dentro de /\n' "(sem partição separada)"
    fi

    echo
    echo "Outras partições não serão alteradas por este plano."
    echo "============================================================"
}

offer_detected_layout() {
    if ! detect_existing_installation; then
        return 1
    fi

    show_detected_layout
    echo
    read -r -p "Usar automaticamente este layout? [S/n]: " answer

    if [[ -z "$answer" || "$answer" =~ ^[sS]$ ]]; then
        STORAGE_MODE="reuse-auto"
        FORMAT_ROOT="yes"
        FORMAT_ESP="no"
        FORMAT_HOME="no"
        ok "Layout existente selecionado automaticamente."
        return 0
    fi

    ROOT_DEVICE=""
    ESP_DEVICE=""
    HOME_DEVICE=""
    return 1
}

choose_storage_mode() {
    if offer_detected_layout; then
        return 0
    fi

    echo
    echo "Como deseja preparar o armazenamento?"
    echo
    echo "  1) Apagar um disco e instalar automaticamente"
    echo "  2) Escolher/reutilizar partições existentes manualmente"
    echo "  3) Configuração manual/avançada"
    echo

    while true; do
        read -r -p "Opção [1-3]: " choice
        case "$choice" in
            1)
                STORAGE_MODE="erase"
                break
                ;;
            2)
                STORAGE_MODE="reuse-manual"
                break
                ;;
            3)
                STORAGE_MODE="manual"
                break
                ;;
            *)
                echo "Opção inválida."
                ;;
        esac
    done
}

validate_device_if_needed() {
    local dev="$1"

    [[ -z "$dev" ]] && return 0
    [[ -b "$dev" ]] && return 0

    if (( DRY_RUN == 1 )); then
        warn "$dev não existe neste sistema; aceito apenas por estar em dry-run."
        return 0
    fi

    die "Dispositivo não encontrado: $dev"
}

plan_reuse_storage_manual() {
    show_block_devices_detailed

    echo
    echo "RAIZ (/): será formatada."
    echo "EFI (/boot/efi): será preservada."
    echo "HOME (/home): será preservada."
    echo

    read -r -p "Dispositivo para a RAIZ / [SERÁ FORMATADO]: " ROOT_DEVICE
    [[ -n "$ROOT_DEVICE" ]] || die "A raiz é obrigatória."
    validate_device_if_needed "$ROOT_DEVICE"

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        read -r -p "Dispositivo EFI /boot/efi [SERÁ PRESERVADO]: " ESP_DEVICE
        [[ -n "$ESP_DEVICE" ]] || die "ESP obrigatória em UEFI."
        validate_device_if_needed "$ESP_DEVICE"
    fi

    read -r -p "Dispositivo/LV para /home [PRESERVAR] (vazio = usar a raiz): " HOME_DEVICE
    validate_device_if_needed "$HOME_DEVICE"

    FORMAT_ROOT="yes"
    FORMAT_ESP="no"
    FORMAT_HOME="no"
}

partition_path() {
    local disk="$1"
    local num="$2"

    case "$disk" in
        *nvme*|*mmcblk*)
            printf '%sp%s\n' "$disk" "$num"
            ;;
        *)
            printf '%s%s\n' "$disk" "$num"
            ;;
    esac
}

plan_erase_storage() {
    show_block_devices_detailed
    echo
    read -r -p "Disco inteiro a apagar (ex.: /dev/vda): " INSTALL_DISK
    [[ -n "$INSTALL_DISK" ]] || die "Informe um disco."
    validate_device_if_needed "$INSTALL_DISK"

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        ESP_DEVICE="$(partition_path "$INSTALL_DISK" 1)"
        ROOT_DEVICE="$(partition_path "$INSTALL_DISK" 2)"
        FORMAT_ESP="yes"
    else
        ESP_DEVICE=""
        ROOT_DEVICE="$(partition_path "$INSTALL_DISK" 1)"
        FORMAT_ESP="no"
    fi

    HOME_DEVICE=""
    FORMAT_ROOT="yes"
    FORMAT_HOME="no"
}

plan_manual_storage() {
    show_block_devices_detailed
    warn "Modo manual: prepare /mnt manualmente antes de continuar."
    FORMAT_ROOT="no"
    FORMAT_ESP="no"
    FORMAT_HOME="no"
}

storage_planner() {
    choose_storage_mode

    case "$STORAGE_MODE" in
        reuse-auto)
            ;;
        reuse-manual)
            plan_reuse_storage_manual
            ;;
        erase)
            plan_erase_storage
            ;;
        manual)
            plan_manual_storage
            ;;
    esac
}


plan_preserved_home_cleanup() {
    CLEAN_HOME_DOTFILES="no"

    case "$STORAGE_MODE" in
        reuse-auto|reuse-manual)
            ;;
        *)
            return 0
            ;;
    esac

    # Só existe algo a limpar quando /home é uma partição/LV separada,
    # será preservada e NÃO será formatada.
    [[ -n "$HOME_DEVICE" ]] || return 0
    [[ "$FORMAT_HOME" == "no" ]] || return 0

    echo
    echo "============================================================"
    echo "             LIMPEZA DO /home PRESERVADO"
    echo "============================================================"
    echo
    echo "A partição/LV /home será preservada."
    echo
    printf 'Usuário alvo ........: %s\n' "$USERNAME_VALUE"
    printf 'Diretório alvo ......: /home/%s\n' "$USERNAME_VALUE"
    echo
    echo "O Wolf Linux pode apagar SOMENTE arquivos e diretórios"
    echo "ocultos diretamente dentro da home desse usuário."
    echo
    echo "Exemplos que serão removidos:"
    echo "  .config  .cache  .local  .mozilla  .zshrc  .p10k.zsh ..."
    echo
    echo "Pastas e arquivos visíveis serão preservados:"
    echo "  Documentos  Downloads  Projetos  Imagens ..."
    echo
    echo "A própria partição /home NÃO será formatada."
    echo "============================================================"
    echo

    read -r -p "Limpar configurações ocultas antigas de /home/$USERNAME_VALUE? [S/n]: " answer

    if [[ -z "$answer" || "$answer" =~ ^[sS]$ ]]; then
        CLEAN_HOME_DOTFILES="yes"
        ok "Limpeza dos dotfiles antigos foi incluída no plano."
    else
        CLEAN_HOME_DOTFILES="no"
        warn "Dotfiles antigos serão preservados."
    fi
}

show_plan() {
    echo
    echo "============================================================"
    echo "                 PLANO WOLF LINUX"
    echo "============================================================"
    printf 'Boot ..............: %s\n' "$BOOT_MODE"
    printf 'CPU ...............: %s\n' "$CPU_VENDOR"
    printf 'GPU profile .......: %s\n' "$GPU_PROFILE"
    printf 'Teclado ...........: br (%s)\n' "$XKB_VARIANT"
    printf 'Desktop ...........: %s\n' "$DESKTOP"
    printf 'Display manager ...: SDDM\n'
    printf 'Kernel ............: linux-zen\n'
    printf 'Áudio .............: PipeWire + WirePlumber\n'
    printf 'Hostname ..........: %s\n' "$HOSTNAME_VALUE"
    printf 'Usuário ...........: %s\n' "$USERNAME_VALUE"
    printf 'Privilégios .......: administrador (wheel/sudo)\n'
    printf 'Conta root ........: bloqueada\n'
    printf 'Sudo ..............: feedback de asteriscos (pwfeedback)\n'
    printf 'Armazenamento .....: %s\n' "$STORAGE_MODE"

    if (( DETECTED_INSTALLATION == 1 )); then
        printf 'Layout anterior ....: detectado automaticamente\n'
    fi

    case "$STORAGE_MODE" in
        reuse-auto|reuse-manual)
            echo
            echo "SERÁ FORMATADO:"
            printf '  /           %s\n' "$ROOT_DEVICE"

            echo
            echo "SERÁ PRESERVADO:"
            [[ -n "$ESP_DEVICE" ]] && printf '  /boot/efi   %s\n' "$ESP_DEVICE"

            if [[ -n "$HOME_DEVICE" ]]; then
                printf '  /home       %s\n' "$HOME_DEVICE"
                if [[ "$CLEAN_HOME_DOTFILES" == "yes" ]]; then
                    printf '  dotfiles    /home/%s/.*  [REMOVER]\n' "$USERNAME_VALUE"
                else
                    printf '  dotfiles    /home/%s/.*  [PRESERVAR]\n' "$USERNAME_VALUE"
                fi
            else
                echo "  /home       dentro da nova raiz"
            fi
            ;;
        erase)
            echo
            echo "DISCO INTEIRO SERÁ APAGADO:"
            printf '  %s\n' "$INSTALL_DISK"
            echo
            printf 'Nova raiz ..........: %s\n' "$ROOT_DEVICE"
            [[ -n "$ESP_DEVICE" ]] && printf 'Nova ESP ...........: %s\n' "$ESP_DEVICE"
            ;;
        manual)
            echo "Particionamento ....: manual"
            ;;
    esac

    echo "============================================================"
}

confirm_installation() {
    if (( DRY_RUN == 1 || PLAN_ONLY == 1 )); then
        return 0
    fi

    echo
    echo "ATENÇÃO: a próxima etapa realizará alterações reais nos dispositivos do plano."
    read -r -p 'Digite INSTALAR-WOLF para continuar: ' answer
    [[ "$answer" == "INSTALAR-WOLF" ]] || die "Instalação cancelada."
}

prepare_erase_disk() {
    [[ "$STORAGE_MODE" == "erase" ]] || return 0

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        wipefs -a "$INSTALL_DISK"
        sgdisk -Z "$INSTALL_DISK"
        sgdisk -n 1:0:+1G -t 1:ef00 "$INSTALL_DISK"
        sgdisk -n 2:0:0 -t 2:8300 "$INSTALL_DISK"
    else
        wipefs -a "$INSTALL_DISK"
        parted -s "$INSTALL_DISK" mklabel msdos
        parted -s "$INSTALL_DISK" mkpart primary ext4 1MiB 100%
        parted -s "$INSTALL_DISK" set 1 boot on
    fi

    partprobe "$INSTALL_DISK"
    blockdev --rereadpt "$INSTALL_DISK" 2>/dev/null || true
    udevadm settle
    sleep 2

    echo
    echo "Partições criadas:"
    lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE "$INSTALL_DISK"
}

format_and_mount() {
    if [[ "$STORAGE_MODE" == "manual" ]]; then
        findmnt /mnt >/dev/null 2>&1 ||
            die "No modo manual, /mnt deve estar montado antes de continuar."
        return 0
    fi

    if [[ "$FORMAT_ROOT" == "yes" ]]; then
        mkfs.ext4 -F "$ROOT_DEVICE"
    fi

    if [[ -n "$HOME_DEVICE" && "$FORMAT_HOME" == "yes" ]]; then
        mkfs.ext4 -F "$HOME_DEVICE"
    fi

    mount "$ROOT_DEVICE" /mnt

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        mkdir -p /mnt/boot/efi

        if [[ "$FORMAT_ESP" == "yes" ]]; then
            # Remove qualquer assinatura antiga que possa confundir blkid/mount.
            wipefs -a "$ESP_DEVICE"

            mkfs.vfat -F32 -n WOLF_EFI "$ESP_DEVICE"

            sync
            udevadm settle

            local esp_type
            esp_type="$(blkid -p -s TYPE -o value "$ESP_DEVICE" 2>/dev/null || true)"

            if [[ "$esp_type" != "vfat" ]]; then
                echo "Diagnóstico da ESP:"
                wipefs "$ESP_DEVICE" || true
                blkid "$ESP_DEVICE" || true
                die "A ESP foi formatada, mas não foi reconhecida como vfat."
            fi

            ok "ESP validada como FAT32/vfat: $ESP_DEVICE"
        fi

        # Não depende de autodetecção do mount; evita cache/signatura incorreta.
        mount -t vfat "$ESP_DEVICE" /mnt/boot/efi

        local mounted_esp_type
        mounted_esp_type="$(findmnt -rn -o FSTYPE /mnt/boot/efi 2>/dev/null || true)"

        if [[ "$mounted_esp_type" != "vfat" ]]; then
            die "A ESP foi montada com filesystem inesperado: ${mounted_esp_type:-desconhecido}"
        fi
    fi

    if [[ -n "$HOME_DEVICE" ]]; then
        mkdir -p /mnt/home
        mount "$HOME_DEVICE" /mnt/home
    fi

    # Remove eventual privilégio temporário deixado por uma execução
    # interrompida durante a instalação de AUR.
    rm -f /mnt/etc/sudoers.d/90-wolf-aur-temporary 2>/dev/null || true

    findmnt /mnt

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        findmnt /mnt/boot/efi
    fi

    if [[ -n "$HOME_DEVICE" ]]; then
        findmnt /mnt/home
    fi

    # Não ter /home separado é um cenário perfeitamente válido.
    return 0
}


clean_preserved_home_dotfiles() {
    [[ "$CLEAN_HOME_DOTFILES" == "yes" ]] || {
        info "Limpeza de dotfiles não solicitada."
        return 0
    }

    [[ -n "$HOME_DEVICE" ]] ||
        die "Limpeza de /home solicitada, mas HOME_DEVICE está vazio."

    findmnt /mnt/home >/dev/null 2>&1 ||
        die "/mnt/home não está montado; limpeza recusada por segurança."

    local target="/mnt/home/$USERNAME_VALUE"
    local count=0

    if [[ ! -d "$target" ]]; then
        info "Home antiga não encontrada em $target; nada para limpar."
        return 0
    fi

    echo
    echo "Dotfiles que serão removidos de /home/$USERNAME_VALUE:"
    echo "------------------------------------------------------------"

    while IFS= read -r -d '' item; do
        printf '  %s\n' "${item##*/}"
        ((count += 1))
    done < <(
        find "$target" \
            -mindepth 1 \
            -maxdepth 1 \
            -name '.*' \
            -print0
    )

    echo "------------------------------------------------------------"

    if (( count == 0 )); then
        ok "Nenhum dotfile antigo encontrado."
        return 0
    fi

    info "Removendo $count item(ns) oculto(s) da home preservada..."

    find "$target" \
        -mindepth 1 \
        -maxdepth 1 \
        -name '.*' \
        -exec rm -rf -- {} +

    if find "$target" \
        -mindepth 1 \
        -maxdepth 1 \
        -name '.*' \
        -print -quit |
        grep -q .; then

        die "Ainda existem dotfiles antigos em $target após a limpeza."
    fi

    ok "Configurações ocultas antigas removidas; arquivos visíveis preservados."
}

packages_for_desktop() {
    case "$DESKTOP" in
        mate)
            printf '%s\n' "${MATE_PACKAGES[@]}" "${MATE_PORTAL_PACKAGES[@]}"
            ;;
        cinnamon)
            printf '%s\n' "${CINNAMON_PACKAGES[@]}" "${CINNAMON_PORTAL_PACKAGES[@]}"
            ;;
        plasma)
            printf '%s\n' "${PLASMA_PACKAGES[@]}" "${PLASMA_PORTAL_PACKAGES[@]}"
            ;;
    esac
}

enable_multilib_in_file() {
    local file="$1"

    if grep -q '^\[multilib\]' "$file"; then
        return 0
    fi

    if grep -q '^#\[multilib\]' "$file"; then
        sed -i \
            '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' \
            "$file"
    fi

    grep -q '^\[multilib\]' "$file" ||
        die "Não foi possível habilitar [multilib] em $file"
}

prepare_live_repositories() {
    info "Preparando repositórios da ISO live antes do pacstrap..."

    enable_multilib_in_file /etc/pacman.conf

    pacman -Sy --noconfirm

    if pacman -Si lib32-pipewire >/dev/null 2>&1; then
        ok "Repositório multilib ativo; lib32-pipewire está disponível."
    else
        die "multilib foi habilitado, mas lib32-pipewire continua indisponível."
    fi
}

collect_base_packages() {
    local -a desktop_packages
    local -a cpu_packages
    local -a packages

    mapfile -t desktop_packages < <(packages_for_desktop)

    case "$CPU_VENDOR" in
        AMD)
            cpu_packages=("${AMD_CPU_PACKAGES[@]}")
            ;;
        Intel)
            cpu_packages=("${INTEL_CPU_PACKAGES[@]}")
            ;;
        *)
            cpu_packages=()
            ;;
    esac

    packages=(
        "${BASE_PACKAGES[@]}"
        "${cpu_packages[@]}"
        "${DISPLAY_MANAGER_PACKAGES[@]}"
        "${AUDIO_PACKAGES[@]}"
        "${BLUETOOTH_PACKAGES[@]}"
        "${PRINT_PACKAGES[@]}"
        "${FONT_PACKAGES[@]}"
        "${THEME_PACKAGES[@]}"
        "${ZSH_PACKAGES[@]}"
        "${OFFICE_PACKAGES[@]}"
        "${MULTIMEDIA_PACKAGES[@]}"
        "${THUMBNAIL_PACKAGES[@]}"
        "${desktop_packages[@]}"
    )

    printf '%s\n' "${packages[@]}"
}
validate_base_packages() {
    local -a packages
    local item
    local -a missing=()

    mapfile -t packages < <(collect_base_packages)

    info "Validando ${#packages[@]} pacotes/grupos antes do pacstrap..."

    for item in "${packages[@]}"; do
        if pacman -Si "$item" >/dev/null 2>&1; then
            continue
        fi

        if pacman -Sg "$item" >/dev/null 2>&1; then
            continue
        fi

        missing+=("$item")
    done

    if ((${#missing[@]} > 0)); then
        echo
        echo "Pacotes/grupos não encontrados:"
        printf '  - %s\n' "${missing[@]}"
        die "Manifesto contém itens indisponíveis nos repositórios ativos."
    fi

    ok "Todos os pacotes/grupos da instalação base estão disponíveis."
}

install_base_system() {
    local -a packages

    mapfile -t packages < <(collect_base_packages)

    info "Instalando ${#packages[@]} entradas de pacote/grupo..."
    pacstrap -K /mnt "${packages[@]}" --noconfirm
}

generate_fstab() {
    genfstab -U /mnt > /mnt/etc/fstab
    cat /mnt/etc/fstab
}

prompt_user_password() {
    local p1 p2

    echo
    echo "Defina a senha do usuário '$USERNAME_VALUE'."
    echo "A senha não será exibida nem gravada no log."

    while true; do
        read -r -s -p "Senha: " p1
        echo
        read -r -s -p "Confirme: " p2
        echo

        if [[ -z "$p1" ]]; then
            echo "A senha não pode ser vazia."
            continue
        fi

        if [[ "$p1" != "$p2" ]]; then
            echo "As senhas não coincidem."
            continue
        fi

        USER_PASSWORD="$p1"
        unset p1 p2
        return 0
    done
}

configure_system_base() {
    printf '%s\n' "$HOSTNAME_VALUE" > /mnt/etc/hostname

    ln -sf /usr/share/zoneinfo/America/Santarem /mnt/etc/localtime

    sed -i 's/^#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /mnt/etc/locale.gen
    printf 'LANG=pt_BR.UTF-8\n' > /mnt/etc/locale.conf

    # Console/TTY continua no mapa ABNT2. A variante ThinkPad é XKB gráfica.
    printf 'KEYMAP=br-abnt2\nFONT=ter-v16n\n' > /mnt/etc/vconsole.conf

    mkdir -p /mnt/etc/X11/xorg.conf.d

    cat > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$XKB_LAYOUT"
        Option "XkbVariant" "$XKB_VARIANT"
EndSection
EOF

    cat > /mnt/etc/wolf-linux-keyboard.conf <<EOF
KEYBOARD_PROFILE=$KEYBOARD_PROFILE
XKB_LAYOUT=$XKB_LAYOUT
XKB_VARIANT=$XKB_VARIANT
CINNAMON_LAYOUT=$CINNAMON_LAYOUT
MATE_LAYOUT='$MATE_LAYOUT'
EOF

    arch-chroot /mnt locale-gen
    arch-chroot /mnt hwclock --systohc

    ok "Locale, timezone, hostname e teclado configurados."
}


configure_wolf_identity() {
    info "Aplicando identidade do sistema Wolf Linux..."

    # /etc/os-release tem precedência sobre /usr/lib/os-release.
    # Mantemos ID=arch para compatibilidade com ferramentas e scripts
    # que detectam a família Arch Linux.
    rm -f /mnt/etc/os-release

    cat > /mnt/etc/os-release <<'EOF'
NAME="Wolf Linux"
PRETTY_NAME="Wolf Linux"
ID=arch
ID_LIKE=arch
VARIANT="Wolf Linux"
VARIANT_ID=wolf-linux
BUILD_ID=rolling
ANSI_COLOR="1;37"
HOME_URL="https://archlinux.org/"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
SUPPORT_URL="https://bbs.archlinux.org/"
EOF

    cat > /mnt/etc/issue <<'EOF'
Wolf Linux \r (\l)

EOF

    cat > /mnt/etc/issue.net <<'EOF'
Wolf Linux
EOF

    # O GRUB passa a usar Wolf Linux nos títulos gerados.
    if grep -q '^GRUB_DISTRIBUTOR=' /mnt/etc/default/grub; then
        sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="Wolf Linux"/' \
            /mnt/etc/default/grub
    else
        printf '\nGRUB_DISTRIBUTOR="Wolf Linux"\n' >> /mnt/etc/default/grub
    fi

    # O computador pessoal possui dual boot; permitimos ao grub-mkconfig
    # detectar Windows e outros sistemas preservados.
    if grep -q '^GRUB_DISABLE_OS_PROBER=' /mnt/etc/default/grub; then
        sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' \
            /mnt/etc/default/grub
    else
        printf 'GRUB_DISABLE_OS_PROBER=false\n' >> /mnt/etc/default/grub
    fi

    grep -q '^PRETTY_NAME="Wolf Linux"$' /mnt/etc/os-release ||
        die "Falha ao gravar identidade Wolf Linux em /etc/os-release."

    ok "Sistema identificado como Wolf Linux (compatibilidade ID=arch)."
}

configure_user_sudo() {
    local -a desired_groups
    local -a existing_groups
    local group
    local group_csv

    desired_groups=(wheel lp scanner kvm)
    existing_groups=()

    for group in "${desired_groups[@]}"; do
        if arch-chroot /mnt getent group "$group" >/dev/null 2>&1; then
            existing_groups+=("$group")
        else
            warn "Grupo '$group' não existe no sistema instalado; ignorando."
        fi
    done

    group_csv="$(IFS=,; echo "${existing_groups[*]}")"

    if arch-chroot /mnt id -u "$USERNAME_VALUE" >/dev/null 2>&1; then
        info "Usuário '$USERNAME_VALUE' já existe; ajustando shell e grupos."
        arch-chroot /mnt usermod -s /bin/zsh "$USERNAME_VALUE"

        if [[ -n "$group_csv" ]]; then
            arch-chroot /mnt usermod -aG "$group_csv" "$USERNAME_VALUE"
        fi
    else
        info "Criando usuário '$USERNAME_VALUE'."

        if [[ -n "$group_csv" ]]; then
            arch-chroot /mnt useradd \
                -m \
                -G "$group_csv" \
                -s /bin/zsh \
                "$USERNAME_VALUE"
        else
            arch-chroot /mnt useradd \
                -m \
                -s /bin/zsh \
                "$USERNAME_VALUE"
        fi
    fi

    # Sempre pedimos a senha quando esta subetapa ainda não tem checkpoint.
    # Assim uma retomada após criação parcial do usuário continua segura.
    prompt_user_password

    # A senha nunca é escrita no log.
    printf '%s:%s\n' "$USERNAME_VALUE" "$USER_PASSWORD" |
        arch-chroot /mnt chpasswd
    USER_PASSWORD=""

    mkdir -p /mnt/etc/sudoers.d

    cat > /mnt/etc/sudoers.d/10-wolf-linux <<'EOF'
Defaults pwfeedback
%wheel ALL=(ALL:ALL) ALL
EOF

    chmod 440 /mnt/etc/sudoers.d/10-wolf-linux

    arch-chroot /mnt visudo -cf /etc/sudoers.d/10-wolf-linux

    # Desktop pessoal: administração via sudo; root sem senha de login.
    arch-chroot /mnt passwd -l root

    ok "Usuário e sudo configurados."
}

enable_one_service() {
    local unit="$1"
    local unit_file=""
    local state=""

    for candidate in \
        "/mnt/etc/systemd/system/$unit" \
        "/mnt/usr/lib/systemd/system/$unit"; do
        if [[ -e "$candidate" ]]; then
            unit_file="$candidate"
            break
        fi
    done

    if [[ -z "$unit_file" ]]; then
        echo
        echo "Unit procurada: $unit"
        echo "Pacotes relacionados instalados:"
        case "$unit" in
            NetworkManager.service)
                arch-chroot /mnt pacman -Q networkmanager 2>/dev/null || true
                ;;
            bluetooth.service)
                arch-chroot /mnt pacman -Q bluez bluez-utils 2>/dev/null || true
                ;;
            cups.service)
                arch-chroot /mnt pacman -Q cups 2>/dev/null || true
                ;;
            sddm.service)
                arch-chroot /mnt pacman -Q sddm 2>/dev/null || true
                ;;
            sshd.service)
                arch-chroot /mnt pacman -Q openssh 2>/dev/null || true
                ;;
        esac
        die "Unit systemd não encontrada: $unit"
    fi

    info "Habilitando $unit..."

    # --root opera diretamente sobre o sistema instalado e não depende
    # de haver um systemd em execução dentro do chroot.
    systemctl --root=/mnt enable "$unit"

    state="$(systemctl --root=/mnt is-enabled "$unit" 2>/dev/null || true)"

    case "$state" in
        enabled|enabled-runtime|static|indirect|alias)
            ok "$unit: $state"
            ;;
        *)
            echo "Estado retornado: ${state:-desconhecido}"
            die "Não foi possível confirmar a habilitação de $unit."
            ;;
    esac
}

configure_services() {
    local -a services=(
        NetworkManager.service
        bluetooth.service
        cups.service
        sddm.service
    )

    if [[ "$VM_TYPE" == "qemu" || "$VM_TYPE" == "kvm" ]]; then
        services+=(sshd.service)
        info "VM detectada: sshd será habilitado somente para facilitar os testes."
    fi

    local unit

    for unit in "${services[@]}"; do
        enable_one_service "$unit"
    done

    echo
    echo "Serviços habilitados:"
    for unit in "${services[@]}"; do
        printf '  %-28s %s\n' \
            "$unit" \
            "$(systemctl --root=/mnt is-enabled "$unit" 2>/dev/null || echo desconhecido)"
    done

    return 0
}

configure_multilib() {
    enable_multilib_in_file /mnt/etc/pacman.conf
    arch-chroot /mnt pacman -Syy --noconfirm
}

complete_base_packages() {
    local -a packages

    mapfile -t packages < <(collect_base_packages)

    info "Conferindo/completando pacotes do perfil base no sistema instalado..."
    arch-chroot /mnt pacman -S --needed --noconfirm "${packages[@]}"

    # Valida especificamente os serviços que dependem de pacotes da base.
    local -a expected_units=(
        /mnt/usr/lib/systemd/system/NetworkManager.service
        /mnt/usr/lib/systemd/system/bluetooth.service
        /mnt/usr/lib/systemd/system/cups.service
        /mnt/usr/lib/systemd/system/sddm.service
    )

    local unit_path
    for unit_path in "${expected_units[@]}"; do
        if [[ ! -e "$unit_path" ]]; then
            echo "[ERRO] Unit esperada ausente após completar pacotes:"
            echo "  $unit_path"
            return 1
        fi
    done

    ok "Perfil base completo e units principais presentes."
}

download_chaotic_bootstrap_file() {
    local url="$1"
    local output="$2"
    local label="$3"

    rm -f "$output"

    if ! curl \
        -fL \
        --connect-timeout 15 \
        --max-time 120 \
        --retry 2 \
        --retry-delay 3 \
        --retry-all-errors \
        "$url" \
        -o "$output"; then

        warn "Falha HTTP/rede ao baixar $label."
        rm -f "$output"
        return 1
    fi

    # O CDN pode responder HTTP 200 com texto como "mirror unhealthy".
    # Um pacote pacman válido deve ser um tar que bsdtar consiga listar.
    if ! bsdtar -tf "$output" >/dev/null 2>&1; then
        echo
        echo "Resposta recebida do mirror para $label:"
        echo "------------------------------------------------------------"
        head -c 500 "$output" 2>/dev/null || true
        echo
        echo "------------------------------------------------------------"
        rm -f "$output"
        return 1
    fi

    ok "$label validado."
    return 0
}

download_chaotic_bootstrap_with_retry() {
    local cache_host="/mnt/var/cache/wolf-linux/chaotic"
    local cache_chroot="/var/cache/wolf-linux/chaotic"

    local keyring_url="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst"
    local mirrorlist_url="https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"

    local keyring_host="$cache_host/chaotic-keyring.pkg.tar.zst"
    local mirrorlist_host="$cache_host/chaotic-mirrorlist.pkg.tar.zst"

    local answer=""

    mkdir -p "$cache_host"

    while true; do
        echo
        info "Validando disponibilidade do bootstrap Chaotic-AUR..."

        if download_chaotic_bootstrap_file \
                "$keyring_url" \
                "$keyring_host" \
                "chaotic-keyring" \
           && download_chaotic_bootstrap_file \
                "$mirrorlist_url" \
                "$mirrorlist_host" \
                "chaotic-mirrorlist"; then

            CHAOTIC_KEYRING_PACKAGE="$cache_chroot/chaotic-keyring.pkg.tar.zst"
            CHAOTIC_MIRRORLIST_PACKAGE="$cache_chroot/chaotic-mirrorlist.pkg.tar.zst"
            return 0
        fi

        echo
        warn "O mirror bootstrap do Chaotic-AUR está indisponível ou respondeu conteúdo inválido."
        echo "Isso costuma ser temporário e NÃO exige reiniciar a instalação."

        read -r -p "Tentar novamente agora? [S/n]: " answer

        if [[ -z "$answer" || "$answer" =~ ^[sS]$ ]]; then
            echo "Aguardando 10 segundos antes de tentar novamente..."
            sleep 10
            continue
        fi

        die "Chaotic-AUR indisponível. A instalação pode ser retomada depois nesta mesma etapa."
    done
}

configure_chaotic_aur() {
    info "Configurando Chaotic-AUR..."

    if arch-chroot /mnt pacman -Q chaotic-keyring chaotic-mirrorlist >/dev/null 2>&1 \
       && grep -q '^\[chaotic-aur\]' /mnt/etc/pacman.conf; then
        info "Chaotic-AUR já configurado; apenas sincronizando."

        while true; do
            if arch-chroot /mnt pacman -Syy --noconfirm \
               && arch-chroot /mnt pacman -Sl chaotic-aur >/dev/null 2>&1; then
                ok "Chaotic-AUR sincronizado."
                return 0
            fi

            echo
            warn "Falha ao sincronizar o Chaotic-AUR."
            local sync_answer=""
            read -r -p "Tentar sincronizar novamente? [S/n]: " sync_answer

            if [[ -z "$sync_answer" || "$sync_answer" =~ ^[sS]$ ]]; then
                sleep 10
                continue
            fi

            die "Não foi possível sincronizar o Chaotic-AUR."
        done
    fi

    local -a bootstrap_keys=(
        3056513887B78AEB
        FBA220DFC880C036
    )

    local imported=0
    local key

    for key in "${bootstrap_keys[@]}"; do
        if arch-chroot /mnt pacman-key --recv-key "$key" \
            --keyserver keyserver.ubuntu.com >/dev/null 2>&1; then

            arch-chroot /mnt pacman-key --lsign-key "$key"
            imported=1
        fi
    done

    (( imported == 1 )) ||
        die "Não foi possível importar uma chave de bootstrap do Chaotic-AUR."

    download_chaotic_bootstrap_with_retry

    while true; do
        if arch-chroot /mnt pacman -U --noconfirm \
            "$CHAOTIC_KEYRING_PACKAGE" \
            "$CHAOTIC_MIRRORLIST_PACKAGE"; then
            break
        fi

        echo
        warn "Os arquivos foram baixados, mas pacman -U falhou."
        local install_answer=""
        read -r -p "Baixar novamente e tentar outra vez? [S/n]: " install_answer

        if [[ -z "$install_answer" || "$install_answer" =~ ^[sS]$ ]]; then
            download_chaotic_bootstrap_with_retry
            continue
        fi

        die "Falha ao instalar chaotic-keyring/chaotic-mirrorlist."
    done

    if ! grep -q '^\[chaotic-aur\]' /mnt/etc/pacman.conf; then
        cat >> /mnt/etc/pacman.conf <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
    fi

    while true; do
        if arch-chroot /mnt pacman -Syy --noconfirm \
           && arch-chroot /mnt pacman -Sl chaotic-aur >/dev/null 2>&1; then
            break
        fi

        echo
        warn "Chaotic-AUR configurado, mas o repositório ainda não respondeu corretamente."
        local repo_answer=""
        read -r -p "Tentar sincronizar novamente? [S/n]: " repo_answer

        if [[ -z "$repo_answer" || "$repo_answer" =~ ^[sS]$ ]]; then
            sleep 10
            continue
        fi

        die "Chaotic-AUR configurado, mas indisponível no momento."
    done

    arch-chroot /mnt pacman -Q chaotic-keyring chaotic-mirrorlist
    ok "Chaotic-AUR configurado."
}

install_official_personal_apps() {
    local -a packages=(
        "${INTERNET_PACKAGES[@]}"
        "${DEV_PACKAGES[@]}"
    )

    if ((${#packages[@]} == 0)); then
        return 0
    fi

    info "Instalando aplicativos oficiais de Internet/Desenvolvimento..."
    arch-chroot /mnt pacman -S --needed --noconfirm "${packages[@]}"

    # android-udev pode criar/usar adbusers. Se existir, garante acesso.
    if arch-chroot /mnt getent group adbusers >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG adbusers "$USERNAME_VALUE"
        ok "Usuário adicionado ao grupo adbusers."
    fi

    # Garante KVM quando o grupo está disponível.
    if arch-chroot /mnt getent group kvm >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG kvm "$USERNAME_VALUE"
        ok "Usuário adicionado ao grupo kvm."
    fi
}

ensure_yay() {
    if [[ -x /mnt/usr/bin/yay ]]; then
        ok "yay já instalado."
        return 0
    fi

    info "Tentando instalar yay pelo Chaotic-AUR..."

    if arch-chroot /mnt pacman -Si yay >/dev/null 2>&1; then
        arch-chroot /mnt pacman -S --needed --noconfirm yay
    fi

    if [[ -x /mnt/usr/bin/yay ]]; then
        ok "yay instalado pelo repositório."
        return 0
    fi

    info "yay não disponível via pacman; usando fallback AUR yay-bin."

    local build_dir="/home/$USERNAME_VALUE/.cache/wolf-linux/yay-bin"

    arch-chroot /mnt rm -rf "$build_dir"
    arch-chroot /mnt install -d -o "$USERNAME_VALUE" -g "$USERNAME_VALUE" \
        "/home/$USERNAME_VALUE/.cache/wolf-linux"

    arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- \
        git clone --depth=1 \
        https://aur.archlinux.org/yay-bin.git \
        "$build_dir"

    arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- \
        bash -lc "cd '$build_dir' && makepkg --noconfirm --cleanbuild"

    local built_pkg
    built_pkg="$(
        find "/mnt$build_dir" -maxdepth 1 -type f \
            -name 'yay-bin-*.pkg.tar.*' \
            ! -name '*.sig' \
            -print -quit
    )"

    [[ -n "$built_pkg" ]] ||
        die "yay-bin foi compilado, mas o pacote resultante não foi encontrado."

    arch-chroot /mnt pacman -U --needed --noconfirm "${built_pkg#/mnt}"

    [[ -x /mnt/usr/bin/yay ]] ||
        die "yay não ficou disponível após o fallback AUR."

    ok "yay instalado via fallback AUR."
}

collect_third_party_packages() {
    printf '%s\n' \
        "${ZSH_THIRD_PARTY_PACKAGES[@]}" \
        "${INTERNET_THIRD_PARTY_PACKAGES[@]}" \
        "${DEV_THIRD_PARTY_PACKAGES[@]}" \
        "${PERSONAL_THIRD_PARTY_PACKAGES[@]}" \
        "${SYSTEM_GUI_THIRD_PARTY_PACKAGES[@]}"

    if [[ "$DESKTOP" == "mate" ]]; then
        printf '%s\n' "${MATE_THIRD_PARTY_PACKAGES[@]}"
    fi
}

install_third_party_apps() {
    local -a requested
    local -a repo_packages=()
    local -a aur_packages=()
    local pkg

    mapfile -t requested < <(collect_third_party_packages)

    if ((${#requested[@]} == 0)); then
        return 0
    fi

    echo
    echo "Aplicativos de terceiros solicitados:"
    printf '  - %s\n' "${requested[@]}"

    for pkg in "${requested[@]}"; do
        [[ -n "$pkg" ]] || continue

        if arch-chroot /mnt pacman -Q "$pkg" >/dev/null 2>&1; then
            ok "$pkg já instalado."
            continue
        fi

        if arch-chroot /mnt pacman -Si "$pkg" >/dev/null 2>&1; then
            repo_packages+=("$pkg")
        else
            aur_packages+=("$pkg")
        fi
    done

    if ((${#repo_packages[@]} > 0)); then
        echo
        echo "Instalando pelo Arch/Chaotic-AUR:"
        printf '  - %s\n' "${repo_packages[@]}"
        arch-chroot /mnt pacman -S --needed --noconfirm "${repo_packages[@]}"
    fi

    if ((${#aur_packages[@]} == 0)); then
        ok "Nenhum fallback AUR necessário."
        return 0
    fi

    echo
    echo "Pacotes ausentes dos repositórios; fallback AUR:"
    printf '  - %s\n' "${aur_packages[@]}"

    ensure_yay

    # yay precisa elevar apenas o pacman. Criamos uma autorização temporária,
    # validamos com visudo e a removemos ao fim/EXIT.
    cat > "$AUR_TEMP_SUDOERS" <<EOF
$USERNAME_VALUE ALL=(root) NOPASSWD: /usr/bin/pacman
EOF
    chmod 440 "$AUR_TEMP_SUDOERS"
    arch-chroot /mnt visudo -cf /etc/sudoers.d/90-wolf-aur-temporary

    arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- \
        env \
        HOME="/home/$USERNAME_VALUE" \
        XDG_CACHE_HOME="/home/$USERNAME_VALUE/.cache" \
        yay -S \
            --needed \
            --noconfirm \
            --answerclean None \
            --answerdiff None \
            "${aur_packages[@]}"

    rm -f "$AUR_TEMP_SUDOERS"

    # Validação final pacote por pacote.
    local validation_failed=0

    for pkg in "${requested[@]}"; do
        if arch-chroot /mnt pacman -Q "$pkg" >/dev/null 2>&1; then
            ok "$pkg instalado."
        else
            warn "$pkg não aparece no banco local do pacman."
            validation_failed=1
        fi
    done

    (( validation_failed == 0 )) ||
        die "Um ou mais aplicativos de terceiros não foram confirmados após a instalação."
}

fetch_wolf_asset() {
    local relative="$1"
    local destination="$2"
    local candidate
    local url

    mkdir -p "$(dirname "$destination")"

    for candidate in \
        "${ASSET_DIR:+$ASSET_DIR/$relative}" \
        "$PROJECT_DIR/assets/$relative" \
        "/usr/share/wolf-linux/assets/$relative"; do

        [[ -n "$candidate" ]] || continue

        if [[ -f "$candidate" ]]; then
            cp -f "$candidate" "$destination"
            ok "Asset local: $relative"
            return 0
        fi
    done

    url="$ASSET_BASE_URL"

    if [[ -z "$url" && ( "$VM_TYPE" == "qemu" || "$VM_TYPE" == "kvm" ) ]]; then
        url="http://10.0.2.2:8000/assets"
    fi

    if [[ -n "$url" ]]; then
        info "Baixando asset Wolf Linux: $relative"
        curl -fL --retry 3 --connect-timeout 10 \
            "$url/$relative" \
            -o "$destination"
        return 0
    fi

    die "Asset obrigatório não encontrado: $relative"
}

install_flutter_sdk() {
    local flutter_dir="/mnt/opt/flutter"
    local target_flutter="/opt/flutter"
    local user_home="/home/$USERNAME_VALUE"

    info "Instalando Flutter SDK stable em /opt/flutter..."

    if [[ -d "$flutter_dir/.git" ]]; then
        arch-chroot /mnt git -C "$target_flutter" fetch --depth=1 origin stable
        arch-chroot /mnt git -C "$target_flutter" reset --hard origin/stable
    else
        rm -rf "$flutter_dir"
        arch-chroot /mnt git clone \
            --depth=1 \
            --branch stable \
            https://github.com/flutter/flutter.git \
            "$target_flutter"
    fi

    arch-chroot /mnt chown -R "$USERNAME_VALUE:$USERNAME_VALUE" "$target_flutter"

    cat > /mnt/etc/profile.d/wolf-development.sh <<'EOF'
# Wolf Linux - Android / Flutter
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:$PATH"
EOF
    chmod 644 /mnt/etc/profile.d/wolf-development.sh

    # Primeira execução baixa o Dart SDK/cache necessário. Fazemos isso já
    # como o usuário que será dono do SDK para evitar arquivos root-owned.
    arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- \
        env \
        HOME="$user_home" \
        ANDROID_HOME=/opt/android-sdk \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:/usr/bin:/bin" \
        /opt/flutter/bin/flutter --version

    arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- \
        env \
        HOME="$user_home" \
        PATH="/opt/flutter/bin:/usr/bin:/bin" \
        /opt/flutter/bin/flutter config --android-sdk /opt/android-sdk

    cat > /mnt/usr/local/bin/wolf-flutter-doctor <<'EOF'
#!/usr/bin/env bash
set -u

export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:$PATH"

echo "============================================================"
echo "             WOLF LINUX - FLUTTER / ANDROID"
echo "============================================================"
echo
echo "KVM:"
if [[ -e /dev/kvm ]]; then
    ls -l /dev/kvm
    echo "[OK] /dev/kvm disponível."
else
    echo "[AVISO] /dev/kvm não está disponível."
fi
echo
echo "Flutter:"
flutter doctor -v
echo
echo "Para revisar/aceitar as licenças Android:"
echo "  flutter doctor --android-licenses"
EOF
    chmod 755 /mnt/usr/local/bin/wolf-flutter-doctor

    ok "Flutter stable instalado em /opt/flutter."
}

install_oh_my_zsh_and_profile() {
    local omz="/mnt/usr/share/oh-my-zsh"
    local target_omz="/usr/share/oh-my-zsh"
    local user_home="/mnt/home/$USERNAME_VALUE"
    local p10k_theme=""

    info "Configurando Oh My Zsh + Powerlevel10k..."

    if [[ -d "$omz/.git" ]]; then
        arch-chroot /mnt git -C "$target_omz" pull --ff-only
    else
        rm -rf "$omz"
        arch-chroot /mnt git clone \
            --depth=1 \
            https://github.com/ohmyzsh/ohmyzsh.git \
            "$target_omz"
    fi

    p10k_theme="$(
        arch-chroot /mnt pacman -Ql zsh-theme-powerlevel10k 2>/dev/null |
            awk '/powerlevel10k\.zsh-theme$/ {print $2; exit}'
    )"

    [[ -n "$p10k_theme" ]] ||
        die "Não localizei powerlevel10k.zsh-theme no pacote instalado."

    fetch_wolf_asset "zsh/p10k.zsh" /mnt/etc/skel/.p10k.zsh

    mkdir -p /mnt/usr/share/wolf-linux/fastfetch
    mkdir -p /mnt/etc/skel/.config/fastfetch

    cat > /mnt/usr/share/wolf-linux/fastfetch/wolf-linux.txt <<'EOF'
             ⣀ ⣠ ⢀
         ⣀⠄  ⢧⡀⢩⢀⡼  ⠠⣀
       ⣠⠞⠁⣀⣤⢶⣾⣿⠟⣿⣿⣶⣦⣀ ⠙⢦⡀
     ⢠⡾⠁⣠⠞⣿⠟⢛⣿⣿⣿⣿⣿⣿⣿⢿⣷⣄⠈⢻⣄
    ⢠⣿⠁⣰⠋⡰⣯⣶⣿⣿⣿⣿⣿⡿⣿⣷⡎⣿⣿⣧ ⣿⡆
    ⢻⡏⢠⡯⣤⣿⣿⣟⠻⢿⡿⠋⣴⣻⣿⡿⣠⣿⣟⣿⡆⢸⣿⡀
    ⣼⣇⢸⡇⣕⣿⣿⣿⣠⡟⠁⢰⢿⣿⣿⢣⣿⣿⣿⣿⡇⢸⣿⠁
  ⢀⡌ ⣿⡈⣿⣽⣿⣆⢀⣞⣅⡐⢠⠟⣿⠁⢠⣿⣿⣧⣿⢃⣿⠇⢱⡀
   ⠹⡀⠘⢷⡜⢿⡿⠡⠛⠉⠉⣻⣾ ⠈⠻⣄⢻⣿⣿⢏⣾⠃⢀⡞
    ⠙⣴⠃⠛⠮⠵⢊⣀⣀ ⠙⡟⣷⣦ ⢙⣯⠻⣵⢛⠊⣦⠎
    ⠉⠙⣄⠤⣁⠚⠋⠉⠹⣷⡄ ⢨⢿⣾ ⢹⠃⣈⡠⢢⠏⠉
      ⠚⢧ ⣽⠷⢦⣄ ⠙⣰⠈⠸⢋⡴⠾⣯⠁⡰⠛
        ⠑⠻⣄ ⠙⢷⡀⠹⢀⡼⠛ ⣠⠾⠊
              ⠱ ⠘

              WOLF LINUX
EOF

    cat > /mnt/etc/skel/.config/fastfetch/config.jsonc <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "file-raw",
        "source": "/usr/share/wolf-linux/fastfetch/wolf-linux.txt",
        "padding": { "left": 1, "right": 3 }
    },
    "display": {
        "separator": "  ",
        "color": { "keys": "white", "title": "white" },
        "key": { "width": 11 }
    },
    "modules": [
        "title", "separator", "os", "host", "kernel", "uptime",
        "packages", "shell", "display", "de", "wm", "wmtheme",
        "theme", "icons", "terminal", "cpu", "gpu", "memory",
        "disk", "localip"
    ]
}
EOF

    cat > /mnt/usr/share/wolf-linux/fastfetch/wolf-linux-ascii.txt <<'EOF'
             /\        /\
            /  \______/  \
           /              \
          /   /\      /\   \
         |   /  \____/  \   |
         |       _  _        |
         |      / \/ \       |
          \     \_/\_/      /
           \      /\       /
            '._  /  \  _.'
               '-.__.-'

              WOLF LINUX
EOF

    cat > /mnt/etc/skel/.config/fastfetch/config-tty.jsonc <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "file-raw",
        "source": "/usr/share/wolf-linux/fastfetch/wolf-linux-ascii.txt",
        "padding": {
            "left": 1,
            "right": 3
        }
    },
    "display": {
        "separator": " : ",
        "color": {
            "keys": "white",
            "title": "white"
        },
        "key": {
            "width": 10
        }
    },
    "modules": [
        "title",
        "separator",
        "os",
        "host",
        "kernel",
        "uptime",
        "packages",
        "shell",
        "cpu",
        "gpu",
        "memory",
        "disk",
        "localip"
    ]
}
EOF

    cat > /mnt/etc/skel/.zshrc <<EOF
# ============================================================
# Wolf Linux - Zsh / Oh My Zsh / Powerlevel10k
# ============================================================

# ------------------------------------------------------------
# Console virtual Linux (Ctrl+Alt+F2/F3/F4...)
# ------------------------------------------------------------
# O TTY não usa Meslo Nerd Font. Usamos Terminus + logo ASCII e
# um prompt simples para evitar glifos quebrados do Powerlevel10k.
if [[ -z "\${DISPLAY:-}" &&
      -z "\${WAYLAND_DISPLAY:-}" &&
      "\${TTY:-}" == /dev/tty* ]]; then

    export ANDROID_HOME=/opt/android-sdk
    export ANDROID_SDK_ROOT=/opt/android-sdk
    export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:\$PATH"

    if [[ -t 1 && "\${WOLF_FASTFETCH:-1}" != "0" ]] &&
       command -v fastfetch >/dev/null 2>&1; then
        fastfetch --config "\$HOME/.config/fastfetch/config-tty.jsonc"
        echo
    fi

    PROMPT='%F{white}%n@%m%f:%F{cyan}%~%f %# '
    RPROMPT=''
    bindkey -e

    [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
        source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

    [[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] &&
        source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh

    [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
        source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

    return
fi

# Wolf Linux Fastfetch startup v2
# .zshrc já é carregado apenas em shells interativos.
# Mantemos a saída ANTES do instant prompt do Powerlevel10k.
# Para desativar: export WOLF_FASTFETCH=0
if [[ -t 1 && "${WOLF_FASTFETCH:-1}" != "0" ]] &&
   command -v fastfetch >/dev/null 2>&1; then
    fastfetch
    echo
fi

# Powerlevel10k instant prompt. Deve permanecer próximo ao topo.
if [[ -r "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh" ]]; then
    source "\${XDG_CACHE_HOME:-\$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh"
fi

export ZSH="/usr/share/oh-my-zsh"
ZSH_THEME=""
zstyle ':omz:update' mode disabled

plugins=(
    git
    sudo
)

source "\$ZSH/oh-my-zsh.sh"

# Tema Powerlevel10k empacotado pelo Arch/Chaotic-AUR.
source "$p10k_theme"

# Plugins distribuídos como pacotes do Arch.
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

[[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] &&
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh

# Syntax highlighting deve ser carregado por último.
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Flutter / Android
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:\$PATH"

[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

EOF

    mkdir -p "$user_home"

    # Como esta instalação é limpa, aplicamos o perfil Wolf Linux ao usuário
    # principal. Em reinstalações com /home preservado, a limpeza dos dotfiles
    # será tratada posteriormente pela etapa específica de preservação.
    cp -f /mnt/etc/skel/.zshrc "$user_home/.zshrc"
    cp -f /mnt/etc/skel/.p10k.zsh "$user_home/.p10k.zsh"

    mkdir -p "$user_home/.config/fastfetch"
    cp -f \
        /mnt/etc/skel/.config/fastfetch/config.jsonc \
        "$user_home/.config/fastfetch/config.jsonc"

    cp -f \
        /mnt/etc/skel/.config/fastfetch/config-tty.jsonc \
        "$user_home/.config/fastfetch/config-tty.jsonc"

    arch-chroot /mnt chown \
        "$USERNAME_VALUE:$USERNAME_VALUE" \
        "/home/$USERNAME_VALUE/.zshrc" \
        "/home/$USERNAME_VALUE/.p10k.zsh"

    arch-chroot /mnt chown -R \
        "$USERNAME_VALUE:$USERNAME_VALUE" \
        "/home/$USERNAME_VALUE/.config/fastfetch"

    arch-chroot /mnt chsh -s /bin/zsh "$USERNAME_VALUE"

    ok "Zsh/Oh My Zsh/Powerlevel10k configurados."
}

install_terminal_defaults() {
    mkdir -p /mnt/usr/local/bin
    mkdir -p /mnt/etc/xdg/autostart

    cat > /mnt/usr/local/bin/wolf-apply-terminal-style.sh <<'TERMINAL_EOF'
#!/usr/bin/env bash
set -u

MARKER="$HOME/.config/wolf-linux/terminal-v2.done"

[[ -f "$MARKER" ]] && exit 0
mkdir -p "$(dirname "$MARKER")"

FONT="MesloLGS Nerd Font 11"
DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

configure_mate_terminal() {
    command -v gsettings >/dev/null 2>&1 || return 0

    if ! gsettings list-schemas | grep -Fxq 'org.mate.terminal.global'; then
        return 0
    fi

    if ! gsettings list-schemas | grep -Fxq 'org.mate.terminal.profile'; then
        return 0
    fi

    local profile
    local schema

    profile="$(
        gsettings get org.mate.terminal.global default-profile 2>/dev/null \
            | tr -d "'"
    )"
    [[ -n "$profile" ]] || profile="default"

    schema="org.mate.terminal.profile:/org/mate/terminal/profiles/$profile/"

    gsettings set "$schema" use-theme-colors false 2>/dev/null || true
    gsettings set "$schema" background-color '#000000' 2>/dev/null || true
    gsettings set "$schema" foreground-color '#FFFFFF' 2>/dev/null || true
    gsettings set "$schema" use-system-font false 2>/dev/null || true
    gsettings set "$schema" font "$FONT" 2>/dev/null || true

    # Wolf Linux: largura padrão maior para acomodar Fastfetch + Powerlevel10k.
    gsettings set "$schema" use-custom-default-size true 2>/dev/null || true
    gsettings set "$schema" default-size-columns 120 2>/dev/null || true
}

configure_gnome_terminal() {
    command -v gsettings >/dev/null 2>&1 || return 0

    if ! gsettings list-schemas | grep -Fxq 'org.gnome.Terminal.ProfilesList'; then
        return 0
    fi

    local uuid
    local schema

    uuid="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")"
    [[ -n "$uuid" ]] || return 0

    schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"

    gsettings set "$schema" use-theme-colors false 2>/dev/null || true
    gsettings set "$schema" background-color '#000000' 2>/dev/null || true
    gsettings set "$schema" foreground-color '#FFFFFF' 2>/dev/null || true
    gsettings set "$schema" use-system-font false 2>/dev/null || true
    gsettings set "$schema" font "$FONT" 2>/dev/null || true

    gsettings set "$schema" use-custom-default-size true 2>/dev/null || true
    gsettings set "$schema" default-size-columns 120 2>/dev/null || true
}

configure_konsole() {
    mkdir -p "$HOME/.local/share/konsole"

    cat > "$HOME/.local/share/konsole/WolfLinux.colorscheme" <<'EOF'
[Background]
Color=0,0,0

[BackgroundIntense]
Color=0,0,0

[Foreground]
Color=255,255,255

[ForegroundIntense]
Color=255,255,255

[General]
Description=Wolf Linux
Opacity=1
Wallpaper=
EOF

    cat > "$HOME/.local/share/konsole/Wolf Linux.profile" <<EOF
[Appearance]
ColorScheme=WolfLinux
Font=MesloLGS Nerd Font,11,-1,5,50,0,0,0,0,0

[General]
Name=Wolf Linux
Parent=FALLBACK/
EOF

    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 \
            --file konsolerc \
            --group "Desktop Entry" \
            --key DefaultProfile \
            "Wolf Linux.profile" || true
    fi
}

case "$DESKTOP" in
    *MATE*)
        configure_mate_terminal
        ;;
    *X-Cinnamon*|*Cinnamon*)
        configure_gnome_terminal
        ;;
    *KDE*|*Plasma*)
        configure_konsole
        ;;
esac

touch "$MARKER"
TERMINAL_EOF

    chmod 755 /mnt/usr/local/bin/wolf-apply-terminal-style.sh

    cat > /mnt/etc/xdg/autostart/wolf-first-login-terminal.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Configurar terminal
Comment=Aplica terminal preto, texto branco e Nerd Font no primeiro login
Exec=/usr/local/bin/wolf-apply-terminal-style.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    ok "Padrão dos terminais preparado."
}

configure_octopi_notifier() {
    if [[ ! -x /mnt/usr/bin/octopi-notifier ]]; then
        die "Octopi foi solicitado, mas /usr/bin/octopi-notifier não foi instalado."
    fi

    mkdir -p /mnt/etc/xdg/autostart

    cat > /mnt/etc/xdg/autostart/octopi-notifier.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Octopi Notifier
Comment=Verifica atualizações de pacotes após o login
Exec=/usr/bin/octopi-notifier
TryExec=/usr/bin/octopi-notifier
Terminal=false
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    ok "Octopi Notifier configurado para iniciar após o login."
}

set_mkinitcpio_modules() {
    local -a requested=("$@")
    local conf="/mnt/etc/mkinitcpio.conf"
    local module
    local modules_line="MODULES=("
    local first=1

    for module in "${requested[@]}"; do
        [[ -n "$module" ]] || continue

        if (( first == 0 )); then
            modules_line+=" "
        fi

        modules_line+="$module"
        first=0
    done

    modules_line+=")"

    if grep -q '^MODULES=' "$conf"; then
        sed -i "s|^MODULES=.*|$modules_line|" "$conf"
    else
        printf '%s\n' "$modules_line" >> "$conf"
    fi

    info "mkinitcpio: $(grep '^MODULES=' "$conf")"
}

install_mate_windows_layout() {
    [[ "$DESKTOP" == "mate" ]] || {
        info "Layout MATE ignorado: desktop selecionado não é MATE."
        return 0
    }

    info "Instalando layout MATE conhecido como estável..."

    mkdir -p /mnt/usr/share/mate-panel/layouts
    mkdir -p /mnt/usr/local/bin
    mkdir -p /mnt/etc/xdg/autostart

    cat > /mnt/usr/share/mate-panel/layouts/wolf-linux.layout <<'EOF'
[Toplevel bottom]
expand=true
orientation=bottom
size=28

[Object briskmenu]
object-type=applet
applet-iid=BriskMenuFactory::BriskMenu
toplevel-id=bottom
position=0
locked=true

# Janelas abertas imediatamente após o Brisk.
[Object window-list]
object-type=applet
applet-iid=WnckletFactory::WindowListApplet
toplevel-id=bottom
position=42
locked=true

# Launchers fixos ancorados à direita, antes da tray.
[Object caja]
object-type=launcher
launcher-location=/usr/share/applications/caja.desktop
toplevel-id=bottom
position=285
panel-right-stick=true
locked=true

[Object mate-terminal]
object-type=launcher
launcher-location=/usr/share/applications/mate-terminal.desktop
toplevel-id=bottom
position=250
panel-right-stick=true
locked=true

[Object google-chrome]
object-type=launcher
launcher-location=/usr/share/applications/google-chrome.desktop
toplevel-id=bottom
position=215
panel-right-stick=true
locked=true

[Object notification-area]
object-type=applet
applet-iid=NotificationAreaAppletFactory::NotificationArea
toplevel-id=bottom
position=165
panel-right-stick=true
locked=true

[Object clock]
object-type=applet
applet-iid=ClockAppletFactory::ClockApplet
toplevel-id=bottom
position=42
panel-right-stick=true
locked=true

[Object show-desktop]
object-type=applet
applet-iid=WnckletFactory::ShowDesktopApplet
toplevel-id=bottom
position=0
panel-right-stick=true
locked=true
EOF

    cat > /mnt/usr/share/mate-panel/layouts/wolf-linux-fallback.layout <<'EOF'
[Toplevel bottom]
expand=true
orientation=bottom
size=28

[Object menu-bar]
object-type=menu-bar
toplevel-id=bottom
position=0
locked=true

[Object window-list]
object-type=applet
applet-iid=WnckletFactory::WindowListApplet
toplevel-id=bottom
position=130
locked=true

[Object caja]
object-type=launcher
launcher-location=/usr/share/applications/caja.desktop
toplevel-id=bottom
position=250
panel-right-stick=true
locked=true

[Object mate-terminal]
object-type=launcher
launcher-location=/usr/share/applications/mate-terminal.desktop
toplevel-id=bottom
position=215
panel-right-stick=true
locked=true

[Object notification-area]
object-type=applet
applet-iid=NotificationAreaAppletFactory::NotificationArea
toplevel-id=bottom
position=165
panel-right-stick=true
locked=true

[Object clock]
object-type=applet
applet-iid=ClockAppletFactory::ClockApplet
toplevel-id=bottom
position=42
panel-right-stick=true
locked=true

[Object show-desktop]
object-type=applet
applet-iid=WnckletFactory::ShowDesktopApplet
toplevel-id=bottom
position=0
panel-right-stick=true
locked=true
EOF

    cat > /mnt/usr/local/bin/wolf-apply-mate-layout.sh <<'EOF'
#!/usr/bin/env bash
set -u

MARKER="$HOME/.config/wolf-linux/mate-layout-v4.done"
[[ -f "$MARKER" ]] && exit 0
mkdir -p "$(dirname "$MARKER")"

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in
    *MATE*) ;;
    *) exit 0 ;;
esac

# A versão conhecida como boa funcionava melhor deixando o MATE
# terminar de iniciar antes do reset do painel.
sleep 3

LAYOUT="wolf-linux"

# Única verificação do Brisk que usamos na versão que funcionou.
if [[ ! -f /usr/share/mate-panel/applets/com.solus_project.brisk.BriskMenu.mate-panel-applet ]]; then
    echo "[AVISO] Descriptor do Brisk não encontrado; usando fallback."
    LAYOUT="wolf-linux-fallback"
fi

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.mate.panel default-layout "$LAYOUT" 2>/dev/null || true

    if gsettings list-schemas | grep -Fxq 'com.solus-project.brisk-menu'; then
        gsettings set com.solus-project.brisk-menu label-visible false 2>/dev/null || true
    fi
fi

mate-panel --reset --layout "$LAYOUT" >/dev/null 2>&1 || {
    echo "[AVISO] Layout principal falhou; usando fallback."
    LAYOUT="wolf-linux-fallback"
    mate-panel --reset --layout "$LAYOUT" >/dev/null 2>&1 || true
}

touch "$MARKER"
EOF

    chmod 755 /mnt/usr/local/bin/wolf-apply-mate-layout.sh

    cat > /mnt/etc/xdg/autostart/wolf-first-login-mate-layout.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Painel MATE
Comment=Aplica o painel inferior Wolf Linux no primeiro login
Exec=/usr/local/bin/wolf-apply-mate-layout.sh
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    ok "Layout MATE conhecido como estável preparado."
}

install_wolf_branding() {
    info "Instalando branding Wolf Linux..."

    mkdir -p /mnt/usr/share/backgrounds/wolf-linux
    fetch_wolf_asset \
        "wallpapers/wolf-linux-wallpaper.png" \
        /mnt/usr/share/backgrounds/wolf-linux/wallpaper.png

    mkdir -p /mnt/boot/grub/themes/wolf-linux
    fetch_wolf_asset \
        "grub/background.png" \
        /mnt/boot/grub/themes/wolf-linux/background.png

    cat > /mnt/boot/grub/themes/wolf-linux/theme.txt <<'EOF'
desktop-image: "background.png"
desktop-color: "#09090b"
title-text: ""
message-color: "#d8d8dc"
message-bg-color: "#00000000"
+ boot_menu {
    left = 53%
    top = 31%
    width = 40%
    height = 46%
    item_color = "#bdbdc4"
    selected_item_color = "#ffffff"
    item_height = 34
    item_padding = 10
    item_spacing = 6
    scrollbar = false
}
+ label {
    id = "__timeout__"
    left = 53%
    top = 80%
    width = 40%
    align = "center"
    color = "#8f8f96"
    text = "Inicializando em %d segundos..."
}
EOF

    if grep -q '^GRUB_THEME=' /mnt/etc/default/grub; then
        sed -i \
            's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/wolf-linux/theme.txt"|' \
            /mnt/etc/default/grub
    else
        printf '\nGRUB_THEME="/boot/grub/themes/wolf-linux/theme.txt"\n' \
            >> /mnt/etc/default/grub
    fi

    if grep -q '^GRUB_GFXMODE=' /mnt/etc/default/grub; then
        sed -i 's/^GRUB_GFXMODE=.*/GRUB_GFXMODE=auto/' /mnt/etc/default/grub
    else
        printf 'GRUB_GFXMODE=auto\n' >> /mnt/etc/default/grub
    fi

    # Plymouth
    mkdir -p /mnt/usr/share/plymouth/themes/wolf-linux
    fetch_wolf_asset \
        "plymouth/logo.png" \
        /mnt/usr/share/plymouth/themes/wolf-linux/logo.png

    cat > /mnt/usr/share/plymouth/themes/wolf-linux/wolf-linux.plymouth <<'EOF'
[Plymouth Theme]
Name=Wolf Linux
Description=Wolf Linux boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/wolf-linux
ScriptFile=/usr/share/plymouth/themes/wolf-linux/wolf-linux.script
EOF

    cat > /mnt/usr/share/plymouth/themes/wolf-linux/wolf-linux.script <<'EOF'
Window.SetBackgroundTopColor(0.02, 0.02, 0.025);
Window.SetBackgroundBottomColor(0.02, 0.02, 0.025);

logo_image = Image("logo.png");
logo_sprite = Sprite(logo_image);

fun position_logo() {
    logo_sprite.SetX(Window.GetWidth() / 2 - logo_image.GetWidth() / 2);
    logo_sprite.SetY(Window.GetHeight() / 2 - logo_image.GetHeight() / 2);
}

position_logo();
Plymouth.SetRefreshFunction(position_logo);
EOF

    arch-chroot /mnt plymouth-set-default-theme wolf-linux

    if ! grep '^HOOKS=' /mnt/etc/mkinitcpio.conf | grep -qw plymouth; then
        if grep '^HOOKS=' /mnt/etc/mkinitcpio.conf | grep -qw systemd; then
            sed -i '/^HOOKS=/ s/systemd/systemd plymouth/' /mnt/etc/mkinitcpio.conf
        else
            sed -i '/^HOOKS=/ s/base/base plymouth/' /mnt/etc/mkinitcpio.conf
        fi
    fi

    # --------------------------------------------------------
    # SDDM Wolf Linux baseado no sddm-astronaut-theme.
    # Upstream: https://github.com/Keyitdev/sddm-astronaut-theme
    # GPL-3.0-or-later. O clone mantém LICENSE e os avisos de copyright.
    # --------------------------------------------------------
    local sddm_target="/mnt/usr/share/sddm/themes/wolf-linux"

    info "Instalando framework SDDM Astronaut como base do Wolf Linux..."

    rm -rf "$sddm_target"

    arch-chroot /mnt git clone \
        --depth=1 \
        --branch master \
        https://github.com/Keyitdev/sddm-astronaut-theme.git \
        /usr/share/sddm/themes/wolf-linux

    # Não precisamos manter o histórico Git na máquina instalada.
    rm -rf "$sddm_target/.git"

    [[ -f "$sddm_target/Main.qml" ]] ||
        die "Clone do sddm-astronaut-theme não contém Main.qml."

    [[ -d "$sddm_target/Components" ]] ||
        die "Clone do sddm-astronaut-theme não contém Components/."

    # Background Wolf Linux substitui a arte upstream, mas preservamos
    # o framework QML e a licença.
    mkdir -p "$sddm_target/Backgrounds"

    fetch_wolf_asset \
        "sddm/background.png" \
        "$sddm_target/Backgrounds/wolf-linux.png"

    mkdir -p "$sddm_target/Themes"

    # Layout próprio:
    # - arte Wolf Linux à esquerda;
    # - formulário à direita;
    # - fundo do form translúcido + blur parcial;
    # - cores monocromáticas;
    # - botões de sistema preservados.
    cat > "$sddm_target/Themes/wolf_linux.conf" <<'EOF'
[General]
#################### Wolf Linux ####################

ScreenWidth="1920"
ScreenHeight="1080"
ScreenPadding="18"

Font="Noto Sans"
FontSize="13"

KeyboardSize="0.4"
RoundCorners="18"

Locale="pt_BR"
HourFormat="HH:mm"
DateFormat="dddd, d 'de' MMMM"

HeaderText="Wolf Linux"

#################### Background ####################

BackgroundPlaceholder=""
Background="Backgrounds/wolf-linux.png"
BackgroundSpeed=""
PauseBackground=""

DimBackground="0.08"
CropBackground="true"
BackgroundHorizontalAlignment="center"
BackgroundVerticalAlignment="center"

#################### Colors ####################

HeaderTextColor="#f2f2f5"
DateTextColor="#b8b8c0"
TimeTextColor="#ffffff"

FormBackgroundColor="#0b0b10"
BackgroundColor="#08080b"
DimBackgroundColor="#000000"

LoginFieldBackgroundColor="#18181f"
PasswordFieldBackgroundColor="#18181f"

LoginFieldTextColor="#ffffff"
PasswordFieldTextColor="#ffffff"

UserIconColor="#d6d6dd"
PasswordIconColor="#d6d6dd"

PlaceholderTextColor="#8f8f99"
WarningColor="#d06776"

LoginButtonTextColor="#ffffff"
LoginButtonBackgroundColor="#2a2a33"

SystemButtonsIconsColor="#d6d6dd"
SessionButtonTextColor="#c7c7cf"
VirtualKeyboardButtonTextColor="#c7c7cf"

DropdownTextColor="#ffffff"
DropdownSelectedBackgroundColor="#35353f"
DropdownBackgroundColor="#15151b"

HighlightTextColor="#ffffff"
HighlightBackgroundColor="#35353f"
HighlightBorderColor="#777783"

HoverUserIconColor="#ffffff"
HoverPasswordIconColor="#ffffff"
HoverSystemButtonsIconsColor="#ffffff"
HoverSessionButtonTextColor="#ffffff"
HoverVirtualKeyboardButtonTextColor="#ffffff"

#################### Form ####################

PartialBlur="true"
FullBlur="false"
BlurMax="48"
Blur="1.2"

HaveFormBackground="true"
FormPosition="right"

#################### Virtual Keyboard ####################

VirtualKeyboardPosition="right"

#################### Interface ####################

HideVirtualKeyboard="true"
HideSystemButtons="false"
HideLoginButton="false"

UseRealName="true"
ForceLastUser="true"
PasswordFocus="true"
HideCompletePassword="true"
AllowEmptyPassword="false"

BypassSystemButtonsChecks="false"
RightToLeftLayout="false"

#################### Translation ####################

TranslatePlaceholderUsername="Usuário"
TranslatePlaceholderPassword="Senha"
TranslateLogin="Entrar"
TranslateLoginFailedWarning="Falha no login"
TranslateCapslockWarning="Caps Lock ativado"
TranslateSuspend="Suspender"
TranslateHibernate="Hibernar"
TranslateReboot="Reiniciar"
TranslateShutdown="Desligar"
TranslateSessionSelection="Sessão"
TranslateVirtualKeyboardButtonOn="Teclado virtual"
TranslateVirtualKeyboardButtonOff="Fechar teclado"
EOF

    # Metadata própria, deixando explícita a origem e licença.
    cat > "$sddm_target/metadata.desktop" <<'EOF'
[SddmGreeterTheme]
Name=Wolf Linux
Description=Wolf Linux SDDM theme based on sddm-astronaut-theme
Author=Wolf Linux / Keyitdev upstream
Website=https://github.com/Keyitdev/sddm-astronaut-theme
License=GPL-3.0-or-later
Type=sddm-theme
Version=1.0
ConfigFile=Themes/wolf_linux.conf
Screenshot=Backgrounds/wolf-linux.png
MainScript=Main.qml
TranslationsDirectory=translations
Theme-Id=wolf-linux
Theme-API=2.0
QtVersion=6
EOF

    # Dependência recomendada pelo upstream para o teclado virtual Qt6.
    mkdir -p /mnt/etc/sddm.conf.d

    cat > /mnt/etc/sddm.conf.d/10-wolf-linux-theme.conf <<'EOF'
[Theme]
Current=wolf-linux
CursorTheme=breeze-dark
CursorSize=24
EOF

    cat > /mnt/etc/sddm.conf.d/11-wolf-linux-virtualkbd.conf <<'EOF'
[General]
InputMethod=qtvirtualkeyboard
EOF

    # NumLock:
    # 1) usa a opção nativa do SDDM;
    # 2) em X11 aplica numlockx pelo DisplayCommand como redundância.
    mkdir -p /mnt/usr/local/libexec

    cat > /mnt/usr/local/libexec/wolf-sddm-xsetup <<'EOF'
#!/bin/sh

if [ -x /usr/share/sddm/scripts/Xsetup ]; then
    /usr/share/sddm/scripts/Xsetup "$@" || true
fi

if [ -x /usr/bin/numlockx ]; then
    /usr/bin/numlockx on || true
fi

exit 0
EOF

    chmod 755 /mnt/usr/local/libexec/wolf-sddm-xsetup

    cat > /mnt/etc/sddm.conf.d/12-wolf-linux-numlock.conf <<'EOF'
[General]
Numlock=on

[X11]
DisplayCommand=/usr/local/libexec/wolf-sddm-xsetup
EOF

    cat > "$sddm_target/WOLF-LINUX-NOTES.txt" <<'EOF'
Wolf Linux customization of:
https://github.com/Keyitdev/sddm-astronaut-theme

The upstream QML framework and assets remain under GPL-3.0-or-later.
The Wolf Linux customization provides its own configuration and background.
See the upstream LICENSE file included in this directory.
EOF

    # Valida os arquivos essenciais antes de concluir a etapa.
    [[ -f "$sddm_target/LICENSE" ]] ||
        die "LICENSE do tema upstream não foi preservada."

    [[ -f "$sddm_target/Themes/wolf_linux.conf" ]] ||
        die "Config Wolf Linux do SDDM não foi criada."

    ok "SDDM Wolf Linux baseado no Astronaut Theme instalado."

    # Wallpaper on first login.
    cat > /mnt/usr/local/bin/wolf-apply-wallpaper.sh <<'EOF'
#!/usr/bin/env bash
set -u

MARKER="$HOME/.config/wolf-linux/wallpaper-v1.done"
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"

[[ -f "$MARKER" ]] && exit 0
mkdir -p "$(dirname "$MARKER")"

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

case "$DESKTOP" in
    *MATE*)
        if gsettings list-schemas | grep -Fxq 'org.mate.background'; then
            gsettings set org.mate.background picture-filename "$WALLPAPER" || true
            gsettings set org.mate.background picture-options 'zoom' || true
        fi
        ;;
    *X-Cinnamon*|*Cinnamon*)
        if gsettings list-schemas | grep -Fxq 'org.cinnamon.desktop.background'; then
            gsettings set org.cinnamon.desktop.background picture-uri "file://$WALLPAPER" || true
            gsettings set org.cinnamon.desktop.background picture-options 'zoom' || true
        fi
        ;;
    *KDE*|*Plasma*)
        if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
            plasma-apply-wallpaperimage "$WALLPAPER" >/dev/null 2>&1 || true
        fi
        ;;
esac

touch "$MARKER"
EOF
    chmod 755 /mnt/usr/local/bin/wolf-apply-wallpaper.sh

    cat > /mnt/etc/xdg/autostart/wolf-first-login-wallpaper.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Wallpaper
Comment=Aplica o wallpaper padrão Wolf Linux
Exec=/usr/local/bin/wolf-apply-wallpaper.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    arch-chroot /mnt mkinitcpio -P

    # Useful when branding is added to an already-completed test VM.
    if [[ -f /mnt/boot/grub/grub.cfg ]]; then
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    fi

    ok "Branding Wolf Linux instalado."
}


install_desktop_productivity_extras() {
    info "Configurando aplicativos padrão, previews e integrações do desktop..."

    # --------------------------------------------------------
    # Aplicativos padrão por usuário.
    # --------------------------------------------------------
    mkdir -p /mnt/usr/local/bin
    mkdir -p /mnt/etc/xdg/autostart

    cat > /mnt/usr/local/bin/wolf-apply-default-apps.sh <<'EOF'
#!/usr/bin/env bash
set -u

MARKER="$HOME/.config/wolf-linux/default-apps-v2.done"
mkdir -p "$(dirname "$MARKER")"

[[ -f "$MARKER" ]] && exit 0

set_default() {
    local desktop="$1"
    shift
    local mime

    for mime in "$@"; do
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
    done
}

# SMPlayer para vídeo.
set_default smplayer.desktop \
    video/mp4 \
    video/x-matroska \
    video/webm \
    video/mpeg \
    video/quicktime \
    video/x-msvideo \
    video/x-ms-wmv \
    video/x-flv \
    video/ogg \
    application/x-matroska

# Audacious para áudio e playlists.
set_default audacious.desktop \
    audio/mpeg \
    audio/mp4 \
    audio/aac \
    audio/flac \
    audio/x-flac \
    audio/ogg \
    audio/vorbis \
    audio/x-vorbis+ogg \
    audio/x-wav \
    audio/wav \
    audio/x-mpegurl \
    audio/x-scpls \
    application/xspf+xml \
    application/vnd.apple.mpegurl

# Também aproveita todos os MIME types de áudio/vídeo anunciados
# pelos próprios .desktop, para acompanhar atualizações futuras.
if [[ -r /usr/share/applications/smplayer.desktop ]]; then
    while IFS= read -r mime; do
        [[ "$mime" == video/* ]] || continue
        xdg-mime default smplayer.desktop "$mime" >/dev/null 2>&1 || true
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/smplayer.desktop \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

if [[ -r /usr/share/applications/audacious.desktop ]]; then
    while IFS= read -r mime; do
        [[ "$mime" == audio/* ]] || continue
        xdg-mime default audacious.desktop "$mime" >/dev/null 2>&1 || true
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/audacious.desktop \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

# Caja: miniaturas sempre habilitadas e limite alto para vídeos grandes.
if gsettings list-schemas 2>/dev/null | grep -Fxq 'org.mate.caja.preferences'; then
    if gsettings list-keys org.mate.caja.preferences 2>/dev/null \
        | grep -Fxq 'show-image-thumbnails'; then
        gsettings set org.mate.caja.preferences show-image-thumbnails 'always' || true
    fi

    if gsettings list-keys org.mate.caja.preferences 2>/dev/null \
        | grep -Fxq 'thumbnail-limit'; then
        # 64 GiB: cobre arquivos grandes sem tornar o valor virtualmente ilimitado.
        gsettings set org.mate.caja.preferences thumbnail-limit 68719476736 || true
    fi
fi

touch "$MARKER"
EOF

    chmod 755 /mnt/usr/local/bin/wolf-apply-default-apps.sh

    cat > /mnt/etc/xdg/autostart/wolf-default-apps.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Aplicativos padrão
Comment=Configura SMPlayer, Audacious e preferências de miniaturas
Exec=/usr/local/bin/wolf-apply-default-apps.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # --------------------------------------------------------
    # Integrações específicas do MATE.
    # --------------------------------------------------------
    if [[ "$DESKTOP" != "mate" ]]; then
        ok "Defaults e thumbnailers preparados; integrações Caja/X11 não se aplicam ao desktop escolhido."
        return 0
    fi

    # --------------------------------------------------------
    # Caja: Abrir pasta no VS Code.
    # python-caja carrega extensões globais de /usr/share/caja-python/extensions.
    # --------------------------------------------------------
    mkdir -p /mnt/usr/share/caja-python/extensions

    cat > /mnt/usr/share/caja-python/extensions/wolf_vscode.py <<'PY'
import shutil
import subprocess

from gi.repository import Caja, GObject


class WolfVSCodeExtension(GObject.GObject, Caja.MenuProvider):
    def _code_available(self):
        return shutil.which("code") is not None

    def _open(self, file_info):
        if not self._code_available():
            return

        location = file_info.get_location()
        if location is None:
            return

        path = location.get_path()
        if not path:
            return

        subprocess.Popen(
            ["code", "--new-window", path],
            cwd=path,
            start_new_session=True,
        )

    def _selected_activate(self, menu, file_info):
        self._open(file_info)

    def _background_activate(self, menu, file_info):
        self._open(file_info)

    def get_file_items(self, window, files):
        if not self._code_available() or len(files) != 1:
            return

        file_info = files[0]

        if not file_info.is_directory():
            return

        if file_info.get_uri_scheme() != "file":
            return

        item = Caja.MenuItem(
            name="WolfLinux::VSCodeFolder",
            label="Abrir pasta no VS Code",
            tip="Abrir esta pasta em uma nova janela do Visual Studio Code",
        )
        item.connect("activate", self._selected_activate, file_info)
        return [item]

    def get_background_items(self, window, current_folder):
        if not self._code_available():
            return

        if current_folder.get_uri_scheme() != "file":
            return

        item = Caja.MenuItem(
            name="WolfLinux::VSCodeCurrentFolder",
            label="Abrir esta pasta no VS Code",
            tip="Abrir a pasta atual em uma nova janela do Visual Studio Code",
        )
        item.connect("activate", self._background_activate, current_folder)
        return [item]
PY

    # --------------------------------------------------------
    # Preferência de tema escuro também para aplicações GNOME/libhandy.
    #
    # O MATE usa org.mate.interface, mas aplicações GNOME modernas podem
    # consultar org.gnome.desktop.interface/color-scheme. Mantemos ambos
    # alinhados com a identidade visual Wolf Linux.
    # --------------------------------------------------------
    cat > /mnt/usr/local/bin/wolf-apply-dark-preference <<'EOF'
#!/usr/bin/env bash
set -u

set_if_available() {
    local schema="$1"
    local key="$2"
    local value="$3"

    gsettings list-schemas 2>/dev/null | grep -Fxq "$schema" || return 0
    gsettings list-keys "$schema" 2>/dev/null | grep -Fxq "$key" || return 0

    gsettings set "$schema" "$key" "$value" 2>/dev/null || true
}

set_if_available org.mate.interface gtk-theme "'Materia-dark'"
set_if_available org.mate.interface icon-theme "'Papirus-Dark'"

set_if_available org.gnome.desktop.interface gtk-theme "'Materia-dark'"
set_if_available org.gnome.desktop.interface icon-theme "'Papirus-Dark'"
set_if_available org.gnome.desktop.interface color-scheme "'prefer-dark'"

# Em MATE, aplicações GNOME/libhandy consultam a preferência publicada
# pelo XDG Desktop Portal. Reiniciar os portais após gravar o GSettings
# garante que org.freedesktop.appearance/color-scheme reflita prefer-dark.
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user restart \
        xdg-desktop-portal-gtk.service \
        xdg-desktop-portal.service \
        >/dev/null 2>&1 || true
fi
EOF

    chmod 755 /mnt/usr/local/bin/wolf-apply-dark-preference

    cat > /mnt/etc/xdg/autostart/wolf-dark-preference.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Preferência de tema escuro
Comment=Mantém aplicações MATE/GNOME alinhadas com o tema escuro Wolf Linux
Exec=/usr/local/bin/wolf-apply-dark-preference
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # --------------------------------------------------------
    # Mídias removíveis
    #
    # udiskie fica responsável SOMENTE pela bandeja/ações manuais.
    # O automount continua com Caja/GVfs para evitar disputa entre dois
    # automounters na mesma sessão.
    # --------------------------------------------------------
    cat > /mnt/etc/xdg/autostart/wolf-udiskie.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Mídias removíveis
Comment=Bandeja para montar, desmontar e ejetar mídias removíveis
Exec=/usr/bin/udiskie --smart-tray --no-automount --no-notify --file-manager=/usr/bin/caja
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # Helper centralizado para a integração "Formatar mídia removível".
    # Ele só libera o GNOME Disks para o DIRETÓRIO RAIZ de um filesystem
    # montado em um dispositivo removível/USB/MMC.
    cat > /mnt/usr/local/bin/wolf-format-removable <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    echo "Uso:"
    echo "  wolf-format-removable --check CAMINHO"
    echo "  wolf-format-removable --format CAMINHO"
}

resolve_device() {
    local input="$1"
    local real_path
    local source
    local target
    local real_target
    local parent=""
    local disk=""
    local rm_flag=""
    local transport=""

    real_path="$(readlink -f -- "$input" 2>/dev/null || true)"
    [[ -n "$real_path" && -d "$real_path" ]] || return 1

    source="$(
        findmnt \
            --noheadings \
            --output SOURCE \
            --target "$real_path" \
            2>/dev/null \
            | head -n1 \
            | xargs
    )"

    target="$(
        findmnt \
            --noheadings \
            --output TARGET \
            --target "$real_path" \
            2>/dev/null \
            | head -n1 \
            | xargs
    )"

    [[ -n "$source" && -n "$target" ]] || return 1

    # Btrfs/subvolume pode aparecer como /dev/...[/subvolume].
    source="${source%%\\[*}"

    [[ "$source" == /dev/* ]] || return 1

    real_target="$(readlink -f -- "$target" 2>/dev/null || true)"
    [[ "$real_path" == "$real_target" ]] || return 1

    parent="$(
        lsblk \
            --noheadings \
            --output PKNAME \
            "$source" \
            2>/dev/null \
            | head -n1 \
            | xargs
    )"

    if [[ -n "$parent" ]]; then
        disk="/dev/$parent"
    else
        disk="$source"
    fi

    rm_flag="$(
        lsblk \
            --nodeps \
            --noheadings \
            --output RM \
            "$disk" \
            2>/dev/null \
            | head -n1 \
            | xargs
    )"

    transport="$(
        lsblk \
            --nodeps \
            --noheadings \
            --output TRAN \
            "$disk" \
            2>/dev/null \
            | head -n1 \
            | xargs
    )"

    case "$transport" in
        usb|mmc)
            ;;
        *)
            [[ "$rm_flag" == "1" ]] || return 1
            ;;
    esac

    printf '%s\n' "$source"
}

[[ $# -eq 2 ]] || {
    usage
    exit 2
}

mode="$1"
path="$2"

device="$(resolve_device "$path")" || exit 1

case "$mode" in
    --check)
        printf '%s\n' "$device"
        ;;

    --format)
        command -v gnome-disks >/dev/null 2>&1 || {
            echo "[ERRO] gnome-disks não encontrado." >&2
            exit 1
        }

        # GNOME Disks abre o diálogo "Formatar volume" e exige confirmação
        # do usuário; nenhuma formatação é feita silenciosamente.
        exec gnome-disks \
            --block-device "$device" \
            --format-device
        ;;

    *)
        usage
        exit 2
        ;;
esac
EOF

    chmod 755 /mnt/usr/local/bin/wolf-format-removable

    cat > /mnt/usr/share/caja-python/extensions/wolf_removable_media.py <<'PY'
import os
import subprocess

from gi.repository import Caja, GObject


HELPER = "/usr/local/bin/wolf-format-removable"


class WolfRemovableMediaExtension(GObject.GObject, Caja.MenuProvider):
    def _path(self, file_info):
        if file_info is None:
            return None

        if file_info.get_uri_scheme() != "file":
            return None

        location = file_info.get_location()
        if location is None:
            return None

        path = location.get_path()

        if not path or not os.path.isdir(path):
            return None

        return path

    def _is_removable_root(self, path):
        if not path or not os.path.exists(HELPER):
            return False

        try:
            result = subprocess.run(
                [HELPER, "--check", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=1.5,
                check=False,
            )
            return result.returncode == 0
        except Exception:
            return False

    def _format(self, _menu, path):
        try:
            subprocess.Popen(
                [HELPER, "--format", path],
                start_new_session=True,
            )
        except Exception:
            pass

    def _item(self, path):
        item = Caja.MenuItem(
            name="WolfLinux::FormatRemovable",
            label="Formatar mídia removível…",
            tip="Abrir o diálogo seguro de formatação para esta mídia",
        )
        item.connect("activate", self._format, path)
        return item

    def get_file_items(self, window, files):
        if len(files) != 1:
            return

        path = self._path(files[0])

        if not self._is_removable_root(path):
            return

        return [self._item(path)]

    def get_background_items(self, window, current_folder):
        path = self._path(current_folder)

        if not self._is_removable_root(path):
            return

        return [self._item(path)]
PY

    # --------------------------------------------------------
    # Mouse sem aceleração no X11/libinput.
    # Touchpads ficam fora desta regra.
    # --------------------------------------------------------
    mkdir -p /mnt/etc/X11/xorg.conf.d

    cat > /mnt/etc/X11/xorg.conf.d/50-wolf-mouse-no-accel.conf <<'EOF'
Section "InputClass"
    Identifier "Wolf Linux - Mouse sem aceleracao"
    MatchIsPointer "on"
    MatchIsTouchpad "off"
    MatchDriver "libinput"

    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
EndSection
EOF

    # Reforço na sessão: executa depois que o MATE/settings-daemon inicia.
    # Assim uma preferência antiga do usuário não devolve o perfil adaptive.
    cat > /mnt/usr/local/bin/wolf-disable-mouse-accel.sh <<'EOF'
#!/usr/bin/env bash
set -u

sleep 2

command -v xinput >/dev/null 2>&1 || exit 0

while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue

    props="$(xinput list-props "$id" 2>/dev/null || true)"

    # Não altera touchpads.
    if grep -q 'libinput Tapping Enabled' <<<"$props"; then
        continue
    fi

    if grep -q 'libinput Accel Profile Enabled' <<<"$props"; then
        profile_line="$(
            grep -m1 'libinput Accel Profile Enabled (' <<<"$props" \
                || true
        )"
        values="${profile_line##*:}"
        values="$(tr -d '[:space:]' <<<"$values")"

        # xf86-input-libinput pode expor 2 perfis (adaptive, flat)
        # ou 3 perfis (adaptive, flat, custom), dependendo da versão/
        # dispositivo. O segundo valor é sempre o perfil flat.
        case "$values" in
            *,*,*)
                xinput set-prop \
                    "$id" \
                    'libinput Accel Profile Enabled' \
                    0 1 0 \
                    >/dev/null 2>&1 || true
                ;;
            *,*)
                xinput set-prop \
                    "$id" \
                    'libinput Accel Profile Enabled' \
                    0 1 \
                    >/dev/null 2>&1 || true
                ;;
        esac
    fi

    if grep -q 'libinput Accel Speed' <<<"$props"; then
        xinput set-prop "$id" 'libinput Accel Speed' 0 \
            >/dev/null 2>&1 || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
EOF

    chmod 755 /mnt/usr/local/bin/wolf-disable-mouse-accel.sh

    cat > /mnt/etc/xdg/autostart/wolf-disable-mouse-accel.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Mouse sem aceleração
Comment=Força perfil flat do libinput para mice no MATE/X11
Exec=/usr/local/bin/wolf-disable-mouse-accel.sh
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # --------------------------------------------------------
    # Wolf Edge Barrier
    #
    # Uma pequena barreira XFixes nos primeiros 36 px da divisa vertical
    # entre monitores. O restante da borda continua livre.
    # --------------------------------------------------------
    mkdir -p /mnt/usr/local/src

    cat > /mnt/usr/local/src/wolf-edge-barrier.c <<'C'
#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>
#include <X11/extensions/Xfixes.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_MONITORS 16
#define MAX_BARRIERS 128

typedef struct {
    int x;
    int y;
    int w;
    int h;
} Monitor;

static volatile sig_atomic_t keep_running = 1;

static void handle_signal(int sig) {
    (void)sig;
    keep_running = 0;
}

static int read_monitors(Monitor *out, int max_count) {
    FILE *fp = popen("xrandr --query 2>/dev/null", "r");
    if (!fp) {
        return 0;
    }

    char line[2048];
    int count = 0;

    while (fgets(line, sizeof(line), fp) && count < max_count) {
        if (strstr(line, " connected ") == NULL) {
            continue;
        }

        char copy[2048];
        snprintf(copy, sizeof(copy), "%s", line);

        char *save = NULL;
        char *token = strtok_r(copy, " \t\r\n", &save);

        while (token) {
            char *end = NULL;
            char *next = NULL;

            long w = strtol(token, &end, 10);

            if (end == token || *end != 'x') {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            long h = strtol(end + 1, &next, 10);

            if (next == end + 1 || (*next != '+' && *next != '-')) {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            long x = strtol(next, &end, 10);

            if (end == next || (*end != '+' && *end != '-')) {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            long y = strtol(end, &next, 10);

            if (next == end || *next != '\0') {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            out[count].x = (int)x;
            out[count].y = (int)y;
            out[count].w = (int)w;
            out[count].h = (int)h;
            count++;
            break;
        }
    }

    pclose(fp);
    return count;
}

static int monitors_equal(const Monitor *a, int na, const Monitor *b, int nb) {
    if (na != nb) {
        return 0;
    }

    for (int i = 0; i < na; i++) {
        if (
            a[i].x != b[i].x ||
            a[i].y != b[i].y ||
            a[i].w != b[i].w ||
            a[i].h != b[i].h
        ) {
            return 0;
        }
    }

    return 1;
}

static void destroy_barriers(
    Display *display,
    PointerBarrier *barriers,
    int *barrier_count
) {
    for (int i = 0; i < *barrier_count; i++) {
        XFixesDestroyPointerBarrier(display, barriers[i]);
    }

    *barrier_count = 0;
    XSync(display, False);
}

static void rebuild_barriers(
    Display *display,
    Window root,
    const Monitor *monitors,
    int monitor_count,
    int barrier_size,
    PointerBarrier *barriers,
    int *barrier_count
) {
    destroy_barriers(display, barriers, barrier_count);

    if (monitor_count < 2 || barrier_size <= 0) {
        return;
    }

    for (int i = 0; i < monitor_count; i++) {
        for (int j = i + 1; j < monitor_count; j++) {
            int boundary_x = 0;
            int adjacent = 0;

            if (monitors[i].x + monitors[i].w == monitors[j].x) {
                boundary_x = monitors[j].x;
                adjacent = 1;
            } else if (monitors[j].x + monitors[j].w == monitors[i].x) {
                boundary_x = monitors[i].x;
                adjacent = 1;
            }

            if (!adjacent) {
                continue;
            }

            int overlap_top =
                monitors[i].y > monitors[j].y
                    ? monitors[i].y
                    : monitors[j].y;

            int bottom_i = monitors[i].y + monitors[i].h;
            int bottom_j = monitors[j].y + monitors[j].h;

            int overlap_bottom =
                bottom_i < bottom_j
                    ? bottom_i
                    : bottom_j;

            if (overlap_bottom <= overlap_top) {
                continue;
            }

            int top_end = overlap_top + barrier_size;

            if (top_end > overlap_bottom) {
                top_end = overlap_bottom;
            }

            if (top_end > overlap_top) {
                if (*barrier_count >= MAX_BARRIERS) {
                    fprintf(stderr, "wolf-edge-barrier: limite de barreiras atingido\n");
                    XSync(display, False);
                    return;
                }

                barriers[*barrier_count] = XFixesCreatePointerBarrier(
                    display,
                    root,
                    boundary_x,
                    overlap_top,
                    boundary_x,
                    top_end,
                    0,
                    0,
                    NULL
                );
                (*barrier_count)++;
            }

            int bottom_start = overlap_bottom - barrier_size;

            if (bottom_start < top_end) {
                bottom_start = top_end;
            }

            if (bottom_start < overlap_bottom) {
                if (*barrier_count >= MAX_BARRIERS) {
                    fprintf(stderr, "wolf-edge-barrier: limite de barreiras atingido\n");
                    XSync(display, False);
                    return;
                }

                barriers[*barrier_count] = XFixesCreatePointerBarrier(
                    display,
                    root,
                    boundary_x,
                    bottom_start,
                    boundary_x,
                    overlap_bottom,
                    0,
                    0,
                    NULL
                );
                (*barrier_count)++;
            }
        }
    }

    XSync(display, False);
}

int main(int argc, char **argv) {
    int barrier_size = 36;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--size") == 0 && i + 1 < argc) {
            barrier_size = atoi(argv[++i]);

            if (barrier_size < 0 || barrier_size > 300) {
                fprintf(stderr, "wolf-edge-barrier: --size deve estar entre 0 e 300\n");
                return 2;
            }
        } else if (strcmp(argv[i], "--help") == 0) {
            printf("Uso: wolf-edge-barrier [--size PIXELS]\n");
            return 0;
        }
    }

    Display *display = XOpenDisplay(NULL);

    if (!display) {
        fprintf(stderr, "wolf-edge-barrier: não foi possível abrir DISPLAY\n");
        return 1;
    }

    int event_base = 0;
    int error_base = 0;

    if (!XFixesQueryExtension(display, &event_base, &error_base)) {
        fprintf(stderr, "wolf-edge-barrier: XFixes não disponível\n");
        XCloseDisplay(display);
        return 1;
    }

    int major = 5;
    int minor = 0;

    if (!XFixesQueryVersion(display, &major, &minor) || major < 5) {
        fprintf(stderr, "wolf-edge-barrier: XFixes >= 5 necessário\n");
        XCloseDisplay(display);
        return 1;
    }

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGHUP, handle_signal);

    Window root = DefaultRootWindow(display);

    Monitor previous[MAX_MONITORS];
    Monitor current[MAX_MONITORS];
    int previous_count = -1;

    PointerBarrier barriers[MAX_BARRIERS];
    int barrier_count = 0;

    while (keep_running) {
        int current_count = read_monitors(current, MAX_MONITORS);

        if (!monitors_equal(previous, previous_count, current, current_count)) {
            rebuild_barriers(
                display,
                root,
                current,
                current_count,
                barrier_size,
                barriers,
                &barrier_count
            );

            memcpy(previous, current, sizeof(current));
            previous_count = current_count;
        }

        sleep(2);
    }

    destroy_barriers(display, barriers, &barrier_count);
    XCloseDisplay(display);
    return 0;
}
C

    arch-chroot /mnt cc \
        -O2 \
        -Wall \
        -Wextra \
        -std=c11 \
        /usr/local/src/wolf-edge-barrier.c \
        -o /usr/local/bin/wolf-edge-barrier \
        -lX11 \
        -lXfixes

    chmod 755 /mnt/usr/local/bin/wolf-edge-barrier

    cat > /mnt/etc/xdg/autostart/wolf-edge-barrier.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Barreira entre monitores
Comment=Protege os cantos superiores e inferiores entre monitores no MATE/X11
Exec=/usr/local/bin/wolf-edge-barrier --size 36
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # Documentação simples/configuração para facilitar ajuste posterior.
    mkdir -p /mnt/etc/wolf-linux
    cat > /mnt/etc/wolf-linux/edge-barrier.conf <<'EOF'
# Wolf Linux - edge barrier
# O autostart atual usa 36 pixels no topo e 36 pixels na base.
# Para alterar, edite:
# /etc/xdg/autostart/wolf-edge-barrier.desktop
TOP_BARRIER_PIXELS=36
EOF

    ok "Integrações MATE prontas: VS Code no Caja + edge barrier multi-monitor."
}
install_gpu_profile() {
    local -a packages=()
    local -a early_modules=()

    case "$GPU_PROFILE" in
        virtio)
            packages=("${VIRTIO_GPU_PACKAGES[@]}")
            early_modules=(virtio_gpu)
            ;;

        intel)
            packages=("${INTEL_GPU_PACKAGES[@]}")
            early_modules=(i915)
            ;;

        amd)
            packages=("${AMD_GPU_PACKAGES[@]}")
            early_modules=(amdgpu)
            ;;

        nvidia-modern)
            packages=("${NVIDIA_MODERN_PACKAGES[@]}")

            if (( GPU_HAS_INTEL == 1 )); then
                packages+=("${INTEL_GPU_PACKAGES[@]}")
                early_modules+=(i915)
            fi

            if (( GPU_HAS_AMD == 1 )); then
                packages+=("${AMD_GPU_PACKAGES[@]}")
                early_modules+=(amdgpu)
            fi

            early_modules+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
            ;;

        nvidia-kepler-nouveau)
            packages=("${NVIDIA_NOUVEAU_PACKAGES[@]}")

            if (( GPU_HAS_INTEL == 1 )); then
                packages+=("${INTEL_GPU_PACKAGES[@]}")
                early_modules+=(i915)
            fi

            if (( GPU_HAS_AMD == 1 )); then
                packages+=("${AMD_GPU_PACKAGES[@]}")
                early_modules+=(amdgpu)
            fi

            early_modules+=(nouveau)
            ;;

        nvidia-legacy-or-unknown)
            warn "NVIDIA legacy/desconhecida: usando Nouveau por segurança."
            packages=("${NVIDIA_NOUVEAU_PACKAGES[@]}")
            early_modules=(nouveau)
            ;;

        *)
            warn "GPU não reconhecida; usando Mesa básico."
            packages=(mesa lib32-mesa)
            ;;
    esac

    info "Instalando perfil gráfico '$GPU_PROFILE'..."
    arch-chroot /mnt pacman -S --needed --noconfirm "${packages[@]}"

    if [[ "$GPU_PROFILE" == "nvidia-modern" ]]; then
        mkdir -p /mnt/etc/modprobe.d
        printf 'options nvidia_drm modeset=1\n' \
            > /mnt/etc/modprobe.d/nvidia-drm.conf
    fi

    if ((${#early_modules[@]} > 0)); then
        set_mkinitcpio_modules "${early_modules[@]}"
    fi

    arch-chroot /mnt mkinitcpio -P

    cat > /mnt/etc/wolf-linux-video.conf <<EOF
GPU_PROFILE=$GPU_PROFILE
GPU_HAS_INTEL=$GPU_HAS_INTEL
GPU_HAS_AMD=$GPU_HAS_AMD
GPU_HAS_NVIDIA=$GPU_HAS_NVIDIA
EOF

    ok "Perfil gráfico instalado: $GPU_PROFILE"
}

validate_graphics_stack() {
    echo
    echo "Validando perfil gráfico: $GPU_PROFILE"

    case "$GPU_PROFILE" in
        nvidia-modern)
            arch-chroot /mnt pacman -Q \
                nvidia-open-dkms \
                nvidia-utils \
                lib32-nvidia-utils \
                nvidia-settings
            ;;
        amd)
            arch-chroot /mnt pacman -Q \
                vulkan-radeon \
                lib32-vulkan-radeon
            ;;
        intel)
            arch-chroot /mnt pacman -Q \
                vulkan-intel \
                lib32-vulkan-intel
            ;;
        virtio)
            arch-chroot /mnt pacman -Q \
                vulkan-virtio \
                lib32-vulkan-virtio
            ;;
        nvidia-kepler-nouveau|nvidia-legacy-or-unknown)
            arch-chroot /mnt pacman -Q \
                vulkan-nouveau \
                lib32-vulkan-nouveau
            ;;
    esac

    ok "Perfil gráfico validado."
}

install_gaming_stack() {
    info "Instalando stack gaming..."
    arch-chroot /mnt pacman -S --needed --noconfirm \
        "${GAMING_PACKAGES[@]}"

    local pkg
    local validation_failed=0

    for pkg in \
        steam \
        lutris \
        wine \
        winetricks \
        protontricks \
        protonup-qt \
        gamemode; do

        if arch-chroot /mnt pacman -Q "$pkg" >/dev/null 2>&1; then
            printf '  [OK] %s\n' "$pkg"
        else
            printf '  [ERRO] %s\n' "$pkg"
            validation_failed=1
        fi
    done

    (( validation_failed == 0 )) ||
        die "A stack gaming não passou na validação."

    ok "Stack gaming instalada."
}

install_mate_wolf_theme() {
    [[ "$DESKTOP" == "mate" ]] || {
        info "Tema MATE Wolf ignorado: desktop selecionado não é MATE."
        return 0
    }

    info "Instalando tema final MATE: Materia-dark + Sunrise Wolf..."

    local workdir="/tmp/wolf-sunrise-border"
    local archive="$workdir/sunrise.tar.gz"
    local extract_dir="$workdir/extracted"
    local source_theme=""
    local source_root=""
    local border_target="/mnt/usr/share/themes/Wolf-Sunrise-Border"
    local meta_target="/mnt/usr/share/themes/Wolf-Linux"

    [[ -d /mnt/usr/share/themes/Materia-dark ]] ||
        die "Materia-dark não encontrado. Verifique materia-gtk-theme."

    rm -rf "$workdir" "$border_target" "$meta_target"
    mkdir -p "$extract_dir"
    mkdir -p /mnt/usr/share/themes

    info "Baixando Sunrise apenas para a decoração Marco..."

    curl \
        -fL \
        --retry 3 \
        --connect-timeout 15 \
        https://github.com/i-mint/sunrise/archive/refs/heads/master.tar.gz \
        -o "$archive"

    tar -xzf "$archive" -C "$extract_dir"

    source_theme="$(
        find "$extract_dir" \
            -mindepth 2 \
            -maxdepth 2 \
            -type d \
            -name 'Sunrise-Dark' \
            -print \
            -quit
    )"

    [[ -n "$source_theme" && -d "$source_theme/metacity-1" ]] || {
        echo
        echo "Conteúdo Sunrise encontrado:"
        find "$extract_dir" -maxdepth 2 -mindepth 1 -type d -print || true
        echo
        die "Decoração metacity-1 do Sunrise-Dark não encontrada."
    }

    source_root="$(dirname "$source_theme")"

    mkdir -p "$border_target"
    cp -a "$source_theme/metacity-1" "$border_target/metacity-1"

    if [[ -f "$source_root/COPYING" ]]; then
        cp -f "$source_root/COPYING" "$border_target/COPYING"
    fi

    cat > "$border_target/index.theme" <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Wolf-Sunrise-Border
Comment=Wolf Linux neutral Sunrise window decoration
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Materia-dark
MetacityTheme=Wolf-Sunrise-Border
IconTheme=Papirus-Dark
CursorTheme=breeze-dark
NotificationTheme=coco
ButtonLayout=menu:minimize,maximize,close
EOF

    # Reproduz exatamente a estratégia aprovada no Theme Base Lab:
    # somente a decoração Sunrise é neutralizada. Materia-dark permanece
    # completamente original, evitando mistura de CSS/paletas.
    arch-chroot /mnt python - <<'PY'
from pathlib import Path
from PIL import Image
import colorsys
import re

root = Path("/usr/share/themes/Wolf-Sunrise-Border/metacity-1")

ACCENT = (96, 99, 109)
ACCENT_HI = (132, 135, 146)
ACCENT_DARK = (67, 69, 77)

def neutral(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)

    warm = (
        (0.01 <= h <= 0.20 and s >= 0.05 and v >= 0.08)
        or (r > g * 1.10 and g >= b * 0.88 and r - b >= 9)
    )

    if not warm:
        return None

    lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255

    if lum >= 0.67:
        return ACCENT_HI
    if lum >= 0.34:
        return ACCENT
    return ACCENT_DARK

hex6 = re.compile(r"#[0-9a-fA-F]{6}\b")
hex3 = re.compile(r"#[0-9a-fA-F]{3}\b")
rgbfn = re.compile(
    r"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(\s*,\s*[^)]+)?\)"
)

def replace_hex6(match):
    token = match.group(0)
    out = neutral(
        int(token[1:3], 16),
        int(token[3:5], 16),
        int(token[5:7], 16),
    )

    if out is None:
        return token

    return "#%02x%02x%02x" % out

def replace_hex3(match):
    token = match.group(0)
    out = neutral(
        int(token[1] * 2, 16),
        int(token[2] * 2, 16),
        int(token[3] * 2, 16),
    )

    if out is None:
        return token

    return "#%02x%02x%02x" % out

def replace_rgb(match):
    r, g, b = [min(255, int(match.group(i))) for i in (1, 2, 3)]
    out = neutral(r, g, b)

    if out is None:
        return match.group(0)

    alpha = match.group(4) or ""

    if alpha:
        return f"rgba({out[0]}, {out[1]}, {out[2]}{alpha})"

    return f"rgb({out[0]}, {out[1]}, {out[2]})"

changed_text = 0
changed_png = 0

for path in root.rglob("*"):
    if not path.is_file():
        continue

    if path.suffix.lower() in {".xml", ".svg", ".xpm", ".rc"}:
        try:
            original = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        updated = hex6.sub(replace_hex6, original)
        updated = hex3.sub(replace_hex3, updated)
        updated = rgbfn.sub(replace_rgb, updated)
        updated = re.sub(r"\bdarkorange\b", "#43454d", updated, flags=re.I)
        updated = re.sub(r"\borange\b", "#60636d", updated, flags=re.I)

        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed_text += 1

    elif path.suffix.lower() == ".png":
        try:
            image = Image.open(path).convert("RGBA")
        except Exception:
            continue

        pixels = []
        changed = False

        for r, g, b, a in image.getdata():
            out = neutral(r, g, b)

            if a and out is not None:
                pixels.append((*out, a))
                changed = True
            else:
                pixels.append((r, g, b, a))

        if changed:
            image.putdata(pixels)
            image.save(path)
            changed_png += 1

print(f"Sunrise Wolf: {changed_text} arquivos textuais e {changed_png} PNGs neutralizados.")
PY

    # Metatheme exibido no Preferências de Aparência como "Wolf Linux".
    # Ele combina os componentes finais aprovados sem duplicar Materia.
    mkdir -p "$meta_target"

    cat > "$meta_target/index.theme" <<'EOF'
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Wolf Linux
Comment=Wolf Linux MATE desktop theme
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=Materia-dark
MetacityTheme=Wolf-Sunrise-Border
IconTheme=Papirus-Dark
CursorTheme=breeze-dark
NotificationTheme=coco
ButtonLayout=menu:minimize,maximize,close
EOF

    cat > "$border_target/WOLF-LINUX-NOTES.txt" <<'EOF'
Wolf Linux MATE theme
=====================

GTK base:
  Materia-dark
  package: materia-gtk-theme

Window decoration:
  Sunrise-Dark metacity/Marco component
  https://github.com/i-mint/sunrise

Only the Sunrise window-decoration component is recolored to a neutral
graphite/silver palette. The Materia GTK theme is kept unmodified.

Other components:
  Icons: Papirus-Dark
  Cursor: Breeze Dark
  Notifications: Coco
EOF

    rm -rf "$workdir"

    ok "Tema final MATE preparado: Materia-dark + Wolf-Sunrise-Border."
}

install_mate_session_setup() {
    [[ "$DESKTOP" == "mate" ]] || {
        info "Setup de sessão MATE ignorado: desktop selecionado não é MATE."
        return 0
    }

    mkdir -p /mnt/usr/local/bin
    mkdir -p /mnt/etc/xdg/autostart

    cat > /mnt/usr/local/bin/wolf-mate-session-setup.sh <<'EOF'
#!/usr/bin/env bash
set -u

STATE_DIR="$HOME/.local/state/wolf-linux"
LOG="$STATE_DIR/mate-session-setup.log"
MARKER="$HOME/.config/wolf-linux/mate-session-v5.done"

mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$MARKER")"
exec >>"$LOG" 2>&1

echo
echo "============================================================"
echo "Wolf Linux - tema/wallpaper/teclado MATE"
date
echo "============================================================"

[[ -f "$MARKER" ]] && exit 0

ready=0
for attempt in $(seq 1 15); do
    if command -v gsettings >/dev/null 2>&1 \
       && gsettings list-schemas 2>/dev/null | grep -Fxq 'org.mate.interface'; then
        ready=1
        break
    fi
    sleep 2
done

(( ready == 1 )) || {
    echo "[ERRO] GSettings/MATE não ficaram prontos."
    exit 1
}

# Tema / ícones / cursor
gsettings reset org.mate.interface gtk-color-scheme 2>/dev/null || true
gsettings set org.mate.interface gtk-theme 'Materia-dark'
gsettings set org.mate.interface icon-theme 'Papirus-Dark'
gsettings set org.mate.Marco.general theme 'Wolf-Sunrise-Border' 2>/dev/null || true
gsettings set org.mate.peripherals-mouse cursor-theme 'breeze-dark' 2>/dev/null || true
gsettings set org.mate.peripherals-mouse cursor-size 24 2>/dev/null || true

# Notificações MATE: Coco combina melhor com o perfil escuro Wolf Linux.
if gsettings list-schemas | grep -Fxq 'org.mate.NotificationDaemon'; then
    gsettings set org.mate.NotificationDaemon theme 'coco' || true
fi

# Wallpaper
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
if [[ -f "$WALLPAPER" ]]; then
    gsettings set org.mate.background picture-filename "$WALLPAPER"
    gsettings set org.mate.background picture-options 'zoom'
fi

# Teclado
XKB_LAYOUT="br"
XKB_VARIANT="abnt2"
MATE_LAYOUT=$'br\tabnt2'

if [[ -r /etc/wolf-linux-keyboard.conf ]]; then
    # shellcheck disable=SC1091
    source /etc/wolf-linux-keyboard.conf
fi

gsettings set org.mate.peripherals-keyboard-xkb.kbd model "'pc105'" 2>/dev/null || true
gsettings set org.mate.peripherals-keyboard-xkb.kbd layouts "['$MATE_LAYOUT']" 2>/dev/null || true

command -v setxkbmap >/dev/null 2>&1 \
    && setxkbmap "$XKB_LAYOUT" -variant "$XKB_VARIANT" || true

# NumLock dentro da sessão MATE.
if gsettings list-schemas | grep -Fxq 'org.mate.peripherals-keyboard'; then
    gsettings set org.mate.peripherals-keyboard remember-numlock-state false 2>/dev/null || true
    gsettings set org.mate.peripherals-keyboard numlock-state 'on' 2>/dev/null || true
fi

command -v numlockx >/dev/null 2>&1 && numlockx on 2>/dev/null || true

# Coco deve ser aplicado POR ÚLTIMO. Algumas trocas de tema do MATE
# podem reescrever org.mate.NotificationDaemon/theme.
if gsettings list-schemas | grep -Fxq 'org.mate.NotificationDaemon'; then
    NOTIFY_OK=0

    for attempt in 1 2 3 4 5; do
        gsettings set org.mate.NotificationDaemon theme 'coco' || true

        NOTIFY_NOW="$(gsettings get org.mate.NotificationDaemon theme 2>/dev/null || true)"

        if [[ "$NOTIFY_NOW" == "'coco'" ]]; then
            NOTIFY_OK=1
            break
        fi

        sleep 1
    done

    if (( NOTIFY_OK == 1 )); then
        # O daemon pode manter o renderer anterior em memória.
        pkill -x mate-notification-daemon 2>/dev/null || true
        sleep 1
    else
        echo "[AVISO] Não foi possível fixar o tema de notificações Coco."
    fi
fi

# Validação do que ESTE script é responsável por.
THEME_NOW="$(gsettings get org.mate.interface gtk-theme 2>/dev/null || true)"
WALL_NOW="$(gsettings get org.mate.background picture-filename 2>/dev/null || true)"

echo "Tema atual: $THEME_NOW"
echo "Wallpaper atual: $WALL_NOW"

[[ "$THEME_NOW" == "'Materia-dark'" ]] || exit 1
[[ "$WALL_NOW" == "'$WALLPAPER'" ]] || exit 1

# O painel é propositalmente tratado por wolf-apply-mate-layout.sh.
touch "$MARKER"
echo "[OK] Tema/wallpaper/teclado MATE concluídos."
EOF

    chmod 755 /mnt/usr/local/bin/wolf-mate-session-setup.sh

    cat > /mnt/etc/xdg/autostart/wolf-mate-session-setup.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Configurar MATE
Comment=Aplica tema, wallpaper e teclado Wolf Linux
Exec=/usr/local/bin/wolf-mate-session-setup.sh
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # Os scripts genéricos não precisam disputar o MATE.
    if [[ -f /mnt/etc/xdg/autostart/wolf-first-login-style.desktop ]]; then
        grep -q '^NotShowIn=' /mnt/etc/xdg/autostart/wolf-first-login-style.desktop \
            || printf 'NotShowIn=MATE;\n' >> /mnt/etc/xdg/autostart/wolf-first-login-style.desktop
    fi

    if [[ -f /mnt/etc/xdg/autostart/wolf-first-login-wallpaper.desktop ]]; then
        grep -q '^NotShowIn=' /mnt/etc/xdg/autostart/wolf-first-login-wallpaper.desktop \
            || printf 'NotShowIn=MATE;\n' >> /mnt/etc/xdg/autostart/wolf-first-login-wallpaper.desktop
    fi

    ok "Setup MATE sem manipulação de painel preparado."
}

install_visual_defaults() {
    info "Preparando padrões visuais Wolf Linux para o primeiro login..."

    mkdir -p /mnt/usr/local/bin
    mkdir -p /mnt/etc/xdg/autostart
    mkdir -p /mnt/usr/share/icons/default

    cat > /mnt/usr/local/bin/wolf-apply-desktop-style.sh <<'STYLE_EOF'
#!/usr/bin/env bash
set -u

MARKER="$HOME/.config/wolf-linux/style-v1.done"

[[ -f "$MARKER" ]] && exit 0

mkdir -p "$(dirname "$MARKER")"
mkdir -p "$HOME/.config/gtk-3.0"
mkdir -p "$HOME/.config/gtk-4.0"
mkdir -p "$HOME/.local/share/icons/default"

cat > "$HOME/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=true
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=breeze-dark
gtk-cursor-theme-size=24
EOF

cat > "$HOME/.config/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=true
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=breeze-dark
gtk-cursor-theme-size=24
EOF

cat > "$HOME/.local/share/icons/default/index.theme" <<'EOF'
[Icon Theme]
Inherits=breeze-dark
EOF

KEYBOARD_PROFILE="abnt2"
XKB_LAYOUT="br"
XKB_VARIANT="abnt2"
CINNAMON_LAYOUT="br"
MATE_LAYOUT=$'br\tabnt2'

if [[ -r /etc/wolf-linux-keyboard.conf ]]; then
    # shellcheck disable=SC1091
    source /etc/wolf-linux-keyboard.conf
fi

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

case "$DESKTOP" in
    *MATE*)
        if gsettings list-schemas | grep -Fxq 'org.mate.interface'; then
            gsettings reset org.mate.interface gtk-color-scheme 2>/dev/null || true
gsettings set org.mate.interface gtk-theme 'Materia-dark' || true
            gsettings set org.mate.interface icon-theme 'Papirus-Dark' || true
        fi

        if gsettings list-schemas | grep -Fxq 'org.mate.Marco.general'; then
            gsettings set org.mate.Marco.general theme 'Wolf-Sunrise-Border' || true
        fi

        if gsettings list-schemas | grep -Fxq 'org.mate.peripherals-mouse'; then
            gsettings set org.mate.peripherals-mouse cursor-theme 'breeze-dark' || true
            gsettings set org.mate.peripherals-mouse cursor-size 24 || true
        fi

        if gsettings list-schemas | grep -Fxq 'org.mate.peripherals-keyboard-xkb.kbd'; then
            gsettings set org.mate.peripherals-keyboard-xkb.kbd model "'pc105'" || true
            gsettings set org.mate.peripherals-keyboard-xkb.kbd layouts "['$MATE_LAYOUT']" || true
        fi

        if command -v setxkbmap >/dev/null 2>&1; then
            setxkbmap "$XKB_LAYOUT" -variant "$XKB_VARIANT" || true
        fi
        ;;

    *X-Cinnamon*|*Cinnamon*)
        if gsettings list-schemas | grep -Fxq 'org.cinnamon.desktop.interface'; then
            gsettings set org.cinnamon.desktop.interface gtk-theme 'Adwaita-dark' || true
            gsettings set org.cinnamon.desktop.interface icon-theme 'Papirus-Dark' || true
            gsettings set org.cinnamon.desktop.interface cursor-theme 'breeze-dark' || true
            gsettings set org.cinnamon.desktop.interface cursor-size 24 || true
        fi

        if [[ -d /usr/share/themes/Cinnamon-Dark ]]; then
            gsettings set org.cinnamon.theme name 'Cinnamon-Dark' || true
        fi

        if gsettings list-schemas | grep -Fxq 'org.cinnamon.desktop.input-sources'; then
            gsettings set org.cinnamon.desktop.input-sources \
                sources "[('xkb', '$CINNAMON_LAYOUT')]" || true
        fi

        if command -v setxkbmap >/dev/null 2>&1; then
            setxkbmap "$XKB_LAYOUT" -variant "$XKB_VARIANT" || true
        fi
        ;;

    *KDE*|*Plasma*)
        if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
            plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
        fi

        if command -v kwriteconfig6 >/dev/null 2>&1; then
            kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme breeze-dark || true
            kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize 24 || true
            kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark || true

            kwriteconfig6 --file kxkbrc --group Layout --key Use true || true
            kwriteconfig6 --file kxkbrc --group Layout --key Model pc105 || true
            kwriteconfig6 --file kxkbrc --group Layout --key LayoutList "$XKB_LAYOUT" || true
            kwriteconfig6 --file kxkbrc --group Layout --key VariantList "$XKB_VARIANT" || true
        fi
        ;;
esac

touch "$MARKER"
STYLE_EOF

    chmod 755 /mnt/usr/local/bin/wolf-apply-desktop-style.sh

    cat > /mnt/etc/xdg/autostart/wolf-first-login-style.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Aplicar estilo inicial
Comment=Aplica tema escuro, ícones e cursor padrão no primeiro login
Exec=/usr/local/bin/wolf-apply-desktop-style.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/usr/share/icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=breeze-dark
EOF

    ok "Padrões visuais preparados para o primeiro login."
}

configure_bootloader() {
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        info "Instalando GRUB UEFI..."

        arch-chroot /mnt grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --bootloader-id=WolfLinux \
            --recheck

        # Na VM instalamos também o caminho UEFI fallback.
        # Assim ela consegue iniciar mesmo sem uma entrada NVRAM válida.
        if [[ "$VM_TYPE" == "qemu" || "$VM_TYPE" == "kvm" ]]; then
            info "VM UEFI: instalando fallback EFI/BOOT/BOOTX64.EFI..."

            arch-chroot /mnt grub-install \
                --target=x86_64-efi \
                --efi-directory=/boot/efi \
                --removable \
                --recheck
        fi
    else
        info "Instalando GRUB BIOS/Legacy..."

        arch-chroot /mnt grub-install \
            --target=i386-pc \
            "$INSTALL_DISK"
    fi

    sed -i \
        's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash"/' \
        /mnt/etc/default/grub

    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

validate_boot_installation() {
    echo
    echo "Validando instalação de boot..."

    local kernel="/mnt/boot/vmlinuz-linux-zen"
    local initramfs="/mnt/boot/initramfs-linux-zen.img"
    local grub_cfg="/mnt/boot/grub/grub.cfg"

    [[ -s "$kernel" ]] ||
        die "Kernel linux-zen ausente ou vazio: /boot/vmlinuz-linux-zen"

    [[ -s "$initramfs" ]] ||
        die "Initramfs linux-zen ausente ou vazio: /boot/initramfs-linux-zen.img"

    [[ -s "$grub_cfg" ]] ||
        die "grub.cfg ausente ou vazio."

    arch-chroot /mnt grub-script-check /boot/grub/grub.cfg

    grep -q 'vmlinuz-linux-zen' "$grub_cfg" ||
        die "grub.cfg não contém uma entrada para vmlinuz-linux-zen."

    grep -q 'initramfs-linux-zen.img' "$grub_cfg" ||
        die "grub.cfg não referencia initramfs-linux-zen.img."

    echo
    echo "Arquivos de boot:"
    ls -lh "$kernel" "$initramfs" "$grub_cfg"

    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        local found_efi=""
        local fallback_efi="/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI"

        found_efi="$(
            find /mnt/boot/efi/EFI \
                -maxdepth 3 \
                -type f \
                -iname '*.efi' \
                -print \
                -quit 2>/dev/null || true
        )"

        [[ -n "$found_efi" ]] ||
            die "Nenhum executável EFI foi encontrado na ESP."

        echo
        echo "Executáveis EFI:"
        find /mnt/boot/efi/EFI \
            -maxdepth 3 \
            -type f \
            -iname '*.efi' \
            -print 2>/dev/null || true

        if [[ "$VM_TYPE" == "qemu" || "$VM_TYPE" == "kvm" ]]; then
            [[ -s "$fallback_efi" ]] ||
                die "Fallback UEFI da VM ausente: EFI/BOOT/BOOTX64.EFI"

            ok "Fallback UEFI da VM validado."
        fi

        echo
        echo "Entradas NVRAM:"
        efibootmgr -v 2>/dev/null || true
    fi

    ok "GRUB, kernel, initramfs e arquivos de boot validados."
}

finalize_vm_install() {
    sync

    echo
    echo "============================================================"
    if [[ "$VM_TYPE" == "qemu" || "$VM_TYPE" == "kvm" ]]; then
        echo "       INSTALAÇÃO WOLF LINUX CONCLUÍDA NA VM"
    else
        echo "      INSTALAÇÃO WOLF LINUX CONCLUÍDA NO HARDWARE"
    fi
    echo "============================================================"
    echo "Desktop ....: $DESKTOP"
    echo "Usuário ....: $USERNAME_VALUE"
    echo "Kernel .....: linux-zen"
    echo "SDDM .......: habilitado"
    echo "PipeWire ...: instalado"
    echo "sudo .......: wheel + pwfeedback"
    echo
    echo "Incluído nesta etapa:"
    echo "  - Chaotic-AUR + fallback AUR/yay"
    echo "  - Internet e desenvolvimento"
    echo "  - Google Chrome / JDownloader / AB Download Manager"
    echo "  - Android Studio/SDK / VS Code / Insomnia"
    echo "  - Powerlevel10k (pacote)"
    [[ "$DESKTOP" == "mate" ]] && echo "  - Brisk Menu"
    echo
    echo "Também incluído agora:"
    echo "  - Octopi + Octopi Notifier após o login"
    echo "  - perfil gráfico automático: $GPU_PROFILE"
    echo "  - Vulkan 64/32-bit adequado à GPU"
    echo "  - Steam / Lutris / Wine / Proton tools / GameMode"
    echo
    echo "Ambiente do usuário:"
    echo "  - Flutter stable em /opt/flutter"
    echo "  - Android SDK integrado ao PATH"
    echo "  - Zsh + Oh My Zsh + Powerlevel10k"
    echo "  - configuração Powerlevel10k atual do usuário"
    echo "  - terminal preto/branco + Meslo Nerd Font"
    echo
    echo "Identidade visual:"
    [[ "$DESKTOP" == "mate" ]] && echo "  - painel MATE inferior estilo Windows + Brisk Menu"
    echo "  - wallpaper Wolf Linux"
    echo "  - GRUB Wolf Linux"
    echo "  - Plymouth Wolf Linux"
    echo "  - SDDM Wolf Linux"
    echo "============================================================"
}

main() {
    banner
    check_runtime
    detect_boot
    detect_cpu
    detect_gpu
    detect_keyboard
    check_network
    choose_desktop
    collect_identity
    storage_planner
    plan_preserved_home_cleanup
    show_plan

    if (( DRY_RUN == 1 || PLAN_ONLY == 1 )); then
        ok "Dry-run/plano concluído: nenhuma operação destrutiva executada."
        exit 0
    fi

    confirm_installation

    stage "10-preparar-disco" prepare_erase_disk
    stage "20-formatar-montar" format_and_mount
    stage "22-limpar-home" clean_preserved_home_dotfiles
    stage "25-repositorios-live" prepare_live_repositories
    stage "27-validar-pacotes" validate_base_packages
    stage "30-pacstrap" install_base_system
    stage "40-fstab" generate_fstab
    stage "50-multilib" configure_multilib
    stage "55-completar-pacotes-base" complete_base_packages
    stage "60-sistema-base" configure_system_base
    stage "61-identidade-wolf" configure_wolf_identity
    stage "62-usuario-sudo" configure_user_sudo
    stage "63-chaotic-aur" configure_chaotic_aur
    stage "64-apps-oficiais" install_official_personal_apps
    stage "65-yay" ensure_yay
    stage "66-apps-terceiros" install_third_party_apps
    stage "66b-octopi-notifier" configure_octopi_notifier
    stage "67-servicos" configure_services
    stage "67b-tema-mate" install_mate_wolf_theme
    stage "68-estilo-base" install_visual_defaults
    stage "68a-mate-session" install_mate_session_setup
    stage "68b-flutter" install_flutter_sdk
    stage "68c-zsh" install_oh_my_zsh_and_profile
    stage "68d-terminal" install_terminal_defaults
    stage "68e-mate-layout" install_mate_windows_layout
    stage "68f-desktop-extras" install_desktop_productivity_extras
    stage "69-video" install_gpu_profile
    stage "69b-validar-video" validate_graphics_stack
    stage "69c-gaming" install_gaming_stack
    stage "69d-branding" install_wolf_branding
    stage "70-bootloader" configure_bootloader
    stage "72-validar-boot" validate_boot_installation
    stage "80-finalizar" finalize_vm_install
}

main "$@"
