#!/usr/bin/env bash

# O shell interativo da ISO oficial do Arch é Zsh, mas este instalador é Bash.
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -Eeuo pipefail

WOLF_VERSION="2.0.0"
DRY_RUN=0
PLAN_ONLY=0
RESET_STATE=0
VM_INSTALL=0
REAL_INSTALL=0
GUI_VM_PLAN=""
GUI_VM_CLICK_CONFIRMED=0
GUI_LAB42_PLAN=""
GUI_PHYSICAL_PLAN=""
PHYSICAL_ROOT_UUID=""
PHYSICAL_ESP_UUID=""
PHYSICAL_HOME_UUID=""
LAB42_ROOT_UUID=""
LAB42_ESP_UUID=""
LAB42_HOME_UUID=""
GUI_VM_DISK=""
GUI_VM_MAJMIN=""
GUI_VM_MODE=""
GUI_ERASE_ROOT_GIB=0
GUI_ERASE_HOME_GIB=0
GUI_ERASE_SEPARATE=no
HOME_CLEAN_CONFIRMED="no"
HOME_CLEAN_LIST_FILE=""

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || true)"

# Revisão multidisco continua EXCLUSIVAMENTE leitura. O executor físico
# usa entrada própria, verifica novamente o JSON read-only e exige consentimento.
if [[ "${1:-}" == "--review-multidisk-plan" || "${1:-}" == "--simulate-multidisk-plan" ]]; then
    if (( $# != 2 )); then
        echo '[ERRO] Informe o JSON de planejamento multidisco.' >&2
        exit 2
    fi
    action=review
    [[ "$1" == "--simulate-multidisk-plan" ]] && action=simulate
    exec /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_discovery.py" "$action" "$2"
fi

# Ensaio físico independente: APENAS inventário e relatório de etapas.
# Não chega a main(), checkpoints, pacstrap ou qualquer operação destrutiva.
if [[ "${1:-}" == "--rehearse-multidisk-physical" ]]; then
    (( $# == 2 )) || { echo '[ERRO] Informe o JSON multidisco para o ensaio físico.' >&2; exit 2; }
    exec /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_physical_rehearsal.py" "$2"
fi

# Preflight do laboratório QEMU multidisco: somente inspeção, sem escrita.
if [[ "${1:-}" == "--preflight-multidisk-physical" ]]; then
    (( $# == 2 )) || { echo "[ERRO] Informe o JSON para preflight físico." >&2; exit 2; }
    exec /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_physical_executor.py" check "$2"
fi

if [[ "${1:-}" == "--preflight-multidisk-lab-vm" ]]; then
    (( $# == 2 )) || { echo '[ERRO] Informe o JSON Lab42.' >&2; exit 2; }
    exec /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_lab42.py" check "$2"
fi

# Entrada exclusivamente de leitura, ANTES do estado, rede, partições e main.
# Não transforma o documento da GUI em argumentos de instalação.
if [[ "${1:-}" == "--review-gui-plan" || "${1:-}" == "--simulate-gui-plan" || "${1:-}" == "--preflight-gui-plan-vm" ]]; then
    if (( $# != 2 )); then
        echo '[ERRO] Uso: wolf-install --review-gui-plan|--simulate-gui-plan /caminho/preview.json' >&2
        exit 2
    fi
    case "$1" in
        --simulate-gui-plan) action=simulate ;;
        --preflight-gui-plan-vm) action=vm-preflight ;;
        *) action=review ;;
    esac
    exec /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_plan.py" "$action" "$2"
fi
[[ -r "$PROJECT_DIR/VERSION" ]] && WOLF_VERSION="$(< "$PROJECT_DIR/VERSION")"
PACKAGES_FILE="${WOLF_PACKAGES_FILE:-$PROJECT_DIR/package-profiles/packages.conf}"
ASSET_DIR="${WOLF_ASSET_DIR:-}"
ASSET_BASE_URL="${WOLF_ASSET_BASE_URL:-}"

STATE_DIR="/tmp/wolf-linux-installer"
LOG_FILE="$STATE_DIR/wolf-install.log"
PACKAGE_RESOLUTION_LOG="$STATE_DIR/package-resolution.log"
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

DESKTOP="plasma"
STACK_PRESET=""
STACKS_ARG=""
LIST_STACKS=0
declare -A SELECTED_STACKS=()
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
    printf 'Wolf Linux Installer %s - KDE Plasma / Wayland baseline\n\n' "$WOLF_VERSION"
    cat <<'EOF'
Uso:
  ./wolf-install.sh [opções]

Modos de instalação:
  --dry-run             Detecta hardware, coleta opções e mostra o plano.
  --plan-only           Gera o plano e encerra.
  --review-gui-plan F   Revisa o JSON experimental da GUI (leitura APENAS).
  --simulate-gui-plan F Simula etapas compatíveis com o Bash (SEM executar).
  --review-multidisk-plan F  Revalida plano multidisco/LVM (SOMENTE leitura).
  --simulate-multidisk-plan F Revalida e simula plano multidisco (SEM executar).
  --rehearse-multidisk-physical F  Ensaio físico integral: roteiro, NENHUMA escrita.
  --preflight-gui-plan-vm F Valida instalação em VM (somente leitura).
  --execute-gui-plan-vm F  Instala em disco VirtIO de VM; exige confirmação no terminal.
  --execute-gui-plan-vm-click F  Executor VM autorizado após duas confirmações GUI.
  --preflight-multidisk-lab-vm F  Confere laboratório 2 VirtIO sem escrita.
  --execute-multidisk-lab-vm F   Reinstala laboratório alpha41 (APENAS VM QEMU).
  --preflight-multidisk-physical F  Pré-teste de segurança da instalação física.
  --execute-multidisk-physical F   Instala SOMENTE na topologia física validada.
  --vm-install          Instalação real apenas em QEMU/KVM/VirtualBox.
  --install             Instalação real em hardware físico.
  --reset-state         Limpa checkpoints temporários.

Seleção de software:
  --preset full         Todas as stacks opcionais (padrão do Wagner).
  --preset test         VM/teste: daily + gaming + development + extras.
                        Não instala Android/Flutter nem containers.
  --preset minimal      Somente sistema + KDE Plasma/Wayland.
  --preset custom       Abre seleção interativa das stacks.
  --stacks LISTA        Seleção explícita, separada por vírgulas.
                        Ex.: daily,gaming,development
  --list-stacks         Lista as stacks disponíveis e encerra.

Stacks opcionais:
  daily, gaming, development, android, containers, extras

Helpers Wolf:
  São transportados pela ISO e copiados para o sistema instalado,
  com Branding e MultiMonitor aplicados uma vez no primeiro login.
  Gamepad e GRUB Manager permanecem manuais; sem watchers permanentes.

SEGURANÇA:
  --vm-install é recusado fora de QEMU/KVM/VirtualBox.
  --install é recusado quando uma VM suportada é detectada.
EOF
}

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --plan-only) PLAN_ONLY=1 ;;
        --vm-install) VM_INSTALL=1 ;;
        --execute-gui-plan-vm-click)
            shift
            [[ $# -gt 0 && -z "$GUI_VM_PLAN" ]] || { echo '[ERRO] Plano da instalação GUI ausente/duplicado.' >&2; exit 2; }
            GUI_VM_PLAN="$1"
            VM_INSTALL=1
            GUI_VM_CLICK_CONFIRMED=1
            ;;
        --execute-gui-plan-vm)
            shift
            [[ $# -gt 0 && -z "$GUI_VM_PLAN" ]] || { echo "[ERRO] Plano VM ausente/duplicado." >&2; exit 2; }
            GUI_VM_PLAN="$1"
            VM_INSTALL=1
            ;;
        --execute-multidisk-lab-vm)
            shift
            [[ $# -gt 0 && -z "$GUI_LAB42_PLAN" ]] || { echo '[ERRO] Plano do laboratório ausente ou duplicado.' >&2; exit 2; }
            GUI_LAB42_PLAN="$1"
            VM_INSTALL=1
            ;;
        --execute-multidisk-physical)
            shift
            [[ $# -gt 0 && -z "$GUI_PHYSICAL_PLAN" ]] || { echo "[ERRO] Plano físico ausente/duplicado." >&2; exit 2; }
            GUI_PHYSICAL_PLAN="$1"
            REAL_INSTALL=1
            ;;
        --install) REAL_INSTALL=1 ;;
        --reset-state) RESET_STATE=1 ;;
        --preset)
            shift
            [[ $# -gt 0 ]] || { echo "[ERRO] --preset exige um valor." >&2; exit 2; }
            STACK_PRESET="$1"
            ;;
        --full) STACK_PRESET="full" ;;
        --test) STACK_PRESET="test" ;;
        --minimal) STACK_PRESET="minimal" ;;
        --stacks)
            shift
            [[ $# -gt 0 ]] || { echo "[ERRO] --stacks exige uma lista." >&2; exit 2; }
            STACKS_ARG="$1"
            ;;
        --list-stacks) LIST_STACKS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Opção desconhecida: $1"; usage; exit 2 ;;
    esac
    shift
done

if [[ -n "$GUI_PHYSICAL_PLAN" ]]; then
    [[ -z "$GUI_VM_PLAN" && -z "$GUI_LAB42_PLAN" && "$VM_INSTALL" == 0 && "$REAL_INSTALL" == 1 &&
       "$DRY_RUN" == 0 && "$PLAN_ONLY" == 0 && "$RESET_STATE" == 0 &&
       -z "$STACK_PRESET" && -z "$STACKS_ARG" && "$LIST_STACKS" == 0 ]] || {
        echo "[ERRO] Executor físico não aceita opções conflitantes/override." >&2; exit 2;
    }
fi

if [[ -n "$GUI_LAB42_PLAN" ]]; then
    [[ -z "$GUI_VM_PLAN" && "$VM_INSTALL" == 1 && "$REAL_INSTALL" == 0 &&
       "$DRY_RUN" == 0 && "$PLAN_ONLY" == 0 && "$RESET_STATE" == 0 &&
       -z "$STACK_PRESET" && -z "$STACKS_ARG" && "$LIST_STACKS" == 0 ]] || {
        echo '[ERRO] Laboratório não aceita opções conflitantes ou override.' >&2; exit 2;
    }
fi

if [[ -n "$GUI_VM_PLAN" ]]; then
    # Não permitir misturar opções interativas/override com um plano validado.
    (( VM_INSTALL == 1 && REAL_INSTALL == 0 && DRY_RUN == 0 && PLAN_ONLY == 0 && RESET_STATE == 0 )) || {
        echo '[ERRO] Execução GUI não aceita modos/opções de instalação conflitantes.' >&2; exit 2;
    }
    [[ -z "$STACK_PRESET" && -z "$STACKS_ARG" && "$LIST_STACKS" == 0 ]] || {
        echo '[ERRO] Não misture preset/stacks com o plano JSON.' >&2; exit 2;
    }
fi

if (( LIST_STACKS == 1 )); then
    cat <<'EOF'
Stacks opcionais disponíveis:
  daily        Escritório, multimídia, impressão, Chrome, Flatpak, Zsh
  gaming       Steam, Discord, Lutris, Heroic, Wine/Proton, MangoHud, Gamescope
  development  Compiladores, Python, JDK, VS Code, Insomnia
  android      Android Studio/SDK + Flutter (stack grande)
  containers   Docker, Compose, Buildx, lazydocker
  extras       JDownloader, AB Download Manager, Balena Etcher, Octopi
EOF
    exit 0
fi

if [[ -n "$GUI_VM_PLAN" || -n "$GUI_LAB42_PLAN" || -n "$GUI_PHYSICAL_PLAN" ]]; then
    if mountpoint -q /mnt 2>/dev/null || [[ -s "$CHECKPOINT_FILE" ]]; then
        echo '[ERRO] Há /mnt montado ou checkpoints de outra instalação. Desmonte somente após conferir os dados; não é seguro continuar automaticamente.' >&2
        exit 2
    fi
fi
mkdir -p "$STATE_DIR" "$PROBE_DIR"

if (( RESET_STATE == 1 )); then
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR" "$PROBE_DIR"
fi

touch "$LOG_FILE" "$CHECKPOINT_FILE" "$PACKAGE_RESOLUTION_LOG"

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
    echo "Resolução de pacotes:"
    echo "  $PACKAGE_RESOLUTION_LOG"

    if mountpoint -q /mnt 2>/dev/null; then
        mkdir -p /mnt/var/log/wolf-linux 2>/dev/null || true
        cp -f "$LOG_FILE" /mnt/var/log/wolf-linux/wolf-install.log 2>/dev/null || true
        cp -f "$PACKAGE_RESOLUTION_LOG" /mnt/var/log/wolf-linux/package-resolution.log 2>/dev/null || true
        echo "Cópia persistente (se disponível):"
        echo "  /mnt/var/log/wolf-linux/"
    fi

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
        echo "              *** INSTALAÇÃO GUI ***"
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
            *VirtualBox*)
                VM_TYPE="oracle"
                ;;
            *QEMU*|*KVM*)
                VM_TYPE="qemu"
                ;;
        esac
    fi
}

is_supported_test_vm() {
    case "$VM_TYPE" in
        qemu|kvm|oracle|virtualbox|vbox)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_runtime() {
    [[ -n "${BASH_VERSION:-}" ]] || die "O instalador precisa de Bash."

    detect_virtualization
    info "Ambiente detectado: $VM_TYPE"
    if [[ -n "$GUI_VM_PLAN" ]]; then
        [[ -d /run/archiso/airootfs ]] || die 'A instalação gráfica exige iniciar pela ISO Live Wolf/Archiso.'
        # A nova GUI usa o mesmo contrato em máquina virtual ou física.
        # Não liberar outras rotas (--install/--vm-install) por este ajuste.
        if is_supported_test_vm; then
            VM_INSTALL=1; REAL_INSTALL=0
        else
            VM_INSTALL=0; REAL_INSTALL=1
        fi
    fi

    if (( VM_INSTALL == 1 && REAL_INSTALL == 1 )); then
        die "Use apenas um modo: --vm-install OU --install."
    fi

    if (( DRY_RUN == 0 && PLAN_ONLY == 0 )); then
        (( EUID == 0 )) || die "A instalação real precisa ser executada como root."

        if [[ -n "$GUI_VM_PLAN" ]]; then
            ok 'Sessão Live e plano da interface detectados; será exigida revalidação independente.'
        elif (( VM_INSTALL == 1 )); then
            if is_supported_test_vm; then
                ok "VM suportada confirmada ($VM_TYPE). Operações destrutivas liberadas para a VM."
            else
                die "--vm-install recusado: QEMU/KVM ou VirtualBox não foi detectado."
            fi

        elif (( REAL_INSTALL == 1 )); then
            if is_supported_test_vm; then
                die "--install recusado dentro de uma VM ($VM_TYPE). Use --vm-install."
            else
                warn "MODO HARDWARE REAL ATIVADO."
                warn "O instalador poderá formatar os dispositivos mostrados no plano."
            fi

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
    if [[ "$VM_TYPE" == "oracle" || "$VM_TYPE" == "virtualbox" || "$VM_TYPE" == "vbox" ]]; then
        GPU_PROFILE="virtualbox"

    elif [[ "$VM_TYPE" == "qemu" || "$VM_TYPE" == "kvm" ]] \
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

    if [[ -n "$GUI_VM_PLAN" || -n "$GUI_PHYSICAL_PLAN" ]]; then
        die 'Conecte a rede pelo NetworkManager antes de iniciar uma instalação controlada.'
    fi
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
    DESKTOP="plasma"
    ok "Desktop fixo desta baseline: KDE Plasma / Wayland"
}

list_stacks() {
    cat <<'EOF'
Stacks opcionais disponíveis:
  daily        Escritório, multimídia, impressão, Chrome, Flatpak, Zsh
  gaming       Steam, Discord, Lutris, Heroic, Wine/Proton, MangoHud, Gamescope
  development  Compiladores, Python, JDK, VS Code, Insomnia
  android      Android Studio/SDK + Flutter (stack grande)
  containers   Docker, Compose, Buildx, lazydocker
  extras       JDownloader, AB Download Manager, Balena Etcher, Octopi
EOF
}

valid_stack() {
    case "$1" in
        daily|gaming|development|android|containers|extras) return 0 ;;
        *) return 1 ;;
    esac
}

select_stack() {
    valid_stack "$1" || die "Stack desconhecida: $1"
    SELECTED_STACKS["$1"]=1
}

stack_selected() {
    [[ "${SELECTED_STACKS[$1]:-0}" == 1 ]]
}

selected_stacks_text() {
    local name out=""
    for name in daily gaming development android containers extras; do
        if stack_selected "$name"; then
            [[ -n "$out" ]] && out+=","
            out+="$name"
        fi
    done
    printf '%s\n' "${out:-nenhuma}"
}

apply_preset() {
    local preset="$1"
    case "$preset" in
        full)
            for name in daily gaming development android containers extras; do select_stack "$name"; done
            ;;
        test)
            for name in daily gaming development extras; do select_stack "$name"; done
            ;;
        minimal) ;;
        custom) return 1 ;;
        *) die "Preset inválido: $preset" ;;
    esac
    return 0
}

choose_stacks_interactive() {
    echo
    echo "Seleção de software opcional:"
    echo "  1) Full    - todas as stacks [padrão]"
    echo "  2) Test    - sem Android/Flutter e containers"
    echo "  3) Minimal - somente KDE/base"
    echo "  4) Custom  - escolher stack por stack"
    echo
    read -r -p "Perfil [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
        1) apply_preset full ;;
        2) apply_preset test ;;
        3) apply_preset minimal ;;
        4)
            local name answer
            for name in daily gaming development android containers extras; do
                read -r -p "Instalar stack '$name'? [s/N]: " answer
                [[ "$answer" =~ ^[sS]$ ]] && select_stack "$name"
            done
            ;;
        *) die "Seleção de perfil inválida." ;;
    esac
}

choose_stacks() {
    if (( LIST_STACKS == 1 )); then
        list_stacks
        exit 0
    fi

    if [[ -n "$STACKS_ARG" ]]; then
        local raw
        IFS=',' read -ra raw <<< "$STACKS_ARG"
        local name
        for name in "${raw[@]}"; do
            name="${name//[[:space:]]/}"
            [[ -n "$name" ]] && select_stack "$name"
        done
    elif [[ -n "$STACK_PRESET" ]]; then
        if ! apply_preset "$STACK_PRESET"; then
            choose_stacks_interactive
        fi
    else
        choose_stacks_interactive
    fi

    ok "Stacks selecionadas: $(selected_stacks_text)"
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
    else
        read -r -p "Disco onde instalar o GRUB BIOS (ex.: /dev/sda): " INSTALL_DISK
        [[ -n "$INSTALL_DISK" ]] || die "O disco do GRUB é obrigatório em BIOS/Legacy."
        validate_device_if_needed "$INSTALL_DISK"
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
    if [[ "$BOOT_MODE" == "BIOS" ]]; then
        read -r -p "Disco onde instalar o GRUB BIOS (ex.: /dev/sda): " INSTALL_DISK
        [[ -n "$INSTALL_DISK" ]] || die "O disco do GRUB é obrigatório em BIOS/Legacy."
        validate_device_if_needed "$INSTALL_DISK"
    fi
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
            printf '  /          %s  [EXT4 — APAGA DADOS]\n' "$ROOT_DEVICE"
            if [[ -n "$ESP_DEVICE" && "$FORMAT_ESP" == "yes" ]]; then
                printf '  /boot/efi  %s  [FAT32 — APAGA DADOS]\n' "$ESP_DEVICE"
            fi
            if [[ -n "$HOME_DEVICE" && "$FORMAT_HOME" == "yes" ]]; then
                printf '  /home      %s  [EXT4 — APAGA DADOS]\n' "$HOME_DEVICE"
            fi
            echo
            echo "SERÁ PRESERVADO:"
            if [[ -n "$ESP_DEVICE" && "$FORMAT_ESP" != "yes" ]]; then
                printf '  /boot/efi  %s  [PRESERVAR]\n' "$ESP_DEVICE"
            fi
            if [[ -n "$HOME_DEVICE" && "$FORMAT_HOME" != "yes" ]]; then
                printf '  /home      %s  [PRESERVAR]\n' "$HOME_DEVICE"
            elif [[ -z "$HOME_DEVICE" ]]; then
                echo '  /home      ficará dentro da raiz FORMATADA (sem partição dedicada)'
            fi
            if [[ -n "$HOME_DEVICE" && "$FORMAT_HOME" != "yes" ]]; then
                if [[ "$CLEAN_HOME_DOTFILES" == "yes" ]]; then
                    printf '  dotfiles   /home/%s/.* [REMOVER]\n' "$USERNAME_VALUE"
                fi
            fi
            ;;
        erase)
            echo
            echo "DISCO INTEIRO SERÁ APAGADO:"
            printf '  %s\n' "$INSTALL_DISK"
            echo
            printf 'Nova raiz ..........: %s\n' "$ROOT_DEVICE"
            [[ -n "$ESP_DEVICE" ]] && printf 'Nova ESP ...........: %s\n' "$ESP_DEVICE"
            if [[ -n "$HOME_DEVICE" ]]; then
                printf 'Nova /home ........: %s [partição ext4 FORMATADA]
' "$HOME_DEVICE"
                printf 'Tamanho /home ......: %s
' "$( (( GUI_ERASE_HOME_GIB > 0 )) && echo "${GUI_ERASE_HOME_GIB} GiB" || echo restante )"
            else
                echo "Nova /home ........: diretório DENTRO da raiz / (sem partição dedicada)"
            fi
            if [[ -n "$GUI_VM_PLAN" && "$GUI_VM_MODE" == "erase" ]]; then
                printf 'Tamanho / .........: %s
' "$( (( GUI_ERASE_ROOT_GIB > 0 )) && echo "${GUI_ERASE_ROOT_GIB} GiB" || echo restante )"
                if [[ "$BOOT_MODE" == UEFI ]]; then
                    echo 'ESP ................: 1 GiB (FAT32)'
                else
                    echo 'BIOS ...............: sem ESP / EFI; GRUB no MBR'
                fi
            fi
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
    if [[ -n "$GUI_PHYSICAL_PLAN" ]]; then
        echo "FÍSICO MULTIDISCO: EFI e LVM serão preservados. Somente / será formatada."
    fi
    if [[ -n "$GUI_PHYSICAL_PLAN" ]]; then
        echo "INSTALAÇÃO REAL DE HARDWARE, SEM BACKUP GERAL: todos os dados da raiz serão perdidos."
        echo "FORMATAR: $ROOT_DEVICE (UUID atual $PHYSICAL_ROOT_UUID)"
        echo "PRESERVAR: EFI $ESP_DEVICE e /home $HOME_DEVICE (incluindo PVs LVM)."
        read -r -p "Digite ACEITO-PERDA-RAIZ para reconhecer o risco: " answer
        [[ "$answer" == "ACEITO-PERDA-RAIZ" ]] || die "Risco não confirmado; abortado."
        read -r -p "Digite FORMATAR $ROOT_DEVICE para confirmar o dispositivo: " answer
        [[ "$answer" == "FORMATAR $ROOT_DEVICE" ]] || die "Partição raiz não confirmada; abortado."
    elif [[ -n "$GUI_LAB42_PLAN" ]]; then
        echo 'LABORATÓRIO ALPHA42 — QEMU, DOIS DISCOS VIRTUAIS WOLF41.'
        echo 'APAGAR EXCLUSIVAMENTE /dev/vdb1 (raiz ext4).'
        echo 'PRESERVAR /dev/vda1 (EFI), /dev/vdb2 (NTFS) e /home em LVM de dois PVs.'
        read -r -p 'Digite FORMATAR /dev/vdb1 para continuar: ' answer
        [[ "$answer" == 'FORMATAR /dev/vdb1' ]] || die 'Cancelado sem formatação.'
    elif [[ -n "$GUI_VM_PLAN" ]]; then
        if [[ "$GUI_VM_MODE" == "manual" ]]; then
            printf 'PARTICIONAMENTO MANUAL: partição raiz %s será FORMATADA (PERDA TOTAL DE DADOS).\n' "$ROOT_DEVICE"
            printf 'EFI %s: %s\n' "$( [[ "$FORMAT_ESP" == yes ]] && echo FORMATAR || echo PRESERVAR )" "$ESP_DEVICE"
            if [[ -n "$HOME_DEVICE" ]]; then
                printf '/home %s: %s\n' "$( [[ "$FORMAT_HOME" == yes ]] && echo FORMATAR || echo PRESERVAR )" "$HOME_DEVICE"
            else
                echo '/home: dentro da raiz / (apagada com a formatação da raiz)'
            fi
        elif [[ "$GUI_VM_MODE" == "reuse" ]]; then
            printf 'REUTILIZAR: FORMATAR apenas raiz / = %s (APAGA a instalação anterior).\n' "$ROOT_DEVICE"
            printf 'PRESERVAR EFI FAT32: %s (sem formatação).\n' "$ESP_DEVICE"
            printf 'PRESERVAR /home ext4: %s (sem formatação).\n' "$HOME_DEVICE"
            printf 'Limpeza opcional de configurações ocultas: %s\n' "$CLEAN_HOME_DOTFILES"
            echo 'Arquivos de boot WolfLinux poderão ser atualizados na EFI, sem formatá-la.'
        else
            printf 'APAGAR DISCO: %s INTEIRO será APAGADO, inclusive partições existentes.\n' "$INSTALL_DISK"
        fi
        echo 'Esta ação é irreversível. Confirme apenas se o destino acima estiver correto.'
        if (( GUI_VM_CLICK_CONFIRMED == 1 )); then
            # Confirmações gráficas e contrato validados pelo executor real.
            # O launcher usa esta flag SOMENTE após dois diálogos positivos.
            # Proteções de disco, MAJ:MIN, montagens e checkpoint seguem ativas.
            ok 'Consentimento da interface gráfica recebido; verificações independentes continuam obrigatórias.'
        else
            read -r -p "Digite APAGAR para continuar: " answer
            [[ "$answer" == "APAGAR" ]] || die 'Instalação VM cancelada.'
        fi    else
        read -r -p 'Digite INSTALAR-WOLF para continuar: ' answer
        [[ "$answer" == "INSTALAR-WOLF" ]] || die "Instalação cancelada."
    fi
}

prepare_erase_disk() {
    [[ "$STORAGE_MODE" == "erase" ]] || return 0

    # Valores são revalidados pelo contrato canônico ANTES desta etapa.
    # Na instalação CLI antiga, mantém o particionamento original (root restante).
    local root_gib=0 home_gib=0 separated=no root_end_mib home_end_mib
    if [[ -n "$GUI_VM_PLAN" && "$GUI_VM_MODE" == erase ]]; then
        root_gib="$GUI_ERASE_ROOT_GIB"
        home_gib="$GUI_ERASE_HOME_GIB"
        separated="$GUI_ERASE_SEPARATE"
    fi
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        wipefs -a "$INSTALL_DISK"
        sgdisk -Z "$INSTALL_DISK"
        sgdisk -n 1:0:+1G -t 1:ef00 "$INSTALL_DISK"
        if (( root_gib > 0 )); then
            sgdisk -n "2:0:+${root_gib}G" -t 2:8300 "$INSTALL_DISK"
        else
            sgdisk -n 2:0:0 -t 2:8300 "$INSTALL_DISK"
        fi
        if [[ "$separated" == yes ]]; then
            if (( home_gib > 0 )); then
                sgdisk -n "3:0:+${home_gib}G" -t 3:8300 "$INSTALL_DISK"
            else
                sgdisk -n 3:0:0 -t 3:8300 "$INSTALL_DISK"
            fi
        fi
    else
        wipefs -a "$INSTALL_DISK"
        parted -s "$INSTALL_DISK" mklabel msdos
        if (( root_gib > 0 )); then
            root_end_mib=$((1 + root_gib * 1024))
            parted -s "$INSTALL_DISK" unit MiB mkpart primary ext4 1 "${root_end_mib}"
        else
            parted -s "$INSTALL_DISK" mkpart primary ext4 1MiB 100%
        fi
        parted -s "$INSTALL_DISK" set 1 boot on
        if [[ "$separated" == yes ]]; then
            if (( home_gib > 0 )); then
                home_end_mib=$((root_end_mib + home_gib * 1024))
                parted -s "$INSTALL_DISK" unit MiB mkpart primary ext4 "${root_end_mib}" "${home_end_mib}"
            else
                parted -s "$INSTALL_DISK" unit MiB mkpart primary ext4 "${root_end_mib}" 100%
            fi
        fi
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

        # Na instalação manual, selecionar a EFI dispensa ajustar a flag esp
        # pelo GParted. O tipo GPT da partição escolhida é marcado como ESP.
        if [[ "$BOOT_MODE" == "UEFI" && -n "$GUI_VM_PLAN" && "$GUI_VM_MODE" == "manual" ]]; then
            local partition_number esp_typecode disk_table
            partition_number="$(lsblk -dnro PARTN "$ESP_DEVICE" | tr -d '[:space:]')"
            disk_table="$(lsblk -dnro PTTYPE "$INSTALL_DISK" | tr -d '[:space:]')"
            [[ "$partition_number" =~ ^[0-9]+$ && "$disk_table" == "gpt" ]] || die 'Não foi possível conferir partição EFI/GPT.'
            esp_typecode="$(lsblk -dnro PARTTYPE "$ESP_DEVICE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
            if [[ "$esp_typecode" != "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]; then
                warn "Ajustando tipo GPT da partição $ESP_DEVICE para EFI System (ESP), sem modificar outras partições."
                sgdisk --typecode="${partition_number}:ef00" "$INSTALL_DISK"
                partprobe "$INSTALL_DISK"
                udevadm settle
            fi
        fi

    if [[ "$FORMAT_ROOT" == "yes" ]]; then
        # Modo manual/reuso: revalidar o plano novamente imediatamente antes do mkfs.
        if [[ -n "$GUI_VM_PLAN" && "$GUI_VM_MODE" != erase ]]; then
            revalidate_gui_vm_target
        fi
        revalidate_gui_physical_target
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


# Enumera apenas DIRETÓRIOS imediatos de usuários na raiz do filesystem /home.
# Não segue links e exclui lost+found, .snapshot e nomes não compatíveis com login.
list_preserved_home_users() {
    local base="$1" path name
    while IFS= read -r -d '' path; do
        name="${path##*/}"
        [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || continue
        [[ "$name" != 'lost+found' ]] || continue
        printf '%s\0' "$path"
    done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0)
}

# A GUI apresenta os ocultos APENAS do usuário escolhido; o executor deve
# gerar a mesma seleção. O CLI anterior conserva a política de todos os usuários.
list_home_cleanup_users() {
    local base="$1" selected
    selected="$base/${USERNAME_VALUE:-}"
    if [[ -n "${GUI_VM_PLAN:-}" && "${GUI_VM_CLICK_CONFIRMED:-0}" == 1 ]]; then
        [[ "$USERNAME_VALUE" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die 'Usuário inválido na limpeza.'
        if [[ -d "$selected" && ! -L "$selected" ]]; then
            printf '%s\0' "$selected"
        fi
    else
        list_preserved_home_users "$base"
    fi
}

# ANTES de formatar /, apresenta os arquivos que serão apagados e exige
# uma segunda confirmação. Montagem temporária somente leitura, sem journal replay.
confirm_preserved_home_cleanup() {
    HOME_CLEAN_CONFIRMED="no"
    if [[ -n "${GUI_PHYSICAL_PLAN:-}" ]]; then
        [[ "$(sha256sum "$GUI_PHYSICAL_PLAN" | cut -d' ' -f1)" == "$PHYSICAL_PLAN_SHA256" ]] ||
            die 'Plano de limpeza /home mudou durante o instalador.'
        local selected mode
        read -r mode selected < <(/usr/bin/python3 - "$GUI_PHYSICAL_PLAN" <<'PYCLEAN'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: p=json.load(f)
spec=p.get('home_cleanup',{})
print('root', 1 if spec.get('enabled',False) else 0) if 'enabled' in spec else print('legacy', len(spec.get('items',[])))
PYCLEAN
) || die 'Plano de limpeza inválido.'
        [[ "$mode" == root || "$mode" == legacy ]] || die 'Modo de limpeza desconhecido.'
        [[ "$selected" =~ ^[0-9]+$ ]] || die 'Seleção inválida.'
        if (( selected > 0 )); then
            if [[ "$mode" == root ]]; then
                HOME_CLEAN_LIST_FILE="$(mktemp "$STATE_DIR/home-clean-root.XXXXXXXX")"
                chmod 600 "$HOME_CLEAN_LIST_FILE"
                /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_home_cleanup.py" check "$GUI_PHYSICAL_PLAN" "$HOME_DEVICE" "$HOME_CLEAN_LIST_FILE" ||
                    die 'Falha na prévia de /home; nenhuma formatação iniciou.'
                echo 'Atenção: TODOS os arquivos e diretórios ocultos imediatos da pasta pessoal serão excluídos.'
                echo 'Isso pode incluir Steam, .local, .ssh e perfis. Com backup=Não, a perda é definitiva.'
                local answer
                read -r -p 'Digite LIMPAR para autorizar (Enter cancela a instalação): ' answer
                [[ "$answer" == 'LIMPAR' ]] || die 'Limpeza não autorizada; nenhuma formatação iniciou.'
            else
                /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_home_cleanup.py" check "$GUI_PHYSICAL_PLAN" "$HOME_DEVICE" ||
                    die 'Falha na prévia seletiva; nenhuma formatação iniciou.'
                echo 'Atenção: exclusões seletivas de /home são irreversíveis quando backup=Não.'
                local answer
                read -r -p 'Digite LIMPAR SELECIONADOS para autorizar (Enter cancela a instalação): ' answer
                [[ "$answer" == 'LIMPAR SELECIONADOS' ]] || die 'Limpeza não autorizada; nenhuma formatação iniciou.'
            fi
            HOME_CLEAN_CONFIRMED=yes
        fi
        return 0
    fi
    [[ "$CLEAN_HOME_DOTFILES" == "yes" ]] || return 0
    [[ -n "$HOME_DEVICE" && "$FORMAT_HOME" == "no" && "$STORAGE_MODE" == "reuse-manual" ]] ||
        die 'Limpeza de home fora do modo reutilizar/preservar foi bloqueada.'
    [[ -b "$HOME_DEVICE" ]] || die 'Dispositivo /home inexistente.'
    HOME_CLEAN_LIST_FILE="$STATE_DIR/home-clean-targets.nul"
    # Diretório root-owned criado na inicialização; arquivo NÃO controlado pela GUI.
    : > "$HOME_CLEAN_LIST_FILE"
    chmod 600 "$HOME_CLEAN_LIST_FILE"
    if ! (set -Eeuo pipefail
        probe="$(mktemp -d /tmp/wolf-home-preview.XXXXXXXX)"
        trap 'if mountpoint -q "$probe" 2>/dev/null; then umount "$probe" || true; fi; rmdir "$probe" 2>/dev/null || true' EXIT
        mount -t ext4 -o ro,noload "$HOME_DEVICE" "$probe"
        echo
        echo '============================================================'
        echo '       PRÉVIA DE LIMPEZA DA /home PRESERVADA'
        echo '============================================================'
        echo "Partição: $HOME_DEVICE (NÃO será formatada)"
        echo 'Serão removidas APENAS as entradas ocultas listadas do usuário selecionado:'
        total=0
        while IFS= read -r -d '' userdir; do
            echo "Usuário: /home/${userdir##*/}"
            while IFS= read -r -d '' item; do
                printf '  REMOVER: %q\n' "${item##*/}"
                printf '%s\0' "${userdir##*/}/${item##*/}" >> "$HOME_CLEAN_LIST_FILE"
                total=$((total+1))
            done < <(find "$userdir" -mindepth 1 -maxdepth 1 -name '.*' -print0)
        done < <(list_home_cleanup_users "$probe")
        echo "Total de entradas ocultas: $total"
        echo 'Diretórios/arquivos VISÍVEIS são preservados.'
        echo 'ATENÇÃO: .ssh, .gnupg, .mozilla, .local e outros dados privados'
        echo 'também SERÃO APAGADOS se aparecerem acima. Faça backup antes!'
        echo '============================================================'
        sort -z "$HOME_CLEAN_LIST_FILE" -o "$HOME_CLEAN_LIST_FILE"
        if (( GUI_VM_CLICK_CONFIRMED == 1 )); then
            # Consentimento GUI já incluiu a remoção dos dotfiles nas DUAS janelas.
            # A lista real é revalidada antes da exclusão; a GUI não bypassa essa proteção.
            echo '[OK] Limpeza /home autorizada nas duas confirmações da interface.'
        else
            printf 'Digite LIMPAR para remover os itens listados (ou Enter para cancelar): '
            read -r answer
            [[ "$answer" == 'LIMPAR' ]] || { echo '[AVISO] Limpeza NÃO autorizada; instalação cancelada ANTES de formatar /.'; exit 3; }
        fi
        umount "$probe" || { echo '[ERRO] Não foi possível desmontar o volume de prévia; instalação cancelada.'; exit 4; }
    ); then
        die 'Limpeza de /home não autorizada ou falha na prévia: NENHUMA formatação foi iniciada.'
    fi
    HOME_CLEAN_CONFIRMED="yes"
    ok 'Limpeza de arquivos ocultos explicitamente confirmada antes da formatação da raiz.'
}

clean_preserved_home_dotfiles() {
    if [[ -n "${GUI_PHYSICAL_PLAN:-}" ]]; then
        [[ "$(sha256sum "$GUI_PHYSICAL_PLAN" | cut -d' ' -f1)" == "$PHYSICAL_PLAN_SHA256" ]] ||
            die 'Plano físico mudou antes da limpeza de /home.'
        local selected mode
        read -r mode selected < <(/usr/bin/python3 - "$GUI_PHYSICAL_PLAN" <<'PYCLEAN'
import json,sys
with open(sys.argv[1],encoding='utf-8') as f: p=json.load(f)
spec=p.get('home_cleanup',{})
print('root', 1 if spec.get('enabled',False) else 0) if 'enabled' in spec else print('legacy', len(spec.get('items',[])))
PYCLEAN
) || die 'Seleção de limpeza ilegível.'
        [[ "$mode" == root || "$mode" == legacy ]] || die 'Modo de limpeza desconhecido.'
        [[ "$selected" =~ ^[0-9]+$ ]] || die 'Seleção inválida.'
        if (( selected > 0 )); then
            [[ "$HOME_CLEAN_CONFIRMED" == yes ]] || die 'Faltou consentimento para limpeza física.'
            if [[ "$mode" == root ]]; then
                [[ -n "${HOME_CLEAN_LIST_FILE:-}" && -f "$HOME_CLEAN_LIST_FILE" && ! -L "$HOME_CLEAN_LIST_FILE" ]] ||
                    die 'Manifesto da prévia não encontrado; limpeza recusada.'
                /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_home_cleanup.py" apply "$GUI_PHYSICAL_PLAN" /mnt/home "$HOME_DEVICE" "$HOME_CLEAN_LIST_FILE" ||
                    die 'Limpeza integral de dotfiles recusada/abortada.'
            else
                /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_home_cleanup.py" apply "$GUI_PHYSICAL_PLAN" /mnt/home "$HOME_DEVICE" ||
                    die 'Limpeza física recusada/abortada.'
            fi
        else
            info 'Limpeza desmarcada: /home será preservada integralmente.'
        fi
        return 0
    fi
    [[ "$CLEAN_HOME_DOTFILES" == "yes" ]] || {
        info 'Limpeza de dotfiles não solicitada; /home preservada integralmente.'
        return 0
    }
    [[ "$HOME_CLEAN_CONFIRMED" == "yes" ]] || die 'Limpeza de /home sem confirmação LIMPAR foi bloqueada.'
    [[ "$STORAGE_MODE" == "reuse-manual" && "$FORMAT_HOME" == "no" && -b "$HOME_DEVICE" ]] ||
        die 'Condições de preservação de /home inválidas; limpeza recusada.'
    mountpoint -q /mnt/home || die '/mnt/home não está montado; limpeza recusada.'
    local source expected actual userdir item mp
    source="$(findmnt -rn -o SOURCE --mountpoint /mnt/home 2>/dev/null || true)"
    expected="$(readlink -f -- "$HOME_DEVICE")"
    actual="$(readlink -f -- "$source" 2>/dev/null || true)"
    [[ -n "$actual" && "$actual" == "$expected" ]] || die 'A fonte montada em /mnt/home não corresponde à partição preservada.'
    # Não excluir árvores com submontagens; nunca forçar desmontagem/exclusão.
    [[ -n "$HOME_CLEAN_LIST_FILE" && -f "$HOME_CLEAN_LIST_FILE" && ! -L "$HOME_CLEAN_LIST_FILE" ]] ||
        die 'Lista da prévia de limpeza não encontrada; abortado.'
    local current
    current="$(mktemp "$STATE_DIR/home-clean-current.XXXXXXXX")"
    chmod 600 "$current"
    local -a targets=()
    while IFS= read -r -d '' userdir; do
        while IFS= read -r -d '' item; do
            printf '%s\0' "${userdir##*/}/${item##*/}" >> "$current"
        done < <(find "$userdir" -mindepth 1 -maxdepth 1 -name '.*' -print0)
    done < <(list_home_cleanup_users /mnt/home)
    sort -z "$current" -o "$current"
    if ! cmp -s "$current" "$HOME_CLEAN_LIST_FILE"; then
        rm -f -- "$current"
        die 'Conteúdo oculto de /home mudou após a confirmação; limpeza cancelada, sem apagar novas entradas.'
    fi
    rm -f -- "$current"
    local relative user file item
    while IFS= read -r -d '' relative; do
        user="${relative%%/*}"
        file="${relative#*/}"
        [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$file" == .* && "$file" != '.' && "$file" != '..' && "$file" != */* ]] ||
            die 'Caminho inválido na lista de dotfiles; abortado.'
        [[ -d "/mnt/home/$user" && ! -L "/mnt/home/$user" ]] ||
            die 'Diretório de usuário inesperado/symlink na limpeza.'
        item="/mnt/home/$user/$file"
        [[ -e "$item" || -L "$item" ]] || die 'Arquivo oculto desapareceu após a prévia.'
        while IFS= read -r mp; do
            if [[ "$mp" == "$item" || "$mp" == "$item/"* ]]; then
                die "Existe montagem sob entrada oculta $item; limpeza recusada."
            fi
        done < <(findmnt -rn -o TARGET)
        targets+=("$item")
    done < "$HOME_CLEAN_LIST_FILE"
    if ((${#targets[@]} == 0)); then
        ok 'Nenhum dotfile existente para limpar.'
        return 0
    fi
    info "Removendo ${#targets[@]} entradas ocultas previamente autorizadas de /home preservada."
    # Operação única com caminhos extraídos diretamente de /mnt/home, sem glob '*'.
    rm -rf -- "${targets[@]}"
    ok 'Entradas ocultas removidas; partição /home e arquivos visíveis preservados.'
}

packages_for_desktop() {
    printf '%s
' "${KDE_PACKAGES[@]}" "${KDE_PORTAL_PACKAGES[@]}"
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
    local -a desktop_packages cpu_packages packages vm_packages=()
    mapfile -t desktop_packages < <(packages_for_desktop)

    case "$CPU_VENDOR" in
        AMD) cpu_packages=("${AMD_CPU_PACKAGES[@]}") ;;
        Intel) cpu_packages=("${INTEL_CPU_PACKAGES[@]}") ;;
        *) cpu_packages=() ;;
    esac

    case "$VM_TYPE" in
        oracle|virtualbox|vbox) vm_packages=("${VIRTUALBOX_GUEST_PACKAGES[@]}") ;;
    esac

    packages=(
        "${BASE_PACKAGES[@]}"
        "${cpu_packages[@]}"
        "${vm_packages[@]}"
        "${DISPLAY_MANAGER_PACKAGES[@]}"
        "${AUDIO_PACKAGES[@]}"
        "${BLUETOOTH_PACKAGES[@]}"
        "${FONT_PACKAGES[@]}"
        "${THEME_PACKAGES[@]}"
        "${desktop_packages[@]}"
    )
    printf '%s
' "${packages[@]}"
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
    local console_keymap=br-abnt2
    case "$XKB_LAYOUT" in
        br) console_keymap=br-abnt2 ;;
        us) console_keymap=us ;;
        pt) console_keymap=pt-latin1 ;;
        es) console_keymap=es ;;
        fr) console_keymap=fr ;;
        de) console_keymap=de ;;
        it) console_keymap=it ;;
        *) die 'Layout de teclado não suportado para o sistema instalado.' ;;
    esac
    printf 'KEYMAP=%s\nFONT=ter-v16n\n' "$console_keymap" > /mnt/etc/vconsole.conf

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
PRETTY_NAME="Wolf Linux 2.0"
VERSION="2.0"
VERSION_ID="2.0.0"
LOGO="wolf-linux"
VENDOR_NAME="Wolf Linux"
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

    # GRUB 2.16 adiciona o gerador 31_efi_bootnext, que pode transformar
    # entradas UEFI/NVRAM (inclusive pendrives) em itens persistentes do menu.
    # O Wolf Linux mantém Windows via os-prober, mas oculta o ruído BootNext.
    if grep -q '^GRUB_DISABLE_BOOTNEXT=' /mnt/etc/default/grub; then
        sed -i 's/^GRUB_DISABLE_BOOTNEXT=.*/GRUB_DISABLE_BOOTNEXT=true/' \
            /mnt/etc/default/grub
    else
        printf 'GRUB_DISABLE_BOOTNEXT=true\n' >> /mnt/etc/default/grub
    fi

    grep -q '^PRETTY_NAME="Wolf Linux 2.0"$' /mnt/etc/os-release ||
        die "Falha ao gravar identidade Wolf Linux em /etc/os-release."

    ok "Sistema identificado como Wolf Linux (compatibilidade ID=arch)."
}

# Na reutilização de /home, preferir UID histórico (se disponível), sem
# alterar a propriedade de arquivos preservados. A verificação é somente
# leitura e rejeita conflito com outra conta da nova instalação.
preflight_preserved_home_identity() {
    PRESERVED_HOME_MODE="new"
    PRESERVED_HOME_UID=""
    PRESERVED_HOME_GID=""
    PRESERVED_HOME_DESIRED_UID=""
    [[ "$STORAGE_MODE" == "reuse-manual" && -n "$HOME_DEVICE" && "$FORMAT_HOME" == "no" ]] || return 0
    mountpoint -q /mnt/home || die 'Home preservada não está montada em /mnt/home.'
    local helper="$PROJECT_DIR/live-gui/wolf_home_identity.py" temp
    [[ -f "$helper" ]] || die 'Preflight de UID/GID da home ausente.'
    temp="$(mktemp /tmp/wolf-home-identity.XXXXXXXX)"
    chmod 600 "$temp"
    if ! /usr/bin/python3 "$helper" inspect --root /mnt --user "$USERNAME_VALUE" > "$temp"; then
        rm -f -- "$temp"
        die 'Identidade numérica da home preservada é incompatível; recusado sem chown recursivo.'
    fi
    local -a f=()
    mapfile -d '' -t f < "$temp"
    rm -f -- "$temp"
    (( ${#f[@]} == 4 )) || die 'Dados incompletos no preflight da home.'
    PRESERVED_HOME_MODE="${f[0]}"
    PRESERVED_HOME_UID="${f[1]}"
    PRESERVED_HOME_GID="${f[2]}"
    PRESERVED_HOME_DESIRED_UID="${f[3]}"
    info "Home preservada: ${PRESERVED_HOME_MODE}; UID anterior=${PRESERVED_HOME_UID:-inexistente}; GID anterior=${PRESERVED_HOME_GID:-inexistente}."
}

# Corrige SOMENTE o diretório pessoal, com confirmação explícita quando
# necessário. Nunca executar chown -R, chmod -R ou alterar outros usuários.
reconcile_preserved_home_access() {
    [[ "$STORAGE_MODE" == "reuse-manual" && -n "$HOME_DEVICE" && "$FORMAT_HOME" == "no" ]] || return 0
    local dir="/mnt/home/$USERNAME_VALUE" uid old_uid response
    mountpoint -q /mnt/home || die 'Home deixou de estar montada.'
    [[ -d "$dir" && ! -L "$dir" ]] || die 'Home não é diretório regular: ajuste manual necessário.'
    uid="$(arch-chroot /mnt id -u "$USERNAME_VALUE")"
    old_uid="$(stat -c %u -- "$dir")"
    if [[ "$old_uid" != "$uid" ]]; then
        warn "Dono anterior /home/$USERNAME_VALUE: UID $old_uid; usuário recém-criado: UID $uid."
        warn 'Somente o diretório pessoal terá o dono ajustado. Arquivos internos não serão alterados.'
        printf 'Digite AJUSTAR /home/%s para corrigir somente esse diretório: ' "$USERNAME_VALUE"
        read -r response
        [[ "$response" == "AJUSTAR /home/$USERNAME_VALUE" ]] ||
            die 'Correção de propriedade recusada; não alterar a home preservada.'
        [[ -d "$dir" && ! -L "$dir" && "$(stat -c %u -- "$dir")" == "$old_uid" ]] ||
            die 'Home mudou antes da correção; abortado.'
        chown --no-dereference "$uid" "$dir"
    fi
    # Comprova escrita como usuário final, sem depender de permissões do root.
    # shellcheck disable=SC2016 # Expansão intencional dentro do /bin/sh chamado no chroot.
    if ! arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- /bin/sh -c '
        set -eu
        dir="$1"
        test -w "$dir" && test -x "$dir" || exit 1
        probe="$(mktemp "$dir/.wolf-access-test.XXXXXXXX")" || exit 1
        rm -f -- "$probe"
    ' _ "/home/$USERNAME_VALUE"; then
        die "Home /home/$USERNAME_VALUE sem permissão de escrita. Verifique ACL/permissões; nenhuma alteração recursiva foi efetuada."
    fi
    ok "Acesso de escrita confirmado para /home/$USERNAME_VALUE, preservando arquivos dos usuários."
}

configure_user_sudo() {
    local user_shell="/bin/bash"
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
    preflight_preserved_home_identity

    if arch-chroot /mnt id -u "$USERNAME_VALUE" >/dev/null 2>&1; then
        info "Usuário '$USERNAME_VALUE' já existe; ajustando shell e grupos."
        arch-chroot /mnt usermod -s "$user_shell" "$USERNAME_VALUE"

        if [[ -n "$group_csv" ]]; then
            arch-chroot /mnt usermod -aG "$group_csv" "$USERNAME_VALUE"
        fi
    else
        info "Criando usuário '$USERNAME_VALUE'."

        local -a create_args=(-m -s "$user_shell")
        [[ -z "$group_csv" ]] || create_args+=(-G "$group_csv")
        if [[ "$PRESERVED_HOME_MODE" == "reuse-uid" ]]; then
            # Evita perder acesso aos arquivos que já pertencem ao UID antigo.
            create_args+=(-u "$PRESERVED_HOME_DESIRED_UID")
            info "Reutilizando UID numérico $PRESERVED_HOME_DESIRED_UID para arquivos da /home preservada."
        fi
        arch-chroot /mnt useradd "${create_args[@]}" "$USERNAME_VALUE"
    fi

    reconcile_preserved_home_access

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
            vboxservice.service)
                arch-chroot /mnt pacman -Q virtualbox-guest-utils 2>/dev/null || true
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
    local -a services=(NetworkManager.service bluetooth.service sddm.service)
    stack_selected daily && services+=(cups.service)
    stack_selected containers && services+=(docker.service)

    if is_supported_test_vm; then
        services+=(sshd.service)
        info "VM detectada ($VM_TYPE): sshd será habilitado para testes."
    fi
    case "$VM_TYPE" in
        oracle|virtualbox|vbox) services+=(vboxservice.service) ;;
    esac

    local unit
    for unit in "${services[@]}"; do enable_one_service "$unit"; done

    echo
    echo "Serviços habilitados:"
    for unit in "${services[@]}"; do
        printf '  %-28s %s
' "$unit" "$(systemctl --root=/mnt is-enabled "$unit" 2>/dev/null || echo desconhecido)"
    done
}

configure_multilib() {
    enable_multilib_in_file /mnt/etc/pacman.conf
    arch-chroot /mnt pacman -Syy --noconfirm
}

complete_base_packages() {
    local -a packages
    mapfile -t packages < <(collect_base_packages)
    info "Conferindo/completando perfil KDE/base..."
    arch-chroot /mnt pacman -S --needed --noconfirm "${packages[@]}"

    local -a expected_units=(
        /mnt/usr/lib/systemd/system/NetworkManager.service
        /mnt/usr/lib/systemd/system/bluetooth.service
        /mnt/usr/lib/systemd/system/sddm.service
    )
    local unit_path
    for unit_path in "${expected_units[@]}"; do
        [[ -e "$unit_path" ]] || die "Unit esperada ausente: $unit_path"
    done
    ok "Perfil KDE/base completo."
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

collect_selected_official_packages() {
    stack_selected daily && printf '%s
' "${DAILY_PACKAGES[@]}"
    stack_selected gaming && printf '%s
' "${GAMING_PACKAGES[@]}"
    stack_selected development && printf '%s
' "${DEVELOPMENT_PACKAGES[@]}"
    stack_selected android && printf '%s
' "${ANDROID_PACKAGES[@]}"
    stack_selected containers && printf '%s
' "${CONTAINER_PACKAGES[@]}"
    stack_selected extras && printf '%s
' "${EXTRA_PACKAGES[@]}"
}

install_official_personal_apps() {
    local -a packages
    mapfile -t packages < <(collect_selected_official_packages)
    ((${#packages[@]} > 0)) || return 0
    info "Instalando pacotes oficiais das stacks selecionadas..."
    arch-chroot /mnt pacman -S --needed --noconfirm "${packages[@]}"

    if stack_selected android && arch-chroot /mnt getent group adbusers >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG adbusers "$USERNAME_VALUE"
    fi
    if stack_selected development && arch-chroot /mnt getent group kvm >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG kvm "$USERNAME_VALUE"
    fi
    if stack_selected containers && arch-chroot /mnt getent group docker >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG docker "$USERNAME_VALUE"
    fi
    if stack_selected daily && [[ -x /mnt/usr/bin/zsh ]]; then
        arch-chroot /mnt usermod -s /bin/zsh "$USERNAME_VALUE"
        ok "Zsh definido como shell do usuário pela stack daily."
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
    stack_selected daily && printf '%s
' "${DAILY_THIRD_PARTY_PACKAGES[@]}"
    stack_selected gaming && printf '%s
' "${GAMING_THIRD_PARTY_PACKAGES[@]}"
    stack_selected development && printf '%s
' "${DEVELOPMENT_THIRD_PARTY_PACKAGES[@]}"
    stack_selected android && printf '%s
' "${ANDROID_THIRD_PARTY_PACKAGES[@]}"
    stack_selected containers && printf '%s
' "${CONTAINER_THIRD_PARTY_PACKAGES[@]}"
    stack_selected extras && printf '%s
' "${EXTRA_THIRD_PARTY_PACKAGES[@]}"
}

install_third_party_apps() {
    local -a requested
    local -a repo_packages=()
    local -a aur_packages=()
    local pkg

    mapfile -t requested < <(collect_third_party_packages)
    local -a nonempty=()
    for pkg in "${requested[@]}"; do
        [[ -n "${pkg//[[:space:]]/}" ]] && nonempty+=("$pkg")
    done
    requested=("${nonempty[@]}")

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


collect_selected_stack_packages() {
    stack_selected daily && printf '%s\n' "${DAILY_PACKAGES[@]}" "${DAILY_THIRD_PARTY_PACKAGES[@]}"
    stack_selected gaming && printf '%s\n' "${GAMING_PACKAGES[@]}" "${GAMING_THIRD_PARTY_PACKAGES[@]}"
    stack_selected development && printf '%s\n' "${DEVELOPMENT_PACKAGES[@]}" "${DEVELOPMENT_THIRD_PARTY_PACKAGES[@]}"
    stack_selected android && printf '%s\n' "${ANDROID_PACKAGES[@]}" "${ANDROID_THIRD_PARTY_PACKAGES[@]}"
    stack_selected containers && printf '%s\n' "${CONTAINER_PACKAGES[@]}" "${CONTAINER_THIRD_PARTY_PACKAGES[@]}"
    stack_selected extras && printf '%s\n' "${EXTRA_PACKAGES[@]}" "${EXTRA_THIRD_PARTY_PACKAGES[@]}"
}

package_repository() {
    local pkg="$1"
    arch-chroot /mnt env LC_ALL=C pacman -Si "$pkg" 2>/dev/null \
        | sed -n 's/^Repository[[:space:]]*:[[:space:]]*//p' \
        | head -n1
}

record_package_resolution() {
    local pkg="$1" source="$2"
    printf '%s\t%s\n' "$pkg" "$source" | tee -a "$PACKAGE_RESOLUTION_LOG" >/dev/null
}

install_selected_stack_packages() {
    local -a requested=()
    local -a repo_packages=()
    local -a aur_packages=()
    local -A seen=()
    local pkg repo decision
    local -A optional_skipped=()

    : > "$PACKAGE_RESOLUTION_LOG"

    while IFS= read -r pkg; do
        [[ -n "${pkg//[[:space:]]/}" ]] || continue
        [[ -z "${seen[$pkg]:-}" ]] || continue
        seen["$pkg"]=1
        requested+=("$pkg")
    done < <(collect_selected_stack_packages)

    ((${#requested[@]} > 0)) || {
        ok "Nenhum pacote opcional solicitado pelas stacks."
        return 0
    }

    echo
    echo "Resolvendo pacotes das stacks selecionadas:"
    echo "  prioridade: Arch oficial -> Chaotic-AUR -> AUR fallback"
    echo

    for pkg in "${requested[@]}"; do
        if arch-chroot /mnt pacman -Q "$pkg" >/dev/null 2>&1; then
            printf '  [instalado] %-36s\n' "$pkg"
            record_package_resolution "$pkg" "installed"
            continue
        fi

        repo="$(package_repository "$pkg" || true)"
        if [[ -n "$repo" ]]; then
            printf '  [%-11s] %s\n' "$repo" "$pkg"
            record_package_resolution "$pkg" "$repo"
            repo_packages+=("$pkg")
        else
            printf '  [AUR fallback] %s\n' "$pkg"
            record_package_resolution "$pkg" "AUR"
            aur_packages+=("$pkg")
        fi
    done

    echo
    info "Mapa de resolução salvo em: $PACKAGE_RESOLUTION_LOG"

    if ((${#repo_packages[@]} > 0)); then
        echo
        info "Instalando pacotes resolvidos por pacman (Arch/Chaotic), um por vez para diagnóstico preciso..."
        local i=0 total="${#repo_packages[@]}"
        for pkg in "${repo_packages[@]}"; do
            ((i+=1))
            repo="$(package_repository "$pkg" || true)"
            info "[$i/$total] $pkg (${repo:-repositório configurado})"
            while true; do
                if arch-chroot /mnt pacman -S --needed --noconfirm "$pkg"; then
                    break
                fi
                if [[ "${repo,,}" != chaotic-aur* ]]; then
                    die "Falha ao instalar '$pkg' via pacman (${repo:-origem desconhecida}). Consulte $PACKAGE_RESOLUTION_LOG."
                fi
                warn "Pacote opcional do Chaotic-AUR '$pkg' não pôde ser instalado."
                echo '[1] Tentar novamente  [2] Pular este pacote e continuar'
                read -r -p 'Escolha 1 ou 2: ' decision || decision=2
                case "$decision" in
                    1) continue ;;
                    2)
                        optional_skipped["$pkg"]=1
                        printf 'Pacote Chaotic-AUR pendente: %s\n' "$pkg" >> "$STATE_DIR/optional-failures.log"
                        mkdir -p /mnt/var/log
                        cp "$STATE_DIR/optional-failures.log" /mnt/var/log/wolf-optional-failures.log || true
                        warn "'$pkg' ficou pendente; continuando instalação."
                        break ;;
                    *) echo 'Escolha inválida.' ;;
                esac
            done
        done
    fi

    if ((${#aur_packages[@]} > 0)); then
        echo
        warn "Pacotes não encontrados nos repositórios configurados; usando AUR direto apenas como fallback:"
        printf '  - %s\n' "${aur_packages[@]}"

        ensure_yay

        cat > "$AUR_TEMP_SUDOERS" <<EOF
$USERNAME_VALUE ALL=(root) NOPASSWD: /usr/bin/pacman
EOF
        chmod 440 "$AUR_TEMP_SUDOERS"
        arch-chroot /mnt visudo -cf /etc/sudoers.d/90-wolf-aur-temporary

        local j=0 aur_total="${#aur_packages[@]}"
        for pkg in "${aur_packages[@]}"; do
            ((j+=1))
            info "[AUR $j/$aur_total] $pkg"
            while true; do
                if arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- \
                    env \
                    HOME="/home/$USERNAME_VALUE" \
                    XDG_CACHE_HOME="/home/$USERNAME_VALUE/.cache" \
                    yay -S \
                        --aur \
                        --needed \
                        --noconfirm \
                        --answerclean None \
                        --answerdiff None \
                        "$pkg"; then
                    break
                fi
                warn "Não foi possível instalar o pacote opcional AUR '$pkg'."
                echo '[1] Tentar novamente  [2] Pular este pacote e continuar'
                read -r -p 'Escolha 1 ou 2: ' decision || decision=2
                case "$decision" in
                    1) continue ;;
                    2)
                        optional_skipped["$pkg"]=1
                        printf 'Pacote AUR pendente: %s\n' "$pkg" >> "$STATE_DIR/optional-failures.log"
                        mkdir -p /mnt/var/log
                        cp "$STATE_DIR/optional-failures.log" /mnt/var/log/wolf-optional-failures.log || true
                        warn "'$pkg' ficou pendente. A instalação do sistema continuará."
                        break ;;
                    *) echo 'Escolha inválida.' ;;
                esac
            done
        done

        rm -f "$AUR_TEMP_SUDOERS"
    else
        ok "Nenhum fallback AUR direto foi necessário."
    fi

    local validation_failed=0
    for pkg in "${requested[@]}"; do
        if arch-chroot /mnt pacman -Q "$pkg" >/dev/null 2>&1; then
            ok "$pkg instalado."
        elif [[ "${optional_skipped[$pkg]:-0}" == 1 ]]; then
            warn "'$pkg' não foi instalado por escolha do usuário. Registrado como pendência opcional."
        else
            warn "$pkg não aparece no banco local do pacman após a instalação."
            validation_failed=1
        fi
    done

    (( validation_failed == 0 )) ||
        die "Um ou mais pacotes das stacks não foram confirmados após a instalação."

    if stack_selected android && arch-chroot /mnt getent group adbusers >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG adbusers "$USERNAME_VALUE"
    fi
    if stack_selected development && arch-chroot /mnt getent group kvm >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG kvm "$USERNAME_VALUE"
    fi
    if stack_selected containers && arch-chroot /mnt getent group docker >/dev/null 2>&1; then
        arch-chroot /mnt usermod -aG docker "$USERNAME_VALUE"
    fi
    if stack_selected daily && [[ -x /mnt/usr/bin/zsh ]]; then
        arch-chroot /mnt usermod -s /bin/zsh "$USERNAME_VALUE"
        ok "Zsh definido como shell do usuário pela stack daily."
    fi
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
    stack_selected android || { info "Stack android não selecionada; Flutter/Android SDK ignorados."; return 0; }
    local flutter_dir="/mnt/opt/flutter"
    local target_flutter="/opt/flutter"
    local user_home="/home/$USERNAME_VALUE"
    local android_cli_archive="commandlinetools-linux-15859902_latest.zip"
    local android_cli_sha256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
    local android_cli_url="https://dl.google.com/android/repository/${android_cli_archive}"

    info "Instalando Android Command-line Tools 22.0 compatíveis com Flutter 3.47..."

    # Flutter 3.47.x ainda consulta o fluxo legado sdkmanager --licenses.
    # Command-line Tools 23+ substituiu esse fluxo pela nova Android CLI e
    # faz o doctor reportar licenças como desconhecidas/não aceitas.
    # Pinamos 22.0 temporariamente: é compatível com API 37 e com o checker
    # atual do Flutter. O arquivo vem diretamente do Google e é validado
    # pelo SHA-256 publicado oficialmente.
    arch-chroot /mnt /bin/bash -s -- "$android_cli_url" "$android_cli_archive" "$android_cli_sha256" <<'ANDROIDCLI'
set -Eeuo pipefail
url="$1"
archive="$2"
sha="$3"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl --fail --location "$url" --output "$tmpdir/$archive"
printf '%s  %s\n' "$sha" "$tmpdir/$archive" | sha256sum --check -
unzip -q "$tmpdir/$archive" -d "$tmpdir"

rm -rf /opt/android-sdk/cmdline-tools/22.0 /opt/android-sdk/cmdline-tools/latest
mkdir -p /opt/android-sdk/cmdline-tools
mv "$tmpdir/cmdline-tools" /opt/android-sdk/cmdline-tools/22.0
ln -s 22.0 /opt/android-sdk/cmdline-tools/latest

grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*22\.0$' \
    /opt/android-sdk/cmdline-tools/22.0/source.properties
ANDROIDCLI

    info "Configurando permissões compartilhadas do Android SDK..."

    # /opt/android-sdk é mantido pelo root/pacman, mas ferramentas como
    # `flutter doctor --android-licenses` precisam gravar em licenses/ e
    # outros subdiretórios. Em vez de transferir o SDK inteiro ao usuário,
    # o Wolf Linux usa um grupo dedicado + ACLs. Isso funciona para qualquer
    # nome de usuário escolhido durante a instalação.
    arch-chroot /mnt groupadd -f android-sdk
    arch-chroot /mnt usermod -aG android-sdk "$USERNAME_VALUE"

    cat > /mnt/usr/local/sbin/wolf-fix-android-sdk-permissions <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SDK_ROOT=/opt/android-sdk
SDK_GROUP=android-sdk

getent group "$SDK_GROUP" >/dev/null 2>&1 || groupadd -f "$SDK_GROUP"
[[ -d "$SDK_ROOT" ]] || exit 0

# Acesso aos arquivos/diretórios já existentes.
setfacl -R -m "g:${SDK_GROUP}:rwX" "$SDK_ROOT"

# ACL padrão em todos os diretórios existentes para que novos componentes,
# plataformas, licenças e caches continuem graváveis pelo grupo.
find "$SDK_ROOT" -type d -exec setfacl -m "d:g:${SDK_GROUP}:rwx" {} +
EOF
    chmod 755 /mnt/usr/local/sbin/wolf-fix-android-sdk-permissions

    mkdir -p /mnt/etc/pacman.d/hooks
    cat > /mnt/etc/pacman.d/hooks/wolf-android-sdk-permissions.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = android-sdk
Target = android-sdk-build-tools
Target = android-sdk-platform-tools
Target = android-platform

[Action]
Description = Wolf Linux: reaplicando permissoes compartilhadas do Android SDK...
When = PostTransaction
Exec = /usr/local/sbin/wolf-fix-android-sdk-permissions
EOF

    arch-chroot /mnt /usr/local/sbin/wolf-fix-android-sdk-permissions
    ok "Android SDK configurado para o grupo android-sdk com ACL persistente."

    info "Instalando Flutter SDK stable em /opt/flutter..."

    if [[ -d "$flutter_dir/.git" ]]; then
        timeout 900s arch-chroot /mnt git -C "$target_flutter" fetch --depth=1 origin stable
        arch-chroot /mnt git -C "$target_flutter" reset --hard origin/stable
    else
        rm -rf "$flutter_dir"
        timeout 900s arch-chroot /mnt git clone \
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
export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:$PATH"
EOF
    chmod 644 /mnt/etc/profile.d/wolf-development.sh

    # Flutter no Linux procura por `google-chrome`. O pacote google-chrome
    # do Arch/AUR fornece `google-chrome-stable`, então expomos um alias
    # global sem tocar em arquivos pertencentes ao pacote.
    mkdir -p /mnt/usr/local/bin
    if [[ -x /mnt/usr/bin/google-chrome-stable ]]; then
        ln -sfn /usr/bin/google-chrome-stable /mnt/usr/local/bin/google-chrome
        ok "Compatibilidade Flutter Web: google-chrome -> google-chrome-stable."
    else
        warn "google-chrome-stable não encontrado; Flutter Web poderá reclamar do Chrome."
    fi

    # O metapacote android-sdk não instala uma SDK Platform. Sem ao menos
    # uma plataforma, Flutter encontra /opt/android-sdk mas considera o SDK
    # inválido. `android-platform` deve ter criado platforms/android-XX.
    if compgen -G '/mnt/opt/android-sdk/platforms/android-*' >/dev/null; then
        ok "Android SDK Platform encontrada em /opt/android-sdk/platforms."
    else
        die "Nenhuma Android SDK Platform encontrada. Verifique o pacote android-platform."
    fi

    # Primeira execução baixa o Dart SDK/cache necessário. Fazemos isso já
    # como o usuário que será dono do SDK para evitar arquivos root-owned.
    timeout 900s arch-chroot /mnt runuser -u "$USERNAME_VALUE" -- \
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
export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
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
echo "Android SDK Platforms:"
if compgen -G '/opt/android-sdk/platforms/android-*' >/dev/null; then
    find /opt/android-sdk/platforms -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort
else
    echo "  [ERRO] nenhuma plataforma Android instalada."
fi
echo
echo "Android Command-line Tools:"
if [[ -f /opt/android-sdk/cmdline-tools/latest/source.properties ]]; then
    grep '^Pkg.Revision' /opt/android-sdk/cmdline-tools/latest/source.properties || true
else
    echo "  [ERRO] cmdline-tools/latest ausente."
fi
echo
echo "ADB:"
mapfile -t adb_bins < <(type -aP adb 2>/dev/null | awk '!seen[$0]++')
if (( ${#adb_bins[@]} == 1 )); then
    echo "  [OK] ${adb_bins[0]}"
elif (( ${#adb_bins[@]} == 0 )); then
    echo "  [ERRO] adb não encontrado."
else
    printf '  [AVISO] múltiplos adb no PATH:\n'
    printf '    %s\n' "${adb_bins[@]}"
fi
echo
echo "Chrome para Flutter Web:"
if command -v google-chrome >/dev/null 2>&1; then
    echo "  $(command -v google-chrome)"
else
    echo "  [ERRO] google-chrome não encontrado."
fi
echo
echo "Permissões do Android SDK:"
if id -nG "$USER" | tr ' ' '\n' | grep -Fxq android-sdk; then
    echo "  [OK] usuário pertence ao grupo android-sdk."
else
    echo "  [AVISO] sessão ainda não possui o grupo android-sdk; faça logout/login."
fi
if [[ -w /opt/android-sdk ]]; then
    echo "  [OK] /opt/android-sdk gravável sem sudo."
else
    echo "  [ERRO] /opt/android-sdk não está gravável nesta sessão."
fi
echo
echo "Flutter:"
flutter doctor -v
echo
echo "Para revisar/aceitar as licenças Android:"
echo "  wolf-android-licenses"
EOF
    chmod 755 /mnt/usr/local/bin/wolf-flutter-doctor

    cat > /mnt/usr/local/bin/wolf-android-licenses <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:$PATH"

if (( EUID == 0 )); then
    echo "[ERRO] Não execute as licenças Android com sudo/root." >&2
    echo "       O Wolf Linux configura /opt/android-sdk para o grupo android-sdk." >&2
    exit 1
fi

if ! id -nG "$USER" | tr ' ' '\n' | grep -Fxq android-sdk; then
    echo "[ERRO] Sua sessão ainda não possui o grupo android-sdk." >&2
    echo "       Faça logout/login e tente novamente." >&2
    exit 1
fi

if [[ ! -w /opt/android-sdk ]]; then
    echo "[ERRO] /opt/android-sdk não está gravável nesta sessão." >&2
    echo "       Rode: sudo /usr/local/sbin/wolf-fix-android-sdk-permissions" >&2
    exit 1
fi

echo "============================================================"
echo "          WOLF LINUX - LICENÇAS ANDROID SDK"
echo "============================================================"
echo
echo "As licenças serão apresentadas pelo próprio Flutter."
echo "O SDK Android permanece root-owned, com escrita concedida ao grupo android-sdk."
echo

exec /opt/flutter/bin/flutter doctor --android-licenses
EOF
    chmod 755 /mnt/usr/local/bin/wolf-android-licenses

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
        timeout 900s arch-chroot /mnt git clone \
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
    export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
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
export CHROME_EXECUTABLE=/usr/bin/google-chrome-stable
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

install_wolf_kde_personal_defaults() {
    info "Instalando as preferencias KDE/Wayland do usuario principal (one-shot)..."
    local defaults_script="/root/wolf-linux/tests/wolf-configure-user-defaults.py"
    local asset_dir="${WOLF_ASSET_DIR:-/root/wolf-linux/assets}"
    local -a options=(--root /mnt --user "$USERNAME_VALUE" --assets "$asset_dir")

    [[ -f "$defaults_script" ]] || die "Arquivo de configuracao do perfil KDE ausente: $defaults_script"
    [[ -d "$asset_dir/zsh" ]] || die "Assets de terminal/Zsh ausentes: $asset_dir/zsh"
    if stack_selected daily; then options+=(--daily); fi
    if stack_selected development; then options+=(--development); fi
    if stack_selected extras; then options+=(--extras); fi
    python "$defaults_script" "${options[@]}" || die "Falha ao aplicar preferencias KDE para o usuario"

    if stack_selected daily; then
        # O arquivo de referencia usa /usr/share/oh-my-zsh. Instalamos o
        # framework uma unica vez. Se a rede falhar, Zsh/P10k continuam
        # funcionais via verificacao de existencia do framework no .zshrc.
        mkdir -p /mnt/usr/share/wolf-linux/fastfetch
        install -m 0644 "$asset_dir/zsh/fastfetch-wolf-linux.txt" \
            /mnt/usr/share/wolf-linux/fastfetch/wolf-linux.txt
        install -m 0644 "$asset_dir/zsh/fastfetch-wolf-linux-ascii.txt" \
            /mnt/usr/share/wolf-linux/fastfetch/wolf-linux-ascii.txt
        if [[ ! -f /mnt/usr/share/oh-my-zsh/oh-my-zsh.sh ]]; then
            if ! arch-chroot /mnt git clone --depth=1 --quiet \
                https://github.com/ohmyzsh/ohmyzsh.git /usr/share/oh-my-zsh; then
                warn "Oh My Zsh nao foi baixado. Zsh e Powerlevel10k funcionam; instale OMZ posteriormente."
            fi
        fi
        [[ -f /mnt/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]] || \
            die "Powerlevel10k ausente apos resolver a stack daily."
        [[ -f /mnt/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] || \
            die "zsh-autosuggestions ausente apos resolver a stack Daily."
        grep -Fq 'zsh-autosuggestions.zsh' "/mnt/home/$USERNAME_VALUE/.zshrc" || \
            die "Perfil Zsh nao carrega o zsh-autosuggestions."
        arch-chroot /mnt chsh -s /usr/bin/zsh "$USERNAME_VALUE" || \
            die "Falha ao definir Zsh como shell de $USERNAME_VALUE"
    fi
    ok "Perfil KDE/Wayland, associacoes MIME, mouse, Alt+Tab, Konsole e Zsh preparados."
}

install_terminal_defaults() {
    mkdir -p /mnt/usr/local/bin
    mkdir -p /mnt/etc/xdg/autostart

    cat > /mnt/usr/local/bin/wolf-apply-terminal-style.sh <<'TERMINAL_EOF'
#!/usr/bin/env bash
set -u

MARKER="$HOME/.config/wolf-linux/terminal-v3.done"

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
    *XFCE*|*Xfce*)
        mkdir -p "$HOME/.config/xfce4/terminal"
        cat > "$HOME/.config/xfce4/terminal/terminalrc" <<'EOF'
[Configuration]
FontName=MesloLGS Nerd Font 11
ColorForeground=#FFFFFF
ColorBackground=#000000
ColorUseTheme=FALSE
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=120x30
MiscInheritGeometry=FALSE
MiscMenubarDefault=FALSE
MiscMouseAutohide=FALSE
MiscMouseWheelZoom=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
ScrollingBar=TERMINAL_SCROLLBAR_NONE
ScrollingLines=10000
EOF
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

install_wolf_desktop_keybindings() {
    info "Preparando atalhos Wolf Linux para MATE/XFCE..."

    cat > /mnt/usr/local/bin/wolf-apply-desktop-keybindings <<'WOLF_KEYS'
#!/usr/bin/env bash
set -u
DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
mkdir -p "$HOME/.config/wolf-linux"

case "$DESKTOP" in
    *MATE*)
        # Brisk usa uma configuração global por processo. Com duas instâncias,
        # Super_L faz ambas abrirem. Desabilitamos o hotkey interno e deixamos
        # os menus clicáveis em cada painel até termos roteamento por instância.
        if gsettings list-schemas | grep -Fxq com.solus-project.brisk-menu; then
            gsettings set com.solus-project.brisk-menu hot-key '' 2>/dev/null || true
        fi

        if gsettings list-schemas | grep -Fxq org.mate.Marco.global-keybindings \
           && gsettings list-schemas | grep -Fxq org.mate.Marco.keybinding-commands; then
            gsettings set org.mate.Marco.global-keybindings run-command-1 '<Primary><Alt>t' || true
            gsettings set org.mate.Marco.keybinding-commands command-1 'mate-terminal' || true
            gsettings set org.mate.Marco.global-keybindings run-command-2 '<Super>e' || true
            gsettings set org.mate.Marco.keybinding-commands command-2 'caja --no-desktop' || true

            # Marco não possui filtro de Alt+Tab por monitor. Usamos um ciclo
            # simples das janelas cujo centro está no monitor do ponteiro.
            if gsettings list-keys org.mate.Marco.global-keybindings | grep -Fxq switch-windows; then
                gsettings set org.mate.Marco.global-keybindings switch-windows 'disabled' || true
            fi
            if gsettings list-keys org.mate.Marco.global-keybindings | grep -Fxq switch-windows-backward; then
                gsettings set org.mate.Marco.global-keybindings switch-windows-backward 'disabled' || true
            fi
            gsettings set org.mate.Marco.global-keybindings run-command-3 '<Alt>Tab' || true
            gsettings set org.mate.Marco.keybinding-commands command-3 '/usr/local/bin/wolf-mate-cycle-window forward' || true
            gsettings set org.mate.Marco.global-keybindings run-command-4 '<Shift><Alt>Tab' || true
            gsettings set org.mate.Marco.keybinding-commands command-4 '/usr/local/bin/wolf-mate-cycle-window backward' || true
        fi
        ;;

    *XFCE*|*Xfce*)
        command -v xfconf-query >/dev/null 2>&1 || exit 0

        setcmd() {
            local key="$1" cmd="$2"
            xfconf-query -c xfce4-keyboard-shortcuts \
                -p "/commands/custom/$key" -n -t string -s "$cmd" 2>/dev/null \
                || xfconf-query -c xfce4-keyboard-shortcuts \
                    -p "/commands/custom/$key" -s "$cmd" 2>/dev/null || true
        }

        setcmd '<Primary><Alt>t' '/usr/local/bin/wolf-xfce-launch-here terminal'
        setcmd '<Super>e' '/usr/local/bin/wolf-xfce-launch-here home'

        # Limpe atalhos legados que chamem o popup do Whisker diretamente em
        # Super; eles competiriam com o xcape e poderiam abrir no ponteiro.
        while IFS= read -r prop; do
            [[ "$prop" == /commands/custom/* ]] || continue
            [[ "$prop" == *Super* ]] || continue
            value="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)"
            if [[ "$value" == *xfce4-popup-whiskermenu* ]]; then
                xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
            fi
        done < <(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null || true)

        # Não associe Super_L diretamente ao Whisker: o Xfce pode disparar a
        # ligação também no início de Super+E. Em vez disso, xcape transforma
        # apenas um toque isolado em Super numa combinação privada.
        setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'
        pkill -x xcape >/dev/null 2>&1 || true
        if command -v xcape >/dev/null 2>&1; then
            xcape -e 'Super_L=Control_L|Alt_L|Shift_L|F12' >/dev/null 2>&1 &
        fi
        ;;
esac
WOLF_KEYS
    chmod 755 /mnt/usr/local/bin/wolf-apply-desktop-keybindings

    cat > /mnt/usr/local/bin/wolf-mate-cycle-window <<'WOLF_MATE_CYCLE'
#!/usr/bin/env python3
import sys
import gi
gi.require_version("Gdk", "3.0")
gi.require_version("Wnck", "3.0")
from gi.repository import Gdk, Wnck

direction = -1 if len(sys.argv) > 1 and sys.argv[1] == "backward" else 1
screen = Wnck.Screen.get_default(); screen.force_update()
display = Gdk.Display.get_default()
seat = display.get_default_seat(); pointer = seat.get_pointer()
_, x, y = pointer.get_position()
monitor = display.get_monitor_at_point(x, y)
geom = monitor.get_geometry() if monitor else None
ws = screen.get_active_workspace()
windows=[]
for w in screen.get_windows_stacked():
    try:
        if w.is_skip_tasklist(): continue
        if ws and not (w.is_pinned() or w.is_on_workspace(ws)): continue
        wx,wy,ww,wh=w.get_geometry(); cx=wx+max(1,ww)//2; cy=wy+max(1,wh)//2
        if geom and not (geom.x <= cx < geom.x+geom.width and geom.y <= cy < geom.y+geom.height): continue
        windows.append(w)
    except Exception: pass
if not windows: raise SystemExit(0)
active=screen.get_active_window()
try: idx=windows.index(active)
except ValueError: idx=-1 if direction>0 else 0
target=windows[(idx+direction)%len(windows)]
try:
    target.unminimize(Gdk.CURRENT_TIME)
    target.activate(Gdk.CURRENT_TIME)
except Exception: pass
WOLF_MATE_CYCLE
    chmod 755 /mnt/usr/local/bin/wolf-mate-cycle-window

    cat > /mnt/etc/xdg/autostart/wolf-desktop-keybindings.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Atalhos do desktop
Exec=/usr/local/bin/wolf-apply-desktop-keybindings
NotShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
}

install_xfce_defaults() {
    [[ "$DESKTOP" == "xfce" ]] || return 0
    info "Preparando XFCE X11-only, painel Wolf, Whisker e MultiMonitor..."

    install -d /mnt/usr/local/bin /mnt/usr/local/sbin /mnt/etc/pacman.d/hooks
    install -d /mnt/etc/xdg/autostart /mnt/etc/xdg/xfce4/panel /mnt/usr/share/applications

    if [[ -f "$PROJECT_DIR/tools/wolf-xfce-compositor-0.1.sh" ]]; then
        install -Dm0755 "$PROJECT_DIR/tools/wolf-xfce-compositor-0.1.sh" \
            /mnt/usr/local/bin/wolf-xfce-compositor
    fi

    cat > /mnt/etc/xdg/autostart/wolf-xfce-compositor-default.desktop <<'XFCE_PICOM_AUTOSTART'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Compositor XFCE
Comment=Aplica Picom/XRender uma única vez como padrão inicial do XFCE
Exec=/usr/local/bin/wolf-xfce-compositor ensure-default
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
XFCE_PICOM_AUTOSTART

    # --------------------------------------------------------
    # XFCE somente em X11.
    # O Arch fornece xfce-wayland.desktop mesmo sendo experimental.
    # Removemos a entrada e reaplicamos após upgrades do xfce4-session.
    # --------------------------------------------------------
    cat > /mnt/usr/local/sbin/wolf-disable-xfce-wayland <<'XFCE_X11'
#!/usr/bin/env bash
set -euo pipefail
rm -f /usr/share/wayland-sessions/xfce-wayland.desktop
XFCE_X11
    chmod 755 /mnt/usr/local/sbin/wolf-disable-xfce-wayland

    cat > /mnt/etc/pacman.d/hooks/wolf-xfce-x11-only.hook <<'XFCE_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = xfce4-session

[Action]
Description = Wolf Linux: mantendo XFCE somente em X11...
When = PostTransaction
Exec = /usr/local/sbin/wolf-disable-xfce-wayland
XFCE_HOOK

    arch-chroot /mnt /usr/local/sbin/wolf-disable-xfce-wayland

    arch-chroot /mnt install -d -o sddm -g sddm /var/lib/sddm
    cat > /mnt/var/lib/sddm/state.conf <<EOF
[Last]
Session=xfce.desktop
User=$USERNAME_VALUE
EOF
    arch-chroot /mnt chown sddm:sddm /var/lib/sddm/state.conf

    # --------------------------------------------------------
    # Launchers Wolf usados no painel principal e secundários.
    # O xfce4-panel copia estes arquivos para launcher-<id>/ no
    # perfil do usuário; isso evita ícones genéricos sem aplicativo.
    # --------------------------------------------------------
    cat > /mnt/usr/share/applications/wolf-xfce-browser.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=/usr/local/bin/wolf-xfce-launch-here browser %U
Icon=google-chrome
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=Network;WebBrowser;
EOF

    cat > /mnt/usr/share/applications/wolf-xfce-home.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Pasta pessoal
Exec=/usr/local/bin/wolf-xfce-launch-here home
Icon=user-home
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=System;FileTools;FileManager;
EOF

    cat > /mnt/usr/share/applications/wolf-xfce-terminal.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Terminal
Exec=/usr/local/bin/wolf-xfce-launch-here terminal
Icon=utilities-terminal
Terminal=false
StartupNotify=true
NoDisplay=true
Categories=System;TerminalEmulator;
EOF

    # --------------------------------------------------------
    # Default do painel: UMA barra inferior, sem pager, sem Action Buttons
    # e sem o segundo painel/dock padrão do XFCE.
    # O MultiMonitor replica uma versão reduzida nas telas secundárias.
    # --------------------------------------------------------
    cat > /mnt/etc/xdg/xfce4/panel/default.xml <<'XFCE_PANEL'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="36"/>
      <property name="nrows" type="uint" value="1"/>
      <property name="span-monitors" type="bool" value="false"/>
      <property name="autohide-behavior" type="uint" value="0"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/><value type="int" value="5"/>
        <value type="int" value="6"/><value type="int" value="7"/>
        <value type="int" value="8"/><value type="int" value="9"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <!-- Os três launchers fixos são materializados no primeiro login. -->
    <property name="plugin-5" type="string" value="tasklist">
      <property name="include-all-monitors" type="bool" value="false"/>
      <property name="include-all-workspaces" type="bool" value="false"/>
      <property name="grouping" type="uint" value="1"/>
      <property name="show-labels" type="bool" value="true"/>
    </property>
    <property name="plugin-6" type="string" value="separator"><property name="expand" type="bool" value="true"/><property name="style" type="uint" value="0"/></property>
    <property name="plugin-7" type="string" value="systray"><property name="square-icons" type="bool" value="true"/></property>
    <property name="plugin-8" type="string" value="clock"/>
    <property name="plugin-9" type="string" value="showdesktop"/>
  </property>
</channel>
XFCE_PANEL

    cat > /mnt/usr/local/bin/wolf-xfce-desktop-setup <<'XFCE_SETUP'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.7"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/xfce"
LAYOUT_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v7.done"
APPEARANCE_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-appearance-v1.done"
WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
WHISKER_ICON="$HOME/.local/share/icons/wolf-whisker.png"
FORCE=0
PANEL_RESTART_PENDING=0

log(){ printf '[Wolf XFCE Setup] %s\n' "$*"; }

ensure_panel_on_exit() {
    if (( PANEL_RESTART_PENDING )) && command -v xfce4-panel >/dev/null 2>&1; then
        log "Reconstrução interrompida; reiniciando xfce4-panel como proteção."
        nohup xfce4-panel >/dev/null 2>&1 &
    fi
}
trap ensure_panel_on_exit EXIT

report_setup_error() {
    local rc="$?"
    local line="${BASH_LINENO[0]:-${LINENO}}"
    printf '[Wolf XFCE Setup] ERRO: linha %s: %s (status %s)\n' \
        "$line" "$BASH_COMMAND" "$rc" >&2
    return "$rc"
}
trap report_setup_error ERR

if [[ "${1:-apply}" == "--force" || "${2:-}" == "--force" ]]; then
    FORCE=1
fi

wait_for_xfce() {
    local i
    for ((i=0; i<30; i++)); do
        if xfconf-query -c xsettings -p /Net/ThemeName >/dev/null 2>&1 \
            && xrandr --listmonitors >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log "xfconf/XRandR ainda não ficaram prontos; tentando mesmo assim."
}

set_prop() {
    local channel="$1" prop="$2" type="$3" value="$4"
    if xfconf-query -c "$channel" -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$prop" -s "$value" >/dev/null 2>&1 || true
    else
        xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" >/dev/null 2>&1 || true
    fi
}

set_int_array() {
    local channel="$1" prop="$2"; shift 2
    local args=(xfconf-query -c "$channel" -p "$prop") v
    xfconf-query -c "$channel" -p "$prop" -r >/dev/null 2>&1 || true
    args+=( -n -a )
    for v in "$@"; do args+=( -t int -s "$v" ); done
    "${args[@]}" >/dev/null 2>&1 || true
}

set_string_array() {
    local channel="$1" prop="$2"; shift 2
    local args=(xfconf-query -c "$channel" -p "$prop") v
    xfconf-query -c "$channel" -p "$prop" -r >/dev/null 2>&1 || true
    args+=( -n -a )
    for v in "$@"; do args+=( -t string -s "$v" ); done
    "${args[@]}" >/dev/null 2>&1 || true
}

connected_outputs() {
    xrandr --query 2>/dev/null | awk '$2 == "connected" {print $1}'
}

primary_output() {
    local out
    out="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && /\*/ {print $NF; exit}')"
    [[ -n "$out" ]] || out="$(connected_outputs | head -n1)"
    printf '%s\n' "$out"
}

launcher_source() {
    case "$1" in
        browser)  printf '%s\n' /usr/share/applications/wolf-xfce-browser.desktop ;;
        home)     printf '%s\n' /usr/share/applications/wolf-xfce-home.desktop ;;
        terminal) printf '%s\n' /usr/share/applications/wolf-xfce-terminal.desktop ;;
        *) return 1 ;;
    esac
}

create_launcher() {
    local id="$1" kind="$2" source base dir
    source="$(launcher_source "$kind")"
    [[ -f "$source" ]] || { log "Launcher ausente: $source"; return 1; }
    base="$(basename "$source")"
    dir="$HOME/.config/xfce4/panel/launcher-$id"
    mkdir -p "$dir"
    cp -f "$source" "$dir/$base"
    chmod 644 "$dir/$base"
    set_prop xfce4-panel "/plugins/plugin-$id" string launcher
    set_string_array xfce4-panel "/plugins/plugin-$id/items" "$base"
}

create_whisker_icon() {
    local src=""
    for candidate in \
        /usr/share/plymouth/themes/wolf-linux/logo.png \
        /usr/share/icons/hicolor/256x256/apps/wolf-linux.png \
        /usr/share/pixmaps/wolf-linux.png; do
        if [[ -r "$candidate" ]]; then src="$candidate"; break; fi
    done
    [[ -n "$src" ]] || return 0
    mkdir -p "$(dirname "$WHISKER_ICON")"
    python3 - "$src" "$WHISKER_ICON" <<'PYICON'
from PIL import Image, ImageDraw
import sys
src, dst = sys.argv[1:3]
im = Image.open(src).convert('RGBA')
alpha = im.getchannel('A')
bbox = alpha.getbbox()
if bbox:
    im = im.crop(bbox)
size = 128
canvas = Image.new('RGBA', (size, size), (0,0,0,0))
d = ImageDraw.Draw(canvas)
d.ellipse((3,3,size-4,size-4), fill=(24,24,27,245), outline=(220,220,224,255), width=4)
im.thumbnail((92,92), Image.Resampling.LANCZOS)
x=(size-im.width)//2; y=(size-im.height)//2
canvas.alpha_composite(im, (x,y))
canvas.save(dst)
PYICON
}

set_rc_value() {
    local file="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

configure_whisker() {
    local id="$1"
    local rc="$HOME/.config/xfce4/panel/whiskermenu-${id}.rc"
    set_prop xfce4-panel "/plugins/plugin-$id" string whiskermenu
    create_whisker_icon
    [[ -f "$WHISKER_ICON" ]] && set_rc_value "$rc" button-icon "$WHISKER_ICON"
    set_rc_value "$rc" show-button-title false
    set_rc_value "$rc" show-button-icon true
}

configure_all_whiskers() {
    local prop id type
    while IFS= read -r prop; do
        [[ "$prop" =~ ^/plugins/plugin-([0-9]+)$ ]] || continue
        id="${BASH_REMATCH[1]}"
        type="$(xfconf-query -c xfce4-panel -p "$prop" 2>/dev/null || true)"
        if [[ "$type" == whiskermenu ]]; then
            configure_whisker "$id"
        fi
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+$' || true)

    # Com `set -e`, o status da última condição dentro de um while pode
    # vazar como status da função. Esta função é de varredura/best-effort:
    # não encontrar Whisker no último plugin nunca deve abortar o layout.
    return 0
}

configure_tasklist() {
    local id="$1"
    set_prop xfce4-panel "/plugins/plugin-$id" string tasklist
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-monitors" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-workspaces" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/grouping" uint 1
    set_prop xfce4-panel "/plugins/plugin-$id/show-labels" bool true
}

create_main_panel() {
    local out="$1"
    local ids=(1 2 3 4 5 6 7 8 9 10)

    set_prop xfce4-panel /configver int 2
    set_int_array xfce4-panel /panels 1
    set_prop xfce4-panel /panels/dark-mode bool true
    set_prop xfce4-panel /panels/panel-1/output-name string "$out"
    set_prop xfce4-panel /panels/panel-1/position string 'p=8;x=0;y=0'
    set_prop xfce4-panel /panels/panel-1/position-locked bool true
    set_prop xfce4-panel /panels/panel-1/length uint 100
    set_prop xfce4-panel /panels/panel-1/size uint 36
    set_prop xfce4-panel /panels/panel-1/nrows uint 1
    set_prop xfce4-panel /panels/panel-1/span-monitors bool false
    set_prop xfce4-panel /panels/panel-1/autohide-behavior uint 0
    set_int_array xfce4-panel /panels/panel-1/plugin-ids "${ids[@]}"

    configure_whisker 1
    create_launcher 2 browser
    create_launcher 3 home
    create_launcher 4 terminal
    configure_tasklist 5

    set_prop xfce4-panel /plugins/plugin-6 string separator
    set_prop xfce4-panel /plugins/plugin-6/expand bool true
    set_prop xfce4-panel /plugins/plugin-6/style uint 0

    set_prop xfce4-panel /plugins/plugin-7 string systray
    set_prop xfce4-panel /plugins/plugin-7/square-icons bool true

    # Controle de volume nativo do painel. Ele usa libpulse, portanto funciona
    # normalmente sobre pipewire-pulse; não significa voltar a PulseAudio.
    set_prop xfce4-panel /plugins/plugin-8 string pulseaudio

    set_prop xfce4-panel /plugins/plugin-9 string clock
    set_prop xfce4-panel /plugins/plugin-10 string showdesktop
}

ensure_panel_css() {
    # O xfce4-pulseaudio-plugin tende a usar um ícone maior que systray/clock
    # em painéis de 36 px. Ajuste só a imagem do botão, sem afetar o popup.
    local css="$HOME/.config/gtk-3.0/gtk.css"
    mkdir -p "$(dirname "$css")"
    python3 - "$css" <<'PYCSS'
from pathlib import Path
import sys
p = Path(sys.argv[1])
start = "/* WOLF-XFCE-PULSEAUDIO-BEGIN */"
end = "/* WOLF-XFCE-PULSEAUDIO-END */"
block = """/* WOLF-XFCE-PULSEAUDIO-BEGIN */
#pulseaudio-button > box > image {
  -gtk-icon-transform: scale(0.62);
}
#pulseaudio-button {
  padding: 3px;
}
/* WOLF-XFCE-PULSEAUDIO-END */
"""
text = p.read_text(encoding="utf-8") if p.exists() else ""
if start in text and end in text:
    before = text.split(start, 1)[0].rstrip()
    after = text.split(end, 1)[1].lstrip("\n")
    text = (before + "\n\n" if before else "") + block + ("\n" + after if after else "")
else:
    text = text.rstrip()
    text = (text + "\n\n" if text else "") + block
p.write_text(text, encoding="utf-8")
PYCSS
}

apply_style() {
    set_prop xsettings /Net/ThemeName string Materia-dark
    set_prop xsettings /Net/IconThemeName string Papirus-Dark
    set_prop xsettings /Gtk/CursorThemeName string breeze_cursors
    set_prop xsettings /Gtk/CursorThemeSize int 24
    set_prop xsettings /Gtk/MonospaceFontName string 'MesloLGS Nerd Font 11'
    set_prop xsettings /Xfce/SyncThemes bool true
    set_prop xfwm4 /general/theme string Materia-dark
    set_prop xfwm4 /general/workspace_count int 1
    # Novas janelas seguem o monitor do ponteiro. Isso faz lançamentos pelo
    # Whisker de cada tela tenderem naturalmente a nascer naquela mesma tela.
    set_prop xfwm4 /general/placement_mode string mouse
    set_prop xfwm4 /general/placement_ratio int 100
    set_prop xfwm4 /general/focus_new bool true
    # NVIDIA/X11: o compositor do xfwm4 causa stutter perceptível ao mover
    # janelas/abas em alguns sistemas. O perfil Wolf prioriza baixa latência.
    set_prop xfwm4 /general/use_compositing bool false
    set_prop xfce4-panel /panels/dark-mode bool true

    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.local/share/icons/default"
    cat > "$HOME/.config/gtk-3.0/settings.ini" <<'GTK'
[Settings]
gtk-application-prefer-dark-theme=true
gtk-theme-name=Materia-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=breeze_cursors
gtk-cursor-theme-size=24
GTK
    cp -f "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
    cat > "$HOME/.local/share/icons/default/index.theme" <<'CURSOR'
[Icon Theme]
Inherits=breeze_cursors
CURSOR

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    fi
}

apply_terminal_style() {
    mkdir -p "$HOME/.config/xfce4/terminal"
    cat > "$HOME/.config/xfce4/terminal/terminalrc" <<'EOF_TERMINAL'
[Configuration]
FontName=MesloLGS Nerd Font 11
ColorForeground=#FFFFFF
ColorBackground=#000000
ColorUseTheme=FALSE
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=120x30
MiscInheritGeometry=FALSE
MiscMenubarDefault=FALSE
MiscMouseAutohide=FALSE
MiscMouseWheelZoom=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
ScrollingBar=TERMINAL_SCROLLBAR_NONE
ScrollingLines=10000
EOF_TERMINAL
}

path_to_uri() {
    python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve().as_uri())
PY
}

apply_user_dirs() {
    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        xdg-user-dirs-update >/dev/null 2>&1 || true
    fi
    mkdir -p "$HOME/.config/gtk-3.0"
    local bookmarks="$HOME/.config/gtk-3.0/bookmarks" tmp kind path uri label
    tmp="$(mktemp)"
    [[ -f "$bookmarks" ]] && cat "$bookmarks" > "$tmp"

    for kind in DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS TEMPLATES PUBLICSHARE; do
        path="$(xdg-user-dir "$kind" 2>/dev/null || true)"
        [[ -n "$path" && "$path" != "$HOME" && -d "$path" ]] || continue
        uri="$(path_to_uri "$path")"
        label="$(basename "$path")"
        grep -Fq "$uri" "$tmp" 2>/dev/null || printf '%s %s\n' "$uri" "$label" >> "$tmp"
    done
    mv -f "$tmp" "$bookmarks"
}

apply_xfce_helpers() {
    mkdir -p "$HOME/.config/xfce4" "$HOME/.local/share/xfce4/helpers"
    cat > "$HOME/.config/xfce4/helpers.rc" <<'HELPERS'
WebBrowser=custom-WebBrowser
FileManager=Thunar
TerminalEmulator=xfce4-terminal
HELPERS
    cat > "$HOME/.local/share/xfce4/helpers/custom-WebBrowser.desktop" <<'BROWSER'
[Desktop Entry]
NoDisplay=true
Version=1.0
Encoding=UTF-8
Type=X-XFCE-Helper
X-XFCE-Category=WebBrowser
X-XFCE-CommandsWithParameter=/usr/bin/google-chrome-stable "%s"
Icon=google-chrome
Name=Google Chrome
X-XFCE-Commands=/usr/bin/google-chrome-stable
BROWSER
}

apply_thunar_vscode_action() {
    command -v code >/dev/null 2>&1 || return 0
    mkdir -p "$HOME/.config/Thunar"
    python3 - "$HOME/.config/Thunar/uca.xml" <<'PYUCA'
from pathlib import Path
import sys, xml.etree.ElementTree as ET
p=Path(sys.argv[1])
try:
    tree=ET.parse(p); root=tree.getroot()
except Exception:
    root=ET.Element('actions'); tree=ET.ElementTree(root)
name='Abrir esta pasta no VS Code'
for action in list(root.findall('action')):
    n=action.find('name')
    uid=action.find('unique-id')
    if (n is not None and n.text == name) or (uid is not None and uid.text == 'wolf-open-vscode'):
        root.remove(action)
a=ET.SubElement(root,'action')
for tag,text in [
    ('icon','visual-studio-code'),
    ('name',name),
    ('submenu',''),
    ('unique-id','wolf-open-vscode'),
    ('command','code --new-window "%f"'),
    ('description','Abrir a pasta atual no Visual Studio Code'),
    ('range','*'),
    ('patterns','*'),
]:
    e=ET.SubElement(a,tag); e.text=text
ET.SubElement(a,'directories')
ET.indent(tree, space='  ')
p.parent.mkdir(parents=True,exist_ok=True)
tree.write(p,encoding='UTF-8',xml_declaration=True)
PYUCA
}

apply_mouse_flat() {
    if [[ "${XDG_SESSION_TYPE:-x11}" == x11 ]] && [[ -x /usr/local/bin/wolf-disable-mouse-accel.sh ]]; then
        /usr/local/bin/wolf-disable-mouse-accel.sh >/dev/null 2>&1 || true
    fi
}

apply_wallpaper() {
    [[ -f "$WALLPAPER" ]] || { log "Wallpaper Wolf não encontrado: $WALLPAPER"; return 0; }

    set_prop xfce4-desktop /backdrop/single-workspace-mode bool true
    set_prop xfce4-desktop /backdrop/single-workspace-number int 0

    local out base prop
    while IFS= read -r out; do
        [[ -n "$out" ]] || continue
        base="/backdrop/screen0/monitor${out}/workspace0"
        set_prop xfce4-desktop "$base/last-image" string "$WALLPAPER"
        set_prop xfce4-desktop "$base/image-style" int 5
        set_prop xfce4-desktop "$base/color-style" int 0
    done < <(connected_outputs)

    while IFS= read -r prop; do
        [[ -n "$prop" ]] || continue
        case "$prop" in
            */last-image|*/last-single-image|*/image-path)
                xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" >/dev/null 2>&1 || true
                ;;
        esac
    done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null || true)

    if command -v xfdesktop >/dev/null 2>&1; then
        xfdesktop --reload >/dev/null 2>&1 || true
    fi
}

apply_first_login_appearance() {
    if [[ -f "$APPEARANCE_MARKER" ]]; then
        log "Aparência inicial já aplicada; preservando tema, wallpaper e preferências do usuário."
        return 0
    fi

    apply_style
    apply_terminal_style
    apply_wallpaper

    mkdir -p "$(dirname "$APPEARANCE_MARKER")"
    touch "$APPEARANCE_MARKER"
    log "Aparência inicial aplicada uma única vez."
}

backup_current() {
    local stamp dest
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="$STATE_DIR/$stamp"
    mkdir -p "$dest"
    if [[ -d "$HOME/.config/xfce4" ]]; then
        cp -a "$HOME/.config/xfce4" "$dest/xfce4-config" 2>/dev/null || true
    fi
    xfconf-query -c xfce4-panel -lv > "$dest/xfce4-panel.txt" 2>/dev/null || true
    printf '%s\n' "$dest" > "$STATE_DIR/latest"
    log "Backup: $dest"
}

apply_layout() {
    command -v xfconf-query >/dev/null 2>&1 || return 0
    command -v xrandr >/dev/null 2>&1 || return 0
    wait_for_xfce

    local out
    out="$(primary_output)"
    [[ -n "$out" ]] || { log "Nenhum monitor ativo detectado."; return 1; }

    # Tudo que pode falhar sem tocar no painel é preparado antes da etapa destrutiva.
    create_whisker_icon
    backup_current
    PANEL_RESTART_PENDING=1
    xfce4-panel -q >/dev/null 2>&1 || true
    sleep 1
    xfconf-query -c xfce4-panel -p /panels -r -R >/dev/null 2>&1 || true
    xfconf-query -c xfce4-panel -p /plugins -r -R >/dev/null 2>&1 || true
    xfconf-query -c xfce4-panel -p /configver -r >/dev/null 2>&1 || true
    rm -rf "$HOME/.config/xfce4/panel/launcher-"* 2>/dev/null || true

    create_main_panel "$out"
    ensure_panel_css
    apply_first_login_appearance
    apply_user_dirs
    apply_xfce_helpers
    apply_thunar_vscode_action
    configure_all_whiskers
    apply_mouse_flat

    nohup xfce4-panel >/dev/null 2>&1 &
    sleep 2
    PANEL_RESTART_PENDING=0

    mkdir -p "$(dirname "$LAYOUT_MARKER")"
    touch "$LAYOUT_MARKER"
    log "Painel principal Wolf Linux aplicado em $out."
}

status() {
    printf 'Wolf XFCE Desktop Setup v%s\n' "$VERSION"
    local marker_state="pendente" appearance_state="pendente"
    [[ -f "$LAYOUT_MARKER" ]] && marker_state="aplicado"
    [[ -f "$APPEARANCE_MARKER" ]] && appearance_state="aplicada/preservada"
    printf 'Layout inicial: %s\n' "$marker_state"
    printf 'Aparência inicial: %s\n' "$appearance_state"
    printf 'Tema: %s\n' "$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)"
    printf 'Tema XFWM: %s\n' "$(xfconf-query -c xfwm4 -p /general/theme 2>/dev/null || true)"
    printf 'Workspaces: %s\n' "$(xfconf-query -c xfwm4 -p /general/workspace_count 2>/dev/null || true)"
    printf 'Painéis: '
    xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true
    printf 'Placement: %s\n' "$(xfconf-query -c xfwm4 -p /general/placement_mode 2>/dev/null || true)"
    printf 'Ícone Whisker: %s\n' "$WHISKER_ICON"
    printf 'Fonte terminal: '
    grep '^FontName=' "$HOME/.config/xfce4/terminal/terminalrc" 2>/dev/null || true
}

case "${1:-apply}" in
    apply)
        wait_for_xfce
        if (( FORCE == 0 )); then
            if [[ -f "$LAYOUT_MARKER" ]] || compgen -G "${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-layout-v*.done" >/dev/null; then
                # Layout e aparência são política de PRIMEIRO LOGIN. Revisões
                # futuras não reconstroem o painel de um usuário já configurado.
                exit 0
            fi
        fi
        apply_layout
        ;;
    force|--force)
        FORCE=1
        apply_layout
        ;;
    css|ensure-css)
        ensure_panel_css
        ;;
    status) status ;;
    *) echo "Uso: $0 [apply|force|status]" >&2; exit 2 ;;
esac
XFCE_SETUP
    chmod 755 /mnt/usr/local/bin/wolf-xfce-desktop-setup

    cat > /mnt/usr/local/bin/wolf-xfce-multimonitor <<'XFCE_MM'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.5"
DISABLED_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux/xfce-multimonitor.disabled"

log(){ printf '[Wolf XFCE MultiMonitor] %s\n' "$*"; }

set_prop() {
    local channel="$1" prop="$2" type="$3" value="$4"
    if xfconf-query -c "$channel" -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$prop" -s "$value" >/dev/null 2>&1 || true
    else
        xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" >/dev/null 2>&1 || true
    fi
}

set_int_array() {
    local channel="$1" prop="$2"; shift 2
    local args=(xfconf-query -c "$channel" -p "$prop") v
    xfconf-query -c "$channel" -p "$prop" -r >/dev/null 2>&1 || true
    args+=( -n -a )
    for v in "$@"; do args+=( -t int -s "$v" ); done
    "${args[@]}" >/dev/null 2>&1 || true
}

set_string_array() {
    local channel="$1" prop="$2"; shift 2
    local args=(xfconf-query -c "$channel" -p "$prop") v
    xfconf-query -c "$channel" -p "$prop" -r >/dev/null 2>&1 || true
    args+=( -n -a )
    for v in "$@"; do args+=( -t string -s "$v" ); done
    "${args[@]}" >/dev/null 2>&1 || true
}

monitor_outputs() { xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $NF}'; }
primary_output() {
    local out
    out="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && /\*/ {print $NF; exit}')"
    [[ -n "$out" ]] || out="$(monitor_outputs | head -n1)"
    printf '%s\n' "$out"
}

next_plugin_id() {
    local max=0 prop id
    while IFS= read -r prop; do
        [[ "$prop" =~ ^/plugins/plugin-([0-9]+)$ ]] || continue
        id="${BASH_REMATCH[1]}"
        (( id > max )) && max="$id"
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+$' || true)
    echo $((max + 1))
}

panel_ids() { xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' || true; }

launcher_source() {
    case "$1" in
        browser)  printf '%s\n' /usr/share/applications/wolf-xfce-browser.desktop ;;
        home)     printf '%s\n' /usr/share/applications/wolf-xfce-home.desktop ;;
        terminal) printf '%s\n' /usr/share/applications/wolf-xfce-terminal.desktop ;;
        *) return 1 ;;
    esac
}

create_launcher() {
    local id="$1" kind="$2" source base dir
    source="$(launcher_source "$kind")"
    [[ -f "$source" ]] || return 1
    base="$(basename "$source")"
    dir="$HOME/.config/xfce4/panel/launcher-$id"
    mkdir -p "$dir"
    cp -f "$source" "$dir/$base"
    chmod 644 "$dir/$base"
    set_prop xfce4-panel "/plugins/plugin-$id" string launcher
    set_string_array xfce4-panel "/plugins/plugin-$id/items" "$base"
}

configure_whisker() {
    local id="$1"
    set_prop xfce4-panel "/plugins/plugin-$id" string whiskermenu
    local icon="$HOME/.local/share/icons/wolf-whisker.png"
    local rc="$HOME/.config/xfce4/panel/whiskermenu-${id}.rc"
    mkdir -p "$(dirname "$rc")"
    touch "$rc"
    if [[ -f "$icon" ]]; then
        if grep -q '^button-icon=' "$rc"; then
            sed -i "s|^button-icon=.*|button-icon=$icon|" "$rc"
        else
            printf 'button-icon=%s\n' "$icon" >> "$rc"
        fi
    fi
    for kv in 'show-button-title=false' 'show-button-icon=true'; do
        local key="${kv%%=*}" value="${kv#*=}"
        if grep -q "^${key}=" "$rc"; then sed -i "s|^${key}=.*|${key}=${value}|" "$rc"; else printf '%s\n' "$kv" >> "$rc"; fi
    done
}

configure_tasklist() {
    local id="$1"
    set_prop xfce4-panel "/plugins/plugin-$id" string tasklist
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-monitors" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/include-all-workspaces" bool false
    set_prop xfce4-panel "/plugins/plugin-$id/grouping" uint 1
    set_prop xfce4-panel "/plugins/plugin-$id/show-labels" bool true
}

create_secondary_layout() {
    local pid="$1" out="$2" next id
    local ids=()
    next="$(next_plugin_id)"

    set_prop xfce4-panel "/panels/panel-$pid/output-name" string "$out"
    set_prop xfce4-panel "/panels/panel-$pid/position" string 'p=8;x=0;y=0'
    set_prop xfce4-panel "/panels/panel-$pid/position-locked" bool true
    set_prop xfce4-panel "/panels/panel-$pid/length" uint 100
    set_prop xfce4-panel "/panels/panel-$pid/size" uint 36
    set_prop xfce4-panel "/panels/panel-$pid/nrows" uint 1
    set_prop xfce4-panel "/panels/panel-$pid/span-monitors" bool false
    set_prop xfce4-panel "/panels/panel-$pid/autohide-behavior" uint 0
    set_prop xfce4-panel "/panels/panel-$pid/wolf-managed" bool true
    set_prop xfce4-panel "/panels/panel-$pid/wolf-layout-version" int 5

    id="$next"; next=$((next+1)); ids+=("$id"); configure_whisker "$id"
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" browser
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" home
    id="$next"; next=$((next+1)); ids+=("$id"); create_launcher "$id" terminal
    id="$next"; next=$((next+1)); ids+=("$id"); configure_tasklist "$id"
    id="$next"; next=$((next+1)); ids+=("$id"); set_prop xfce4-panel "/plugins/plugin-$id" string separator; set_prop xfce4-panel "/plugins/plugin-$id/expand" bool true; set_prop xfce4-panel "/plugins/plugin-$id/style" uint 0
    id="$next"; ids+=("$id"); set_prop xfce4-panel "/plugins/plugin-$id" string clock

    set_int_array xfce4-panel "/panels/panel-$pid/plugin-ids" "${ids[@]}"
}

ensure_tasklists_local() {
    local prop type
    while IFS= read -r prop; do
        [[ "$prop" =~ ^/plugins/plugin-[0-9]+$ ]] || continue
        type="$(xfconf-query -c xfce4-panel -p "$prop" 2>/dev/null || true)"
        [[ "$type" == tasklist ]] || continue
        set_prop xfce4-panel "$prop/include-all-monitors" bool false
        set_prop xfce4-panel "$prop/include-all-workspaces" bool false
    done < <(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -E '^/plugins/plugin-[0-9]+$' || true)
}

apply_layout() {
    [[ -e "$DISABLED_MARKER" ]] && return 0
    command -v xfconf-query >/dev/null 2>&1 || return 0
    command -v xrandr >/dev/null 2>&1 || return 0

    local primary out pid max_panel=1 used current_output
    local -a outputs=() panels=() managed=() secondary_outputs=() unused_managed=()
    mapfile -t outputs < <(monitor_outputs)
    ((${#outputs[@]})) || return 0
    primary="$(primary_output)"

    mapfile -t panels < <(panel_ids)
    if ((${#panels[@]} == 0)); then
        # Recuperação excepcional: só reconstrua o layout base se realmente
        # não existir painel algum. Em condições normais, nunca reescrevemos
        # preferências de plugins já existentes.
        /usr/local/bin/wolf-xfce-desktop-setup force >/dev/null 2>&1 || true
        mapfile -t panels < <(panel_ids)
    fi

    # A única preferência do painel principal gerenciada continuamente é o
    # output físico. Não tocamos em tamanho, scroll, autohide, plugins etc.
    current_output="$(xfconf-query -c xfce4-panel -p /panels/panel-1/output-name 2>/dev/null || true)"
    if [[ -n "$primary" && "$current_output" != "$primary" ]]; then
        set_prop xfce4-panel /panels/panel-1/output-name string "$primary"
        log "painel principal associado a $primary"
    fi

    for out in "${outputs[@]}"; do
        [[ "$out" == "$primary" ]] || secondary_outputs+=("$out")
    done

    for pid in "${panels[@]}"; do
        (( pid > max_panel )) && max_panel="$pid"
        [[ "$pid" == 1 ]] && continue
        if [[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/wolf-managed" 2>/dev/null || true)" == true ]]; then
            managed+=("$pid")
        fi
    done

    declare -A assigned=()
    for out in "${secondary_outputs[@]}"; do
        for pid in "${managed[@]}"; do
            if [[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/output-name" 2>/dev/null || true)" == "$out" ]]; then
                assigned["$out"]="$pid"
                break
            fi
        done
    done

    # Não fazemos mais "upgrade destrutivo" de painéis já existentes por
    # versão. O usuário pode personalizar scroll, tamanho, plugins e comportamento
    # à vontade; esses ajustes sobrevivem a reboot e hotplug.
    for pid in "${managed[@]}"; do
        used=0
        for out in "${!assigned[@]}"; do
            [[ "${assigned[$out]}" == "$pid" ]] && used=1
        done
        (( used == 0 )) && unused_managed+=("$pid")
    done

    for out in "${secondary_outputs[@]}"; do
        [[ -n "${assigned[$out]:-}" ]] && continue
        if ((${#unused_managed[@]})); then
            pid="${unused_managed[0]}"
            unused_managed=("${unused_managed[@]:1}")
            set_prop xfce4-panel "/panels/panel-$pid/output-name" string "$out"
            assigned["$out"]="$pid"
            log "painel Wolf existente reassociado a $out (panel-$pid)"
        else
            max_panel=$((max_panel + 1)); pid="$max_panel"
            panels+=("$pid")
            set_int_array xfce4-panel /panels "${panels[@]}"
            create_secondary_layout "$pid" "$out"
            assigned["$out"]="$pid"
            log "painel secundário criado em $out (panel-$pid)"
        fi
    done

    # Esta é parte essencial da política multimonitor e não altera scroll nem
    # demais preferências do tasklist.
    ensure_tasklists_local

    # NÃO execute xfce4-panel -r aqui. O painel observa xfconf em tempo real e
    # um restart no login estava sobrescrevendo/perturbando ajustes do usuário.
}

status() {
    printf 'Wolf XFCE MultiMonitor v%s\n' "$VERSION"
    local auto_state='ativado'
    [[ -e "$DISABLED_MARKER" ]] && auto_state='desativado'
    printf 'Automático: %s\n' "$auto_state"
    xrandr --listmonitors 2>/dev/null || true
    echo 'Painéis:'
    local pid
    while IFS= read -r pid; do
        local suffix=""
        [[ "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/wolf-managed" 2>/dev/null || true)" == true ]] && suffix=" [Wolf]"
        printf '  panel-%s -> %s%s\n' "$pid" \
            "$(xfconf-query -c xfce4-panel -p "/panels/panel-$pid/output-name" 2>/dev/null || echo Automatic)" \
            "$suffix"
    done < <(panel_ids)
}

watch_loop() {
    command -v xev >/dev/null 2>&1 || {
        log "xev não encontrado; aplicando layout uma vez e encerrando o watcher."
        apply_layout
        return 0
    }

    # Reconciliação leve no início da sessão. Como apply_layout é não destrutivo,
    # isso não reinicia o painel nem restaura preferências padrão.
    apply_layout

    local line now last_apply=0
    while true; do
        while IFS= read -r line; do
            [[ -e "$DISABLED_MARKER" ]] && continue
            if [[ "$line" == *"RRScreenChangeNotify event"* || "$line" == *"RRNotify event"* ]]; then
                now="$(date +%s%3N)"
                # XRandR pode emitir vários eventos para uma única operação.
                # Debounce sem polling: apenas ignore a rajada por 1500 ms.
                if (( now - last_apply < 1500 )); then
                    continue
                fi
                last_apply="$now"
                sleep 1
                apply_layout
            fi
        done < <(LC_ALL=C xev -root -event randr 2>/dev/null)

        # Reinicie o listener somente se xev morrer inesperadamente.
        sleep 2
    done
}

case "${1:-apply}" in
    apply) apply_layout ;;
    watch) watch_loop ;;
    status) status ;;
    enable) rm -f "$DISABLED_MARKER"; apply_layout ;;
    disable) mkdir -p "$(dirname "$DISABLED_MARKER")"; touch "$DISABLED_MARKER" ;;
    *) echo "Uso: $0 [apply|watch|status|enable|disable]" >&2; exit 2 ;;
esac
XFCE_MM
    chmod 755 /mnt/usr/local/bin/wolf-xfce-multimonitor

    # Whisker: Super abre o menu do monitor do ponteiro, ancorado ao botão.
    cat > /mnt/usr/local/bin/wolf-xfce-whisker-current <<'XFCE_WHISKER'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

# Abre a instância do Whisker pertencente ao monitor onde está o ponteiro,
# sempre ancorada ao BOTÃO do painel. O bool:false é importante: versões
# recentes do Whisker aceitam o parâmetro "popup" com um booleano que define
# se o menu deve nascer no ponteiro (true) ou junto ao applet (false).

command -v xfconf-query >/dev/null 2>&1 || exit 1
command -v xrandr >/dev/null 2>&1 || exit 1
command -v xfce4-panel >/dev/null 2>&1 || exit 1

mouse_x=0
mouse_y=0
if command -v xdotool >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
        case "$key" in
            X) mouse_x="$value" ;;
            Y) mouse_y="$value" ;;
        esac
    done < <(xdotool getmouselocation --shell 2>/dev/null || true)
fi

# Uma única consulta ao RandR por acionamento da tecla.
randr_query="$(xrandr --query 2>/dev/null || true)"
randr_monitors="$(xrandr --listmonitors 2>/dev/null || true)"

point_output=""
while IFS= read -r line; do
    [[ "$line" == *" connected "* ]] || continue
    out="${line%% *}"
    if [[ "$line" =~ ([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) ]]; then
        w="${BASH_REMATCH[1]}"
        h="${BASH_REMATCH[2]}"
        x="${BASH_REMATCH[3]}"
        y="${BASH_REMATCH[4]}"
        if (( mouse_x >= x && mouse_x < x+w && mouse_y >= y && mouse_y < y+h )); then
            point_output="$out"
            break
        fi
    fi
done <<< "$randr_query"

primary_output="$(awk 'NR>1 && /\*/ {print $NF; exit}' <<< "$randr_monitors")"
[[ -n "$primary_output" ]] || primary_output="$(awk '$2=="connected" {print $1; exit}' <<< "$randr_query")"
[[ -n "$point_output" ]] || point_output="$primary_output"

panel_id=""
first_panel=""
while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    [[ -n "$first_panel" ]] || first_panel="$p"
    out="$(xfconf-query -c xfce4-panel -p "/panels/panel-$p/output-name" 2>/dev/null || true)"
    if [[ "$out" == "$point_output" ]]; then
        panel_id="$p"
        break
    fi
    if [[ "$point_output" == "$primary_output" && "$out" == "Automatic" ]]; then
        panel_id="$p"
    fi
done < <(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true)

monitor_count="$(awk 'NR>1 {n++} END {print n+0}' <<< "$randr_monitors")"
if [[ -z "$panel_id" && "$monitor_count" -le 1 ]]; then
    panel_id="$first_panel"
fi

whisker_id=""
if [[ -n "$panel_id" ]]; then
    while IFS= read -r id; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue
        type="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" 2>/dev/null || true)"
        if [[ "$type" == "whiskermenu" ]]; then
            whisker_id="$id"
            break
        fi
    done < <(xfconf-query -c xfce4-panel -p "/panels/panel-$panel_id/plugin-ids" 2>/dev/null || true)
fi

if [[ -n "$whisker_id" ]]; then
    # O booleano false força popup junto ao applet, e não sob o ponteiro.
    if xfce4-panel --plugin-event="whiskermenu-${whisker_id}:popup:bool:false" >/dev/null 2>&1; then
        exit 0
    fi

    # Fallback apenas para builds antigos. Nunca use --pointer.
    if command -v xfce4-popup-whiskermenu >/dev/null 2>&1 \
       && xfce4-popup-whiskermenu --instance="$whisker_id" >/dev/null 2>&1; then
        exit 0
    fi
fi

if (( monitor_count <= 1 )) && command -v xfce4-popup-whiskermenu >/dev/null 2>&1; then
    exec xfce4-popup-whiskermenu
fi

printf '[Wolf XFCE Whisker] Não encontrei uma instância do Whisker no monitor %s.\n' \
    "${point_output:-desconhecido}" >&2
exit 1
XFCE_WHISKER
    chmod 755 /mnt/usr/local/bin/wolf-xfce-whisker-current

    # Fallback de posicionamento: aplicações iniciadas pelo Whisker seguem o
    # monitor em que a instância do menu foi aberta.
    cat > /mnt/usr/local/bin/wolf-xfce-whisker-placement <<'XFCE_PLACEMENT'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -u

VERSION="0.2"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}/wolf-linux"
PID_FILE="$RUNTIME_BASE/xfce-whisker-placement.pid"
CONTEXT_FILE="$RUNTIME_BASE/xfce-launch-context.tsv"
CONTEXT_TTL_MS=8000
WHISKER_TTL_MS=6000

log(){ printf '[Wolf XFCE Window Placement] %s\n' "$*"; }
now_ms(){ date +%s%3N; }

monitor_for_point() {
    local px="$1" py="$2" line out w h x y
    while IFS= read -r line; do
        [[ "$line" == *" connected "* ]] || continue
        out="${line%% *}"
        if [[ "$line" =~ ([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) ]]; then
            w="${BASH_REMATCH[1]}"; h="${BASH_REMATCH[2]}"
            x="${BASH_REMATCH[3]}"; y="${BASH_REMATCH[4]}"
            if (( px >= x && px < x+w && py >= y && py < y+h )); then
                printf '%s\t%s\t%s\t%s\t%s\n' "$out" "$x" "$y" "$w" "$h"
                return 0
            fi
        fi
    done < <(xrandr --query 2>/dev/null || true)
    return 1
}

pointer_target() {
    local loc mx=0 my=0 key value
    loc="$(xdotool getmouselocation --shell 2>/dev/null || true)"
    while IFS='=' read -r key value; do
        case "$key" in
            X) mx="$value" ;;
            Y) my="$value" ;;
        esac
    done <<< "$loc"
    [[ "$mx" =~ ^-?[0-9]+$ && "$my" =~ ^-?[0-9]+$ ]] || return 1
    monitor_for_point "$mx" "$my"
}

monitor_for_window() {
    local wid="$1" geometry cx cy key value
    local wx=0 wy=0 ww=0 wh=0
    geometry="$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1
    while IFS='=' read -r key value; do
        case "$key" in
            X) wx="$value" ;;
            Y) wy="$value" ;;
            WIDTH) ww="$value" ;;
            HEIGHT) wh="$value" ;;
        esac
    done <<< "$geometry"
    [[ "$wx" =~ ^-?[0-9]+$ && "$wy" =~ ^-?[0-9]+$ && "$ww" =~ ^[0-9]+$ && "$wh" =~ ^[0-9]+$ ]] || return 1
    cx=$((wx + ww / 2)); cy=$((wy + wh / 2))
    monitor_for_point "$cx" "$cy"
}

window_class() {
    local wid="$1" class
    class="$(xprop -id "$wid" WM_CLASS 2>/dev/null || true)"
    class="${class#*= }"
    printf '%s\n' "$class"
}

is_whisker_window() {
    local wid="$1" class pid cmd name
    [[ "$wid" =~ ^0x[0-9a-fA-F]+$ ]] || return 1

    class="$(window_class "$wid")"
    if [[ "${class,,}" == *wrapper-2.0* ]]; then
        name="$(xprop -id "$wid" _NET_WM_NAME WM_NAME 2>/dev/null || true)"
        if [[ "${name,,}" == *whisker* || "${name,,}" == *'menu whisker'* ]]; then
            return 0
        fi
    fi

    pid="$(xdotool getwindowpid "$((wid))" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]]; then
        cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
        [[ "$cmd" == *wrapper-2.0* && "$cmd" == *whiskermenu* ]] && return 0
    fi
    return 1
}

candidate_window() {
    local wid="$1" class type
    class="$(window_class "$wid")"
    case "${class,,}" in
        *xfce4-panel*|*wrapper-2.0*|*xfdesktop*|*xfce4-notifyd*|*alttab*) return 1 ;;
    esac

    type="$(xprop -id "$wid" _NET_WM_WINDOW_TYPE 2>/dev/null || true)"
    case "$type" in
        *_NET_WM_WINDOW_TYPE_DESKTOP*|*_NET_WM_WINDOW_TYPE_DOCK*|*_NET_WM_WINDOW_TYPE_NOTIFICATION*|*_NET_WM_WINDOW_TYPE_TOOLTIP*|*_NET_WM_WINDOW_TYPE_POPUP_MENU*) return 1 ;;
    esac
    return 0
}

window_matches_expected() {
    local wid="$1" expected="$2" i class
    [[ -z "$expected" ]] && return 0
    for ((i=0; i<10; i++)); do
        class="$(window_class "$wid")"
        if [[ -n "$class" ]] && grep -Eiq "$expected" <<< "$class"; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

window_is_on_target() {
    local wid="$1" tx="$2" ty="$3" tw="$4" th="$5" geometry key value
    local wx=0 wy=0 ww=0 wh=0 cx cy
    geometry="$(xdotool getwindowgeometry --shell "$((wid))" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1
    while IFS='=' read -r key value; do
        case "$key" in
            X) wx="$value" ;;
            Y) wy="$value" ;;
            WIDTH) ww="$value" ;;
            HEIGHT) wh="$value" ;;
        esac
    done <<< "$geometry"
    cx=$((wx + ww / 2)); cy=$((wy + wh / 2))
    (( cx >= tx && cx < tx+tw && cy >= ty && cy < ty+th ))
}

move_window_to_target() {
    local wid="$1" target_x="$2" target_y="$3" target_w="$4" target_h="$5"
    local geometry key value wx=0 wy=0 ww=0 wh=0 cx cy current
    local src_x=0 src_y=0 local_x local_y max_x max_y new_x new_y state
    local was_max_h=0 was_max_v=0 was_fullscreen=0

    geometry="$(xdotool getwindowgeometry --shell "$((wid))" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || return 1
    while IFS='=' read -r key value; do
        case "$key" in
            X) wx="$value" ;;
            Y) wy="$value" ;;
            WIDTH) ww="$value" ;;
            HEIGHT) wh="$value" ;;
        esac
    done <<< "$geometry"
    [[ "$wx" =~ ^-?[0-9]+$ && "$wy" =~ ^-?[0-9]+$ && "$ww" =~ ^[0-9]+$ && "$wh" =~ ^[0-9]+$ ]] || return 1

    cx=$((wx + ww / 2)); cy=$((wy + wh / 2))
    if (( cx >= target_x && cx < target_x+target_w && cy >= target_y && cy < target_y+target_h )); then
        return 0
    fi

    current="$(monitor_for_point "$cx" "$cy" 2>/dev/null || true)"
    if [[ -n "$current" ]]; then
        IFS=$'\t' read -r _ src_x src_y _ _ <<< "$current"
    fi

    local_x=$((wx - src_x)); local_y=$((wy - src_y))
    (( local_x < 0 )) && local_x=0
    (( local_y < 0 )) && local_y=0
    max_x=$((target_w - ww)); max_y=$((target_h - wh))
    (( max_x < 0 )) && max_x=0
    (( max_y < 0 )) && max_y=0
    (( local_x > max_x )) && local_x="$max_x"
    (( local_y > max_y )) && local_y="$max_y"
    new_x=$((target_x + local_x)); new_y=$((target_y + local_y))

    state="$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null || true)"
    [[ "$state" == *_NET_WM_STATE_MAXIMIZED_HORZ* ]] && was_max_h=1
    [[ "$state" == *_NET_WM_STATE_MAXIMIZED_VERT* ]] && was_max_v=1
    [[ "$state" == *_NET_WM_STATE_FULLSCREEN* ]] && was_fullscreen=1

    if (( was_max_h || was_max_v || was_fullscreen )); then
        wmctrl -ir "$wid" -b remove,fullscreen,maximized_vert,maximized_horz >/dev/null 2>&1 || true
        sleep 0.04
    fi

    xdotool windowmove --sync "$((wid))" "$new_x" "$new_y" >/dev/null 2>&1 || return 1

    if (( was_max_h )); then wmctrl -ir "$wid" -b add,maximized_horz >/dev/null 2>&1 || true; fi
    if (( was_max_v )); then wmctrl -ir "$wid" -b add,maximized_vert >/dev/null 2>&1 || true; fi
    if (( was_fullscreen )); then wmctrl -ir "$wid" -b add,fullscreen >/dev/null 2>&1 || true; fi
    return 0
}

settle_and_move() {
    local wid="$1" tx="$2" ty="$3" tw="$4" th="$5"
    # O Chromium pode restaurar a geometria gravada alguns instantes depois de
    # mapear a janela. Trabalhamos apenas quando uma janela realmente surge:
    # não existe polling contínuo aqui.
    sleep 0.18
    move_window_to_target "$wid" "$tx" "$ty" "$tw" "$th" || true
    sleep 0.65
    if ! window_is_on_target "$wid" "$tx" "$ty" "$tw" "$th"; then
        move_window_to_target "$wid" "$tx" "$ty" "$tw" "$th" || true
    fi
}

arm_context() {
    local expected="${1:-}" target out x y w h expiry tmp
    command -v xdotool >/dev/null 2>&1 || return 1
    command -v xrandr >/dev/null 2>&1 || return 1
    target="$(pointer_target 2>/dev/null || true)"
    [[ -n "$target" ]] || return 1
    IFS=$'\t' read -r out x y w h <<< "$target"
    expiry=$(( $(now_ms) + CONTEXT_TTL_MS ))
    mkdir -p "$RUNTIME_BASE"
    tmp="$CONTEXT_FILE.$$"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$expiry" "$out" "$x" "$y" "$w" "$h" "$expected" > "$tmp"
    mv -f "$tmp" "$CONTEXT_FILE"
}

read_context() {
    CTX_EXPIRY=0; CTX_X=0; CTX_Y=0; CTX_W=0; CTX_H=0; CTX_EXPECTED=""
    [[ -r "$CONTEXT_FILE" ]] || return 1
    IFS=$'\t' read -r CTX_EXPIRY _ CTX_X CTX_Y CTX_W CTX_H CTX_EXPECTED < "$CONTEXT_FILE" || return 1
    if [[ ! "$CTX_EXPIRY" =~ ^[0-9]+$ ]] || (( $(now_ms) >= CTX_EXPIRY )); then
        rm -f "$CONTEXT_FILE"
        return 1
    fi
    return 0
}

consume_context() { rm -f "$CONTEXT_FILE"; }

parse_client_ids() {
    local line="$1" payload token
    local -a tokens=()
    payload="${line#*#}"
    payload="${payload//,/ }"
    read -r -a tokens <<< "$payload"
    for token in "${tokens[@]}"; do
        if [[ "$token" =~ ^0x[0-9a-fA-F]+$ ]]; then
            printf '%s\n' "${token,,}"
        fi
    done
}

initial_clients() {
    local line
    line="$(xprop -root _NET_CLIENT_LIST 2>/dev/null || true)"
    parse_client_ids "$line"
}

handle_explicit_active() {
    local wid="$1"
    read_context || return 1
    candidate_window "$wid" || return 1
    window_matches_expected "$wid" "$CTX_EXPECTED" || return 1
    settle_and_move "$wid" "$CTX_X" "$CTX_Y" "$CTX_W" "$CTX_H"
    consume_context
    return 0
}

daemon_loop() {
    command -v xdotool >/dev/null 2>&1 || exit 0
    command -v xrandr >/dev/null 2>&1 || exit 0
    command -v wmctrl >/dev/null 2>&1 || exit 0
    command -v xprop >/dev/null 2>&1 || exit 0

    mkdir -p "$RUNTIME_BASE"
    if [[ -r "$PID_FILE" ]]; then
        local old_pid
        old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            exit 0
        fi
    fi
    printf '%s\n' "$$" > "$PID_FILE"

    trap 'pkill -P "$$" -x xprop >/dev/null 2>&1 || true; rm -f "$PID_FILE"' EXIT
    trap 'exit 0' INT TERM

    local whisker_until=0 target_out="" target_x=0 target_y=0 target_w=0 target_h=0
    local line wid target now id active
    declare -A seen=() current=()

    while IFS= read -r id; do seen["${id,,}"]=1; done < <(initial_clients)

    while true; do
        while IFS= read -r line; do
            if [[ "$line" == _NET_ACTIVE_WINDOW* ]]; then
                active="$(grep -Eo '0x[0-9a-fA-F]+' <<< "$line" | tail -n1 || true)"
                [[ "$active" =~ ^0x[0-9a-fA-F]+$ && "$active" != 0x0 ]] || continue
                active="${active,,}"

                if is_whisker_window "$active"; then
                    target="$(monitor_for_window "$((active))" 2>/dev/null || true)"
                    if [[ -n "$target" ]]; then
                        IFS=$'\t' read -r target_out target_x target_y target_w target_h <<< "$target"
                        whisker_until=$(( $(now_ms) + WHISKER_TTL_MS ))
                    fi
                else
                    # Contextos explícitos vêm dos launchers Wolf (Chrome,
                    # Terminal, Home). Isso também cobre um app já existente
                    # que é apenas reativado e não cria um novo client X11.
                    handle_explicit_active "$active" || true
                fi
                continue
            fi

            [[ "$line" == _NET_CLIENT_LIST* ]] || continue
            current=()
            while IFS= read -r id; do
                [[ -n "$id" ]] && current["$id"]=1
            done < <(parse_client_ids "$line")

            for id in "${!current[@]}"; do
                [[ -n "${seen[$id]:-}" ]] && continue

                if is_whisker_window "$id"; then
                    target="$(monitor_for_window "$((id))" 2>/dev/null || true)"
                    if [[ -n "$target" ]]; then
                        IFS=$'\t' read -r target_out target_x target_y target_w target_h <<< "$target"
                        whisker_until=$(( $(now_ms) + WHISKER_TTL_MS ))
                    fi
                    continue
                fi

                candidate_window "$id" || continue

                if read_context && window_matches_expected "$id" "$CTX_EXPECTED"; then
                    settle_and_move "$id" "$CTX_X" "$CTX_Y" "$CTX_W" "$CTX_H"
                    consume_context
                    continue
                fi

                now="$(now_ms)"
                if (( whisker_until > now )) && [[ -n "$target_out" ]]; then
                    settle_and_move "$id" "$target_x" "$target_y" "$target_w" "$target_h"
                    # O contexto do Whisker vale somente para a primeira nova
                    # janela. Evite capturar abas destacadas/diálogos depois.
                    whisker_until=0
                    target_out=""
                fi
            done

            seen=()
            for id in "${!current[@]}"; do seen["$id"]=1; done
        done < <(LC_ALL=C xprop -root -spy _NET_CLIENT_LIST _NET_ACTIVE_WINDOW 2>/dev/null)

        # xprop só deve sair se a sessão X estiver encerrando ou por erro.
        # Em erro transitório, reinicie o listener sem criar um loop agressivo.
        sleep 2
    done
}

start_daemon() {
    mkdir -p "$RUNTIME_BASE"
    if [[ -r "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then return 0; fi
    fi
    nohup "$0" daemon >/dev/null 2>&1 &
}

stop_daemon() {
    local pid=""
    [[ -r "$PID_FILE" ]] && pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE" "$CONTEXT_FILE"
}

status_daemon() {
    printf 'Wolf XFCE Window Placement v%s\n' "$VERSION"
    printf 'Modo: orientado a eventos (_NET_CLIENT_LIST/_NET_ACTIVE_WINDOW); sem polling do mouse\n'
    printf 'Whisker: novas janelas seguem o monitor onde o menu foi aberto\n'
    printf 'Launchers Wolf: seguem o monitor do ponteiro no momento do clique\n'
    if [[ -r "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            printf 'Processo: ativo (PID %s)\n' "$pid"
            return 0
        fi
    fi
    printf 'Processo: parado\n'
    return 1
}

case "${1:-start}" in
    daemon) daemon_loop ;;
    start) start_daemon ;;
    stop) stop_daemon ;;
    restart) stop_daemon; start_daemon ;;
    status) status_daemon ;;
    arm) shift; arm_context "${1:-}" ;;
    *) echo "Uso: $0 {start|stop|restart|status|daemon|arm [regex-classe]}" >&2; exit 2 ;;
esac
XFCE_PLACEMENT
    chmod 755 /mnt/usr/local/bin/wolf-xfce-whisker-placement

    cat > /mnt/usr/local/bin/wolf-xfce-launch-here <<'XFCE_LAUNCH_HERE'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

profile="${1:-}"
[[ -n "$profile" ]] || { echo "Uso: $0 {browser|home|terminal|command} [args...]" >&2; exit 2; }
shift || true

arm() {
    local expected="$1"
    if [[ -x /usr/local/bin/wolf-xfce-whisker-placement ]]; then
        /usr/local/bin/wolf-xfce-whisker-placement arm "$expected" >/dev/null 2>&1 || true
    fi
}

case "$profile" in
    browser)
        arm 'google-chrome|Google-chrome|chrome'
        exec /usr/bin/google-chrome-stable "$@"
        ;;
    home)
        arm 'Thunar|thunar'
        exec /usr/bin/thunar "$@"
        ;;
    terminal)
        arm 'xfce4-terminal|Xfce4-terminal'
        exec /usr/bin/xfce4-terminal "$@"
        ;;
    command)
        expected="${1:-}"
        [[ -n "$expected" ]] || { echo "Uso: $0 command <regex-classe> <comando> [args...]" >&2; exit 2; }
        shift
        (($# > 0)) || { echo "Comando ausente." >&2; exit 2; }
        arm "$expected"
        exec "$@"
        ;;
    *)
        echo "Perfil desconhecido: $profile" >&2
        exit 2
        ;;
esac
XFCE_LAUNCH_HERE
    chmod 755 /mnt/usr/local/bin/wolf-xfce-launch-here

    # MIME/helpers específicos do XFCE.
    cat > /mnt/usr/local/bin/wolf-xfce-default-apps <<'XFCE_DEFAULTS'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in *XFCE*|*Xfce*) ;; *) exit 0 ;; esac

set_default() {
    local desktop="$1"; shift
    [[ -r "/usr/share/applications/$desktop" ]] || return 0
    local mime
    for mime in "$@"; do
        [[ -n "$mime" ]] || continue
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
        if command -v gio >/dev/null 2>&1; then
            gio mime "$mime" "$desktop" >/dev/null 2>&1 || true
        fi
    done
}

set_from_desktop() {
    local desktop="$1" filter="${2:-}" prefix=""
    [[ -r "/usr/share/applications/$desktop" ]] || return 0

    if [[ -n "$filter" && "${filter: -2}" == '/*' ]]; then
        prefix="${filter::-1}"
    fi

    while IFS= read -r mime; do
        [[ -n "$mime" ]] || continue
        if [[ -n "$filter" ]]; then
            if [[ -n "$prefix" ]]; then
                [[ "$mime" == "$prefix"* ]] || continue
            else
                [[ "$mime" == "$filter" ]] || continue
            fi
        fi
        set_default "$desktop" "$mime"
    done < <(sed -n 's/^MimeType=//p' "/usr/share/applications/$desktop" | tr ';' '\n' | sed '/^$/d')
}

# Helpers nativos do XFCE.
mkdir -p "$HOME/.config/xfce4"
cat > "$HOME/.config/xfce4/helpers.rc" <<'HELPERS'
WebBrowser=custom-WebBrowser
FileManager=Thunar
TerminalEmulator=xfce4-terminal
HELPERS

mkdir -p "$HOME/.local/share/xfce4/helpers"
cat > "$HOME/.local/share/xfce4/helpers/custom-WebBrowser.desktop" <<'BROWSER'
[Desktop Entry]
NoDisplay=true
Version=1.0
Encoding=UTF-8
Type=X-XFCE-Helper
X-XFCE-Category=WebBrowser
X-XFCE-CommandsWithParameter=/usr/bin/google-chrome-stable "%s"
Icon=google-chrome
Name=Google Chrome
X-XFCE-Commands=/usr/bin/google-chrome-stable
BROWSER

# Pastas.
set_default thunar.desktop inode/directory

# Web.
set_default google-chrome.desktop \
    text/html application/xhtml+xml \
    x-scheme-handler/http x-scheme-handler/https \
    x-scheme-handler/about x-scheme-handler/unknown

# Imagens: usa todos os MIME types anunciados pelo Ristretto.
set_from_desktop org.xfce.ristretto.desktop 'image/*'
set_default org.xfce.ristretto.desktop \
    image/jpeg image/png image/gif image/webp image/bmp image/tiff image/svg+xml image/avif image/heif image/heic

# PDFs/documentos de leitura.
set_from_desktop xreader.desktop
set_default xreader.desktop application/pdf application/postscript application/epub+zip application/x-cbr application/x-cbz

# Texto/código simples.
set_from_desktop org.xfce.mousepad.desktop 'text/*'
set_default org.xfce.mousepad.desktop application/json application/xml application/x-shellscript

# Vídeo e áudio.
set_from_desktop io.github.mpc_qt.mpc-qt.desktop 'video/*'
set_default io.github.mpc_qt.mpc-qt.desktop application/x-matroska
set_from_desktop audacious.desktop 'audio/*'
set_default audacious.desktop application/xspf+xml

# Compactados.
set_from_desktop xarchiver.desktop

# Torrents/magnet.
set_from_desktop transmission-qt.desktop
set_default transmission-qt.desktop application/x-bittorrent x-scheme-handler/magnet

# Escritório.
set_from_desktop libreoffice-writer.desktop
set_from_desktop libreoffice-calc.desktop
set_from_desktop libreoffice-impress.desktop

# LibreOffice anuncia text/plain entre os MIME types possíveis. Como o bloco
# de escritório roda depois do Mousepad, reafirme explicitamente o editor de
# texto simples por último para que .txt nunca caia no Writer.
set_default org.xfce.mousepad.desktop text/plain

# Reforça navegador padrão também pela API do xdg-settings.
xdg-settings set default-web-browser google-chrome.desktop >/dev/null 2>&1 || true
XFCE_DEFAULTS
    chmod 755 /mnt/usr/local/bin/wolf-xfce-default-apps

    # Alt+Tab por monitor sob o ponteiro (X11/XRandR).
    cat > /mnt/usr/local/bin/wolf-xfce-alttab <<'XFCE_ALTTAB'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.1"
ALTTAB_ARGS=(-w 1 -d 0 -sc 0 -vp pointer)

log(){ printf '[Wolf XFCE AltTab] %s\n' "$*"; }

set_xfconf() {
    local channel="$1" prop="$2" type="$3" value="$4"
    if xfconf-query -c "$channel" -p "$prop" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$prop" -s "$value" >/dev/null
    else
        xfconf-query -c "$channel" -p "$prop" -n -t "$type" -s "$value" >/dev/null
    fi
}

configure_shortcuts() {
    command -v xfconf-query >/dev/null 2>&1 || {
        log "xfconf-query não encontrado; atalhos não foram alterados."
        return 1
    }

    # O xfwm4 pode restaurar o atalho padrão se a ação cycle_windows_key
    # simplesmente desaparecer. Mantemos as ações em combinações privadas
    # praticamente inalcançáveis e deixamos Alt+Tab/Alt+Shift+Tab vazios.
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/override' bool true
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Primary><Alt><Shift>F23' string cycle_windows_key
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Primary><Alt><Shift>F24' string cycle_reverse_windows_key
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Alt>Tab' string ''
    set_xfconf xfce4-keyboard-shortcuts '/xfwm4/custom/<Alt><Shift>Tab' string ''
}

start_switcher() {
    if ! command -v alttab >/dev/null 2>&1; then
        log "alttab não está instalado; mantendo o Alt+Tab nativo intacto."
        return 1
    fi

    configure_shortcuts

    if pgrep -u "$UID" -x alttab >/dev/null 2>&1; then
        return 0
    fi

    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux"
    mkdir -p "$state_dir"
    nohup alttab "${ALTTAB_ARGS[@]}" >"$state_dir/xfce-alttab.log" 2>&1 &
}

stop_switcher() {
    pkill -u "$UID" -x alttab >/dev/null 2>&1 || true
}

restart_switcher() {
    stop_switcher
    start_switcher
}

status_switcher() {
    printf 'Wolf XFCE AltTab v%s\n' "$VERSION"
    printf 'Modo: workspace atual + monitor sob o ponteiro\n'
    printf 'Argumentos: alttab %s\n' "${ALTTAB_ARGS[*]}"
    if command -v alttab >/dev/null 2>&1; then
        printf 'Binário: %s\n' "$(command -v alttab)"
    else
        printf 'Binário: ausente\n'
    fi
    if pgrep -u "$UID" -x alttab >/dev/null 2>&1; then
        printf 'Processo: ativo\n'
    else
        printf 'Processo: parado\n'
    fi
}

case "${1:-start}" in
    configure) configure_shortcuts ;;
    start) start_switcher ;;
    restart) restart_switcher ;;
    stop) stop_switcher ;;
    status) status_switcher ;;
    *)
        echo "Uso: $0 {configure|start|restart|stop|status}" >&2
        exit 2
        ;;
esac
XFCE_ALTTAB
    chmod 755 /mnt/usr/local/bin/wolf-xfce-alttab

    # Mouse X11/libinput sem aceleração também no XFCE.
    mkdir -p /mnt/etc/X11/xorg.conf.d
    cat > /mnt/etc/X11/xorg.conf.d/50-wolf-mouse-no-accel.conf <<'XFCE_MOUSE_XORG'
Section "InputClass"
    Identifier "Wolf Linux - Mouse sem aceleracao"
    MatchIsPointer "on"
    MatchIsTouchpad "off"
    MatchDriver "libinput"
    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
EndSection
XFCE_MOUSE_XORG

    cat > /mnt/usr/local/bin/wolf-disable-mouse-accel.sh <<'XFCE_MOUSE'
#!/usr/bin/env bash
set -u
sleep 2
command -v xinput >/dev/null 2>&1 || exit 0
while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    props="$(xinput list-props "$id" 2>/dev/null || true)"
    grep -q 'libinput Tapping Enabled' <<<"$props" && continue
    line="$(grep -m1 'libinput Accel Profile Enabled (' <<<"$props" || true)"
    values="${line##*:}"; values="$(tr -d '[:space:]' <<<"$values")"
    case "$values" in
        *,*,*) xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 0 >/dev/null 2>&1 || true ;;
        *,*)   xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 >/dev/null 2>&1 || true ;;
    esac
    if grep -q 'libinput Accel Speed' <<<"$props"; then
        xinput set-prop "$id" 'libinput Accel Speed' 0 >/dev/null 2>&1 || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
XFCE_MOUSE
    chmod 755 /mnt/usr/local/bin/wolf-disable-mouse-accel.sh

    cat > /mnt/etc/xdg/autostart/wolf-xfce-mouse-flat.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Mouse sem aceleração
Exec=/usr/local/bin/wolf-disable-mouse-accel.sh
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/etc/xdg/autostart/wolf-xfce-default-apps.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Aplicativos padrão XFCE
Exec=sh -c 'sleep 7; /usr/local/bin/wolf-xfce-default-apps'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/etc/xdg/autostart/wolf-xfce-desktop-setup.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - XFCE Desktop Setup
Exec=sh -c 'sleep 5; /usr/local/bin/wolf-xfce-desktop-setup apply'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/etc/xdg/autostart/wolf-xfce-multimonitor.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - XFCE MultiMonitor
Exec=sh -c 'sleep 8; /usr/local/bin/wolf-xfce-multimonitor watch'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/etc/xdg/autostart/wolf-xfce-alttab.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Alt+Tab por monitor
Exec=sh -c 'sleep 6; /usr/local/bin/wolf-xfce-alttab start'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/etc/xdg/autostart/wolf-xfce-whisker-placement.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Posicionamento de janelas por contexto
Exec=sh -c 'sleep 6; /usr/local/bin/wolf-xfce-whisker-placement start'
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/usr/local/bin/wolf-xfce-super-setup <<'XFCE_SUPER_SETUP'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in *XFCE*|*Xfce*) ;; *) exit 0 ;; esac

command -v xfconf-query >/dev/null 2>&1 || exit 0
command -v xcape >/dev/null 2>&1 || exit 0

# Sem atraso fixo de vários segundos: espere somente o xfconf ficar pronto.
for _ in {1..20}; do
    if xfconf-query -c xfce4-keyboard-shortcuts -l >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

setcmd() {
    local key="$1" cmd="$2"
    xfconf-query -c xfce4-keyboard-shortcuts \
        -p "/commands/custom/$key" -n -t string -s "$cmd" 2>/dev/null \
        || xfconf-query -c xfce4-keyboard-shortcuts \
            -p "/commands/custom/$key" -s "$cmd" 2>/dev/null || true
}

while IFS= read -r prop; do
    [[ "$prop" == /commands/custom/* ]] || continue
    value="$(xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" 2>/dev/null || true)"
    if [[ "$prop" == '/commands/custom/<Primary><Alt><Shift>F12' ]]; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
        continue
    fi
    if [[ "$prop" == *Super* && "$value" == *xfce4-popup-whiskermenu* ]]; then
        xfconf-query -c xfce4-keyboard-shortcuts -p "$prop" -r >/dev/null 2>&1 || true
    fi
done < <(xfconf-query -c xfce4-keyboard-shortcuts -l 2>/dev/null || true)

# Autoridade única dos atalhos Wolf no XFCE.
setcmd '<Primary><Alt>t' '/usr/local/bin/wolf-xfce-launch-here terminal'
setcmd '<Super>e' '/usr/local/bin/wolf-xfce-launch-here home'
setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'

pkill -x xcape >/dev/null 2>&1 || true
exec xcape -e 'Super_L=Control_L|Alt_L|Shift_L|F12'

XFCE_SUPER_SETUP
    chmod 755 /mnt/usr/local/bin/wolf-xfce-super-setup

    cat > /mnt/etc/xdg/autostart/wolf-xfce-super-key.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Super abre Whisker por monitor
Exec=/usr/local/bin/wolf-xfce-super-setup
OnlyShowIn=XFCE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # O XFCE tem um setup próprio para estilo/wallpaper, com retry até o
    # xfconfd/xfdesktop estarem prontos. Evita a corrida dos helpers genéricos.
    for desktop_file in         /mnt/etc/xdg/autostart/wolf-first-login-style.desktop         /mnt/etc/xdg/autostart/wolf-first-login-wallpaper.desktop; do
        [[ -f "$desktop_file" ]] || continue
        if grep -q '^NotShowIn=' "$desktop_file"; then
            sed -i '/^NotShowIn=/ s/;*$/;XFCE;/' "$desktop_file"
        else
            printf 'NotShowIn=XFCE;\n' >> "$desktop_file"
        fi
    done

    ok "Perfil XFCE X11-only + Whisker/Alt+Tab/aplicações por monitor + painel Wolf + defaults + MultiMonitor preparado."
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

    # Ícone de distribuição para telas "Sobre o sistema". O campo LOGO do
    # os-release aponta para wolf-linux; distributor-logo cobre aplicativos
    # mais antigos que ainda usam o nome convencional.
    mkdir -p /mnt/usr/share/icons/hicolor/256x256/apps /mnt/usr/share/icons/hicolor/512x512/apps /mnt/usr/share/icons/hicolor/scalable/apps /mnt/usr/share/pixmaps
    cp -f /mnt/usr/share/plymouth/themes/wolf-linux/logo.png \
        /mnt/usr/share/icons/hicolor/256x256/apps/wolf-linux.png
    cp -f /mnt/usr/share/plymouth/themes/wolf-linux/logo.png \
        /mnt/usr/share/pixmaps/wolf-linux.png
    cp -f /mnt/usr/share/plymouth/themes/wolf-linux/logo.png \
        /mnt/usr/share/pixmaps/distributor-logo.png
    fetch_wolf_asset \
        "kde/wolf-linux-kickoff.svg" \
        /mnt/usr/share/icons/hicolor/scalable/apps/wolf-linux-kickoff.svg

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

WALLPAPER="/usr/share/backgrounds/wolf-linux/wallpaper.png"
DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

case "$DESKTOP" in
    *MATE*) DESKTOP_ID="mate" ;;
    *X-Cinnamon*|*Cinnamon*) DESKTOP_ID="cinnamon" ;;
    *KDE*|*Plasma*) DESKTOP_ID="plasma" ;;
    *XFCE*|*Xfce*) DESKTOP_ID="xfce" ;;
    *) exit 0 ;;
esac

MARKER="$HOME/.config/wolf-linux/wallpaper-${DESKTOP_ID}-v2.done"
[[ -f "$MARKER" ]] && exit 0
mkdir -p "$(dirname "$MARKER")"

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
    *XFCE*|*Xfce*)
        if command -v xfconf-query >/dev/null 2>&1; then
            while IFS= read -r prop; do
                xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" 2>/dev/null || true
            done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$' || true)
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

MARKER="$HOME/.config/wolf-linux/default-apps-v6.done"
mkdir -p "$(dirname "$MARKER")"

[[ -f "$MARKER" ]] && exit 0

set_default() {
    local desktop="$1"
    shift
    local mime

    for mime in "$@"; do
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true

        # Cinnamon/GIO consulta GAppInfo diretamente em alguns pontos.
        if command -v gio >/dev/null 2>&1; then
            gio mime "$mime" "$desktop" >/dev/null 2>&1 || true
        fi
    done
}

# Editor de texto simples por ambiente.
DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
TEXT_EDITOR_DESKTOP=""

case "$DESKTOP" in
    *MATE*)
        TEXT_EDITOR_DESKTOP="pluma.desktop"
        ;;
    *X-Cinnamon*|*Cinnamon*)
        TEXT_EDITOR_DESKTOP="org.x.editor.desktop"
        ;;
    *KDE*|*Plasma*)
        TEXT_EDITOR_DESKTOP="org.kde.kate.desktop"
        ;;
    *XFCE*|*Xfce*)
        TEXT_EDITOR_DESKTOP="org.xfce.mousepad.desktop"
        ;;
esac

if [[ -n "$TEXT_EDITOR_DESKTOP" ]] \
   && [[ -f "/usr/share/applications/$TEXT_EDITOR_DESKTOP" ]]; then
    set_default "$TEXT_EDITOR_DESKTOP" \
        text/plain \
        text/markdown \
        text/x-readme \
        text/x-log \
        application/x-shellscript \
        application/json \
        application/xml \
        text/xml \
        text/x-python \
        text/x-csrc \
        text/x-c++src \
        text/x-java \
        text/x-cmake
fi

# Aproveita também todos os MIME types anunciados pelo próprio editor.
# Isso cobre extensões de código-fonte adicionais sem depender de uma lista fixa.
if [[ -n "$TEXT_EDITOR_DESKTOP" ]] \
   && [[ -r "/usr/share/applications/$TEXT_EDITOR_DESKTOP" ]]; then

    while IFS= read -r mime; do
        [[ -n "$mime" ]] || continue
        set_default "$TEXT_EDITOR_DESKTOP" "$mime"
    done < <(
        sed -n 's/^MimeType=//p' "/usr/share/applications/$TEXT_EDITOR_DESKTOP" \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

# Integrações próprias do Cinnamon.
case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*)
        # Xviewer é o visualizador X-Apps equivalente ao Eye of MATE.
        if [[ -r /usr/share/applications/xviewer.desktop ]]; then
            while IFS= read -r mime; do
                [[ "$mime" == image/* ]] || continue
                set_default xviewer.desktop "$mime"
            done < <(
                sed -n 's/^MimeType=//p' /usr/share/applications/xviewer.desktop \
                    | tr ';' '\n' \
                    | sed '/^$/d'
            )
        fi

        # Xarchiver como gerenciador de arquivos compactados.
        if [[ -r /usr/share/applications/xarchiver.desktop ]]; then
            while IFS= read -r mime; do
                [[ -n "$mime" ]] || continue
                set_default xarchiver.desktop "$mime"
            done < <(
                sed -n 's/^MimeType=//p' /usr/share/applications/xarchiver.desktop \
                    | tr ';' '\n' \
                    | sed '/^$/d'
            )
        fi

        # Cinnamon possui uma preferência própria para a calculadora
        # (usada inclusive pela tecla Calculator de alguns teclados).
        if gsettings list-schemas 2>/dev/null \
            | grep -Fxq 'org.cinnamon.desktop.default-applications.calculator'; then

            if gsettings list-keys \
                org.cinnamon.desktop.default-applications.calculator \
                2>/dev/null \
                | grep -Fxq 'exec'; then

                gsettings set \
                    org.cinnamon.desktop.default-applications.calculator \
                    exec \
                    'galculator' \
                    2>/dev/null || true
            fi
        fi
        ;;
esac

# MPC-QT para vídeo.
set_default io.github.mpc_qt.mpc-qt.desktop \
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

# Também aproveita todos os MIME types de vídeo anunciados pelo MPC-QT,
# mas deliberadamente ignora inode/directory. Alguns players anunciam
# diretórios como entrada suportada e não devem substituir o gerenciador
# de arquivos do desktop.
if [[ -r /usr/share/applications/io.github.mpc_qt.mpc-qt.desktop ]]; then
    while IFS= read -r mime; do
        case "$mime" in
            video/*|application/x-matroska)
                set_default io.github.mpc_qt.mpc-qt.desktop "$mime"
                ;;
        esac
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/io.github.mpc_qt.mpc-qt.desktop \
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

    # --------------------------------------------------------
    # Proteção do handler de diretórios.
    #
    # Alguns players (incluindo MPC-QT em determinados cenários) podem
    # registrar inode/directory e acabar assumindo Pasta pessoal/Super+E.
    # Esta política é reaplicada a cada login, sem marker, para manter o
    # gerenciador de arquivos nativo de cada desktop como handler padrão.
    # --------------------------------------------------------
    cat > /mnt/usr/local/bin/wolf-protect-directory-handler <<'EOF'
#!/usr/bin/env bash
set -u

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
FILE_MANAGER_DESKTOP=""

case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*)
        FILE_MANAGER_DESKTOP="nemo.desktop"
        ;;
    *MATE*)
        FILE_MANAGER_DESKTOP="caja.desktop"
        ;;
    *KDE*|*Plasma*)
        FILE_MANAGER_DESKTOP="org.kde.dolphin.desktop"
        ;;
    *XFCE*|*Xfce*)
        FILE_MANAGER_DESKTOP="thunar.desktop"
        ;;
esac

[[ -n "$FILE_MANAGER_DESKTOP" ]] || exit 0
[[ -r "/usr/share/applications/$FILE_MANAGER_DESKTOP" ]] || exit 0

xdg-mime default "$FILE_MANAGER_DESKTOP" inode/directory >/dev/null 2>&1 || true

if command -v gio >/dev/null 2>&1; then
    gio mime inode/directory "$FILE_MANAGER_DESKTOP" >/dev/null 2>&1 || true
fi
EOF
    chmod 755 /mnt/usr/local/bin/wolf-protect-directory-handler

    cat > /mnt/etc/xdg/autostart/wolf-protect-directory-handler.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Proteger gerenciador de arquivos
Comment=Mantém pastas associadas ao gerenciador de arquivos nativo do desktop
Exec=/usr/local/bin/wolf-protect-directory-handler
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/usr/local/bin/wolf-plasma-panel-cleanup.sh <<'EOF'
#!/usr/bin/env bash
set -u

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in
    *KDE*|*Plasma*) ;;
    *) exit 0 ;;
esac

MARKER="$HOME/.config/wolf-linux/plasma-panel-cleanup-v1.done"
CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

[[ -f "$MARKER" ]] && exit 0
mkdir -p "$(dirname "$MARKER")"

for _ in $(seq 1 20); do
    [[ -s "$CONFIG" ]] && break
    sleep 1
done

[[ -s "$CONFIG" ]] || exit 0

cp -n "$CONFIG" "$CONFIG.wolf-backup" 2>/dev/null || true

python - "$CONFIG" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
out = []

for line in lines:
    if line.startswith("launchers="):
        prefix, value = line.split("=", 1)
        items = [item for item in value.split(",") if item]
        items = [item for item in items if "discover" not in item.lower()]
        line = prefix + "=" + ",".join(items)
    out.append(line)

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

if grep -Ei '^launchers=.*discover' "$CONFIG" >/dev/null 2>&1; then
    exit 0
fi

touch "$MARKER"

if systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1; then
    exit 0
fi

if command -v kquitapp6 >/dev/null 2>&1; then
    kquitapp6 plasmashell >/dev/null 2>&1 || true
fi

nohup plasmashell --replace >/dev/null 2>&1 &
disown || true
EOF

    chmod 755 /mnt/usr/local/bin/wolf-plasma-panel-cleanup.sh

    cat > /mnt/etc/xdg/autostart/wolf-plasma-panel-cleanup.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Limpar painel Plasma
Comment=Remove o atalho do Discover do painel padrão
Exec=/usr/local/bin/wolf-plasma-panel-cleanup.sh
OnlyShowIn=KDE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    cat > /mnt/etc/xdg/autostart/wolf-default-apps.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Aplicativos padrão
Comment=Configura MPC-QT, Audacious e preferências de miniaturas
Exec=/usr/local/bin/wolf-apply-default-apps.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # --------------------------------------------------------
    # Integrações específicas do Cinnamon / Nemo.
    # --------------------------------------------------------
    if [[ "$DESKTOP" == "cinnamon" ]]; then
        # ----------------------------------------------------
        # Wolf Linux usa Cinnamon somente em X11.
        #
        # A sessão Wayland é removida do SDDM para evitar seleção acidental
        # e para manter o perfil validado do Wolf Linux consistente:
        # - perfil flat real via libinput/xinput;
        # - Flameshot previsível;
        # - drag-and-drop do Xarchiver;
        # - comportamento mais estável no conjunto Cinnamon/NVIDIA atual.
        #
        # Um hook do pacman reaplica a política após upgrades do Cinnamon,
        # pois o pacote pode recriar os arquivos .desktop de Wayland.
        # ----------------------------------------------------
        install -d /mnt/usr/local/sbin /mnt/etc/pacman.d/hooks

        cat > /mnt/usr/local/sbin/wolf-disable-cinnamon-wayland <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

for entry in /usr/share/wayland-sessions/cinnamon*.desktop; do
    rm -f -- "$entry"
done
EOF
        chmod 755 /mnt/usr/local/sbin/wolf-disable-cinnamon-wayland

        cat > /mnt/etc/pacman.d/hooks/wolf-cinnamon-x11-only.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = cinnamon

[Action]
Description = Wolf Linux: mantendo Cinnamon somente em X11...
When = PostTransaction
Exec = /usr/local/sbin/wolf-disable-cinnamon-wayland
EOF

        arch-chroot /mnt /usr/local/sbin/wolf-disable-cinnamon-wayland

        arch-chroot /mnt install -d -o sddm -g sddm /var/lib/sddm

        cat > /mnt/var/lib/sddm/state.conf <<EOF
[Last]
Session=cinnamon.desktop
User=$USERNAME_VALUE
EOF

        arch-chroot /mnt chown sddm:sddm /var/lib/sddm/state.conf

        # Portal do Cinnamon: XApp primeiro, GTK como fallback e
        # GNOME Keyring explicitamente como Secret provider.
        mkdir -p /mnt/etc/xdg/xdg-desktop-portal

        cat > /mnt/etc/xdg/xdg-desktop-portal/x-cinnamon-portals.conf <<'EOF'
[preferred]
default=xapp;gtk;
org.freedesktop.impl.portal.Settings=xapp;gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
EOF

        # Integração PAM do GNOME Keyring. O SDDM do Arch já fornece estas
        # linhas atualmente; aceitamos tanto a forma nativa com prefixo '-'
        # quanto a forma sem prefixo. Só adicionamos fallback se realmente
        # estiverem ausentes, evitando as duplicatas da versão 1.0.14.
        if [[ -f /mnt/etc/pam.d/sddm ]]; then
            if ! grep -Eq '^-?auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so([[:space:]]|$)' /mnt/etc/pam.d/sddm; then
                printf '\n-auth optional pam_gnome_keyring.so\n' \
                    >> /mnt/etc/pam.d/sddm
            fi

            if ! grep -Eq '^-?session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so[[:space:]]+auto_start([[:space:]]|$)' /mnt/etc/pam.d/sddm; then
                printf '%s\n' '-session optional pam_gnome_keyring.so auto_start' \
                    >> /mnt/etc/pam.d/sddm
            fi
        fi

        if [[ -f /mnt/etc/pam.d/passwd ]] \
           && ! grep -Eq '^-?password[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so([[:space:]]|$)' /mnt/etc/pam.d/passwd; then
            printf '\npassword optional pam_gnome_keyring.so\n' \
                >> /mnt/etc/pam.d/passwd
        fi

        # O pacote Arch do gnome-keyring normalmente inclui Cinnamon em seu
        # autostart nativo. Se isso mudar em uma versão futura, instalamos um
        # fallback global sem OnlyShowIn, evitando que Secret Service deixe de
        # iniciar no Cinnamon. Não iniciamos socket/daemon manualmente.
        rm -f /mnt/etc/xdg/autostart/wolf-gnome-keyring-secrets.desktop
        KEYRING_AUTOSTART=/mnt/etc/xdg/autostart/gnome-keyring-secrets.desktop
        if [[ -r "$KEYRING_AUTOSTART" ]] \
           && ! grep -Eq '^OnlyShowIn=.*Cinnamon' "$KEYRING_AUTOSTART"; then
            cp -f "$KEYRING_AUTOSTART" \
                /mnt/etc/xdg/autostart/wolf-gnome-keyring-secrets.desktop
            sed -i '/^OnlyShowIn=/d' \
                /mnt/etc/xdg/autostart/wolf-gnome-keyring-secrets.desktop
            warn "GNOME Keyring sem Cinnamon no OnlyShowIn; fallback Wolf instalado."
        fi

        # Remove helper/applet legado do CinnVII. Cinnamon 6.6+ usa o menu
        # nativo menu@cinnamon.org, que já suporta ícone/rótulo customizados.
        rm -f /mnt/usr/local/bin/wolf-cinnvii-hotkey-fix

        # ----------------------------------------------------
        # Cinnamon 6.6+: menu nativo como padrão Wolf Linux.
        #
        # O antigo CinnVII é legado e não é mais instalado/forçado. O menu
        # nativo menu@cinnamon.org suporta ícone/rótulo customizáveis e evita
        # incompatibilidades de applet no primeiro login.
        # ----------------------------------------------------
        rm -rf "/mnt/home/$USERNAME_VALUE/.local/share/cinnamon/applets/CinnVIIStarkMenu@NikoKrause" 2>/dev/null || true

        # ----------------------------------------------------
        # Wolf MultiMonitor — painéis independentes por monitor.
        #
        # O watcher roda apenas no Cinnamon X11. Ele reconcilia a topologia
        # no login e observa hotplug por XRandR: quando uma nova tela surge,
        # cria apenas o painel/applications list que estiver faltando.
        # Painéis de telas removidas NÃO são apagados automaticamente, para
        # preservar personalizações em monitores temporariamente desconectados.
        # ----------------------------------------------------
        mkdir -p /mnt/usr/local/bin /mnt/etc/xdg/autostart

        cat > /mnt/usr/local/bin/wolf-cinnamon-multimonitor <<'WOLF_MULTIMONITOR_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.6"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/cinnamon-multimonitor"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux"
DISABLED_MARKER="$CONFIG_ROOT/cinnamon-multimonitor.disabled"
INITIAL_MARKER="$CONFIG_ROOT/cinnamon-layout-v2.done"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/wolf-cinnamon-multimonitor-${UID}.pid"
LOG_FILE="$STATE_ROOT/watch.log"
MENU_UUID="menu@cinnamon.org"
MENU_CONFIG_ROOT="$HOME/.config/cinnamon/spices/$MENU_UUID"
LOGO="/usr/share/pixmaps/wolf-linux.png"

log()  { printf '[Wolf Cinnamon MultiMonitor] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

check_environment() {
    case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
        *X-Cinnamon*|*Cinnamon*) ;;
        *) die "Este helper é somente para Cinnamon." ;;
    esac
    [[ "${XDG_SESSION_TYPE:-x11}" == "x11" ]] || die "Esta versão é para Cinnamon X11."
    need_cmd gsettings
    need_cmd xrandr
    need_cmd xev
    need_cmd python3
}

wait_cinnamon_ready() {
    local _
    for _ in {1..40}; do
        if gsettings get org.cinnamon panels-enabled >/dev/null 2>&1 \
           && pgrep -x cinnamon >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

monitor_lines() {
    xrandr --listmonitors 2>/dev/null | tail -n +2
}

make_backup() {
    mkdir -p "$STATE_ROOT"
    local stamp dir
    stamp="$(date +%Y%m%d-%H%M%S)"
    dir="$STATE_ROOT/$stamp"
    mkdir -p "$dir"
    gsettings get org.cinnamon panels-enabled > "$dir/panels-enabled.txt"
    gsettings get org.cinnamon enabled-applets > "$dir/enabled-applets.txt"
    gsettings get org.cinnamon next-applet-id > "$dir/next-applet-id.txt"
    [[ -d "$HOME/.config/cinnamon/spices" ]] && cp -a "$HOME/.config/cinnamon/spices" "$dir/spices"
    printf '%s\n' "$dir" > "$STATE_ROOT/latest"
    ok "Backup salvo em $dir"
}

ensure_baseline_backup() {
    local marker="$STATE_ROOT/automatic-baseline"
    [[ -f "$marker" ]] && return 0
    make_backup
    cp "$STATE_ROOT/latest" "$marker"
}

brand_native_menu_instances() {
    [[ -f "$LOGO" ]] || return 0
    mkdir -p "$MENU_CONFIG_ROOT"

    python3 - "$MENU_CONFIG_ROOT" "$LOGO" <<'PY'
import ast
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
logo = sys.argv[2]
raw = subprocess.check_output(["gsettings", "get", "org.cinnamon", "enabled-applets"], text=True).strip()
try:
    items = ast.literal_eval(raw)
except Exception:
    raise SystemExit(0)

ids = []
for item in items:
    parts = item.split(":")
    if len(parts) >= 5 and parts[3] == "menu@cinnamon.org":
        try:
            ids.append(int(parts[4]))
        except ValueError:
            pass

schema_path = pathlib.Path("/usr/share/cinnamon/applets/menu@cinnamon.org/settings-schema.json")
try:
    schema = json.loads(schema_path.read_text())
except Exception:
    schema = None

for instance_id in sorted(set(ids)):
    path = root / f"{instance_id}.json"
    if path.exists():
        try:
            data = json.loads(path.read_text())
        except Exception:
            data = None
    else:
        data = None

    if not isinstance(data, dict):
        if not isinstance(schema, dict):
            continue
        data = json.loads(json.dumps(schema))

    for key, value in (("menu-custom", True), ("menu-icon", logo), ("menu-label", "")):
        entry = data.get(key)
        if isinstance(entry, dict):
            entry["value"] = value
        else:
            data[key] = {"value": value}

    path.write_text(json.dumps(data, ensure_ascii=False, indent=4) + "\n")
PY
}

reconcile_cinnamon() {
    check_environment
    wait_cinnamon_ready || die "Cinnamon ainda não ficou pronto para configurar os painéis."

    local ids_file
    ids_file="$(mktemp)"

    python3 - "$ids_file" <<'PY'
import ast
import subprocess
import sys

MENU = "menu@cinnamon.org"
LEGACY = "CinnVIIStarkMenu@NikoKrause"
IDS_FILE = sys.argv[1]

def gget(key):
    return subprocess.check_output(["gsettings", "get", "org.cinnamon", key], text=True).strip()

def gset(key, value):
    subprocess.run(["gsettings", "set", "org.cinnamon", key, value], check=True)

def gv(items):
    def esc(s):
        return s.replace("\\", "\\\\").replace("'", "\\'")
    return "[" + ", ".join("'" + esc(x) + "'" for x in items) + "]"

def parse(item):
    parts = item.split(":")
    if len(parts) < 4 or not parts[0].startswith("panel"):
        return None
    try:
        panel_id = int(parts[0][5:])
        pos = int(parts[2])
    except ValueError:
        return None
    instance = None
    if len(parts) >= 5:
        try:
            instance = int(parts[-1])
        except ValueError:
            instance = None
    uuid = ":".join(parts[3:-1]) if len(parts) >= 5 else parts[3]
    return {"panel": panel_id, "zone": parts[1], "pos": pos, "uuid": uuid, "instance": instance}

mons = []
for line in subprocess.check_output(["xrandr", "--listmonitors"], text=True).splitlines()[1:]:
    try:
        mons.append(int(line.strip().split(":", 1)[0]))
    except Exception:
        pass
if not mons:
    raise SystemExit("nenhum monitor ativo")

try:
    panels = ast.literal_eval(gget("panels-enabled"))
except Exception:
    panels = []
try:
    applets = ast.literal_eval(gget("enabled-applets"))
except Exception:
    applets = []
try:
    next_id = int(gget("next-applet-id"))
except Exception:
    next_id = 0

if not isinstance(panels, list):
    panels = []
if not isinstance(applets, list):
    applets = []

# Normaliza IDs já existentes e calcula o próximo ID seguro.
max_instance = -1
normalized = []
for item in applets:
    e = parse(item)
    if not e:
        continue
    if e["instance"] is None:
        e["instance"] = max(next_id, max_instance + 1)
        next_id = e["instance"] + 1
    max_instance = max(max_instance, e["instance"])
    uuid = MENU if e["uuid"] == LEGACY else e["uuid"]
    normalized.append(f"panel{e['panel']}:{e['zone']}:{e['pos']}:{uuid}:{e['instance']}")
applets = normalized
next_id = max(next_id, max_instance + 1)

# Se algum estado anterior deixou o painel inválido, volta ao painel base seguro.
valid_panels = []
for definition in panels:
    try:
        pid_s, mon_s, position = definition.split(":", 2)
        pid, mon = int(pid_s), int(mon_s)
    except Exception:
        continue
    if position not in ("top", "bottom", "left", "right"):
        continue
    valid_panels.append((pid, mon, position))

if not valid_panels:
    valid_panels = [(1, mons[0], "bottom")]

panels = [f"{pid}:{mon}:{pos}" for pid, mon, pos in valid_panels]
panel_by_monitor = {mon: pid for pid, mon, _pos in valid_panels}
max_panel = max(pid for pid, _mon, _pos in valid_panels)
new_panels = []
for mon in mons:
    if mon in panel_by_monitor:
        continue
    max_panel += 1
    panels.append(f"{max_panel}:{mon}:bottom")
    panel_by_monitor[mon] = max_panel
    new_panels.append(max_panel)

new_menu_ids = []

def entries(panel):
    out = []
    for i, item in enumerate(applets):
        e = parse(item)
        if e and e["panel"] == panel:
            out.append((i, e))
    return out

def add(panel, zone, pos, uuid):
    global next_id
    instance = next_id
    next_id += 1
    applets.append(f"panel{panel}:{zone}:{pos}:{uuid}:{instance}")
    return instance

for mon in mons:
    panel = panel_by_monitor[mon]
    es = entries(panel)
    if not any(e["uuid"] == MENU for _i, e in es):
        new_menu_ids.append(add(panel, "left", 0, MENU))

    es = entries(panel)
    if not any(e["uuid"] == "grouped-window-list@cinnamon.org" for _i, e in es):
        add(panel, "left", 99, "grouped-window-list@cinnamon.org")

    if panel in new_panels:
        es = entries(panel)
        if not any(e["uuid"] == "calendar@cinnamon.org" for _i, e in es):
            add(panel, "right", 0, "calendar@cinnamon.org")

# Remove apenas CinnVII remanescente e menus nativos duplicados no mesmo painel.
seen_menu_panels = set()
clean = []
for item in applets:
    e = parse(item)
    if not e:
        continue
    if e["uuid"] == LEGACY:
        continue
    if e["uuid"] == MENU:
        if e["panel"] in seen_menu_panels:
            continue
        seen_menu_panels.add(e["panel"])
    clean.append(item)
applets = clean

gset("panels-enabled", gv(panels))
gset("enabled-applets", gv(applets))
gset("next-applet-id", str(next_id))

with open(IDS_FILE, "w", encoding="utf-8") as f:
    for instance in new_menu_ids:
        f.write(f"{instance}\n")
PY

    brand_native_menu_instances
    rm -f "$ids_file"

    # Lista de janelas e Alt+Tab locais ao monitor.
    python3 - "$HOME/.cinnamon/configs/grouped-window-list@cinnamon.org" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
if root.exists():
    for path in root.glob("*.json"):
        try:
            data = json.loads(path.read_text())
        except Exception:
            continue
        entry = data.get("window-display-settings")
        if isinstance(entry, dict):
            entry["value"] = 1
            path.write_text(json.dumps(data, ensure_ascii=False, indent=4) + "\n")
PY

    gsettings set org.cinnamon alttab-switcher-show-current-monitor true 2>/dev/null || true
    gsettings set org.cinnamon alttab-switcher-enforce-primary-monitor false 2>/dev/null || true
}

initial_setup() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    wait_cinnamon_ready || die "Cinnamon não ficou pronto a tempo."
    [[ -f "$INITIAL_MARKER" ]] && return 0
    make_backup
    reconcile_cinnamon
    : > "$INITIAL_MARKER"
    ok "Layout inicial Cinnamon configurado com applets nativos."
}

show_state() {
    check_environment
    echo "Wolf Cinnamon MultiMonitor v${VERSION}"
    echo "panels-enabled:"
    gsettings get org.cinnamon panels-enabled
    echo "enabled-applets:"
    gsettings get org.cinnamon enabled-applets
    echo "monitores:"
    monitor_lines
    if [[ -f "$PID_FILE" ]]; then
        echo "watcher PID: $(cat "$PID_FILE" 2>/dev/null || true)"
    else
        echo "watcher: inativo"
    fi
}

stop_watcher() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
}

disable_automatic() {
    mkdir -p "$CONFIG_ROOT"
    : > "$DISABLED_MARKER"
    stop_watcher
    ok "Watcher Cinnamon desativado; painéis preservados."
}

enable_automatic() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    rm -f "$DISABLED_MARKER"
    stop_watcher
    nohup "$0" watch >/dev/null 2>&1 &
    ok "Watcher event-driven ativado."
}

watch_loop() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    [[ ! -e "$DISABLED_MARKER" ]] || exit 0

    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
            exit 0
        fi
    fi
    printf '%s\n' "$$" > "$PID_FILE"
    trap 'rm -f "$PID_FILE"' EXIT INT TERM

    exec >>"$LOG_FILE" 2>&1
    echo "[$(date '+%F %T')] watcher v${VERSION} event-driven iniciado"

    local last_event=0 now
    while IFS= read -r line; do
        [[ ! -e "$DISABLED_MARKER" ]] || exit 0
        case "$line" in
            *RRScreenChangeNotify*|*RRNotify*)
                now="$(date +%s)"
                if (( now - last_event < 2 )); then
                    continue
                fi
                last_event="$now"
                sleep 1
                ensure_baseline_backup || true
                if reconcile_cinnamon; then
                    echo "[$(date '+%F %T')] evento RandR reconciliado"
                else
                    echo "[$(date '+%F %T')] falha na reconciliação após evento RandR"
                fi
                ;;
        esac
    done < <(xev -root -event randr 2>/dev/null)
}

restore_latest() {
    check_environment
    [[ -f "$STATE_ROOT/latest" ]] || die "Nenhum backup encontrado."
    local dir
    dir="$(cat "$STATE_ROOT/latest")"
    [[ -d "$dir" ]] || die "Backup inválido: $dir"
    gsettings set org.cinnamon panels-enabled "$(cat "$dir/panels-enabled.txt")"
    gsettings set org.cinnamon enabled-applets "$(cat "$dir/enabled-applets.txt")"
    gsettings set org.cinnamon next-applet-id "$(cat "$dir/next-applet-id.txt")"
    ok "Configuração restaurada."
}

usage() {
    cat <<EOF2
Uso: $(basename "$0") {status|initial|reconcile|watch|enable|disable|restore}
EOF2
}

case "${1:-status}" in
    status) show_state ;;
    initial) initial_setup ;;
    reconcile) reconcile_cinnamon ;;
    watch) watch_loop ;;
    enable) enable_automatic ;;
    disable) disable_automatic ;;
    restore) restore_latest ;;
    *) usage; exit 2 ;;
esac
WOLF_MULTIMONITOR_SCRIPT
        chmod 755 /mnt/usr/local/bin/wolf-cinnamon-multimonitor

        cat > /mnt/etc/xdg/autostart/wolf-cinnamon-multimonitor.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux MultiMonitor
Comment=Painel, menu, janelas e Alt+Tab independentes em cada monitor Cinnamon
Exec=/usr/local/bin/wolf-cinnamon-multimonitor watch
OnlyShowIn=X-Cinnamon;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

        # Xorg/libinput: mouse sem aceleração para a sessão X11.
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

        cat > /mnt/usr/local/bin/wolf-cinnamon-session-setup.sh <<'EOF'
#!/usr/bin/env bash
set -u

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*) ;;
    *) exit 0 ;;
esac

# Cinnamon 6.6 inicia os autostarts muito cedo. Esperamos apenas durante
# a configuração da sessão; não há polling permanente.
ready=0
for _ in {1..40}; do
    if pgrep -x cinnamon >/dev/null 2>&1 \
       && gsettings get org.cinnamon panels-enabled >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 0.25
done

(( ready == 1 )) || exit 0

# Aparência e wallpaper são aplicados de forma idempotente por desktop.
if [[ -x /usr/local/bin/wolf-apply-desktop-style.sh ]]; then
    /usr/local/bin/wolf-apply-desktop-style.sh || true
fi
if [[ -x /usr/local/bin/wolf-apply-wallpaper.sh ]]; then
    /usr/local/bin/wolf-apply-wallpaper.sh || true
fi

# O Cinnamon 6.6 possui menu nativo com ícone/rótulo customizáveis.
# Não substituímos mais menu@cinnamon.org pelo CinnVII legado.
if [[ -x /usr/local/bin/wolf-cinnamon-multimonitor ]]; then
    /usr/local/bin/wolf-cinnamon-multimonitor initial || true
fi
if [[ -x /usr/local/bin/wolf-desktop-branding ]]; then
    /usr/local/bin/wolf-desktop-branding --force || true
fi

# ----------------------------------------------------------
# Mouse
# ----------------------------------------------------------
gsettings set org.cinnamon.desktop.peripherals.mouse accel-profile 'flat' \
    2>/dev/null || true
gsettings set org.cinnamon.desktop.peripherals.mouse speed 0.0 \
    2>/dev/null || true
gsettings set org.nemo.preferences click-policy 'double' \
    2>/dev/null || true

if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]] \
   && command -v xinput >/dev/null 2>&1; then

    while IFS= read -r id; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue

        props="$(xinput list-props "$id" 2>/dev/null || true)"

        # Não altera touchpads.
        if grep -q 'libinput Tapping Enabled' <<<"$props"; then
            continue
        fi

        profile_line="$(
            grep -m1 'libinput Accel Profile Enabled (' <<<"$props" \
                || true
        )"

        if [[ -n "$profile_line" ]]; then
            values="${profile_line##*:}"
            values="$(tr -d '[:space:]' <<<"$values")"

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

        if grep -q 'libinput Accel Speed (' <<<"$props"; then
            xinput set-prop "$id" 'libinput Accel Speed' 0 \
                >/dev/null 2>&1 || true
        fi
    done < <(xinput list --id-only 2>/dev/null || true)
fi

# ----------------------------------------------------------
# Dark mode / portal
# ----------------------------------------------------------
if gsettings list-schemas 2>/dev/null | grep -Fxq 'org.x.apps.portal'; then
    gsettings set org.x.apps.portal color-scheme 'prefer-dark' \
        2>/dev/null || true
fi

if gsettings list-schemas 2>/dev/null \
    | grep -Fxq 'org.gnome.desktop.interface'; then

    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' \
        2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' \
        2>/dev/null || true
fi

if gsettings list-schemas 2>/dev/null \
    | grep -Fxq 'org.cinnamon.desktop.interface'; then

    gsettings set org.cinnamon.desktop.interface gtk-theme 'Adwaita-dark' \
        2>/dev/null || true
fi

# ----------------------------------------------------------
# D-Bus / GNOME Keyring
# ----------------------------------------------------------
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd \
        DISPLAY \
        XAUTHORITY \
        WAYLAND_DISPLAY \
        XDG_CURRENT_DESKTOP \
        XDG_SESSION_TYPE \
        >/dev/null 2>&1 || true
fi

# GNOME Keyring é deixado para o fluxo nativo do Arch/Cinnamon:
# SDDM/PAM prepara/desbloqueia o keyring e o autostart do pacote inicia
# o componente secrets. Evitamos uma segunda inicialização manual aqui.

# VS Code: usa Secret Service/libsecret explicitamente.
mkdir -p "$HOME/.vscode"

python - "$HOME/.vscode/argv.json" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
value = '"password-store": "gnome-libsecret"'

if not path.exists():
    path.write_text(
        "{\n  " + value + "\n}\n",
        encoding="utf-8",
    )
    raise SystemExit(0)

text = path.read_text(encoding="utf-8")

# argv.json é JSONC (aceita comentários), então não usamos json.loads aqui.
# Se a chave já existir, apenas trocamos seu valor e preservamos todo o resto.
pattern = re.compile(r'"password-store"\s*:\s*"[^"]*"')
if pattern.search(text):
    text = pattern.sub(value, text, count=1)
else:
    opening = text.find("{")
    closing = text.rfind("}")

    if opening == -1 or closing <= opening:
        text = "{\n  " + value + "\n}\n"
    else:
        body = text[opening + 1:closing]
        has_other_property = bool(re.search(r'"[^"]+"\s*:', body))
        suffix = "," if has_other_property else ""
        insertion = "\n  " + value + suffix + "\n"
        text = text[:opening + 1] + insertion + text[opening + 1:]

path.write_text(text, encoding="utf-8")
PY

# ----------------------------------------------------------
# Flameshot: sem tray; executado sob demanda pela tecla Print.
# ----------------------------------------------------------
mkdir -p "$HOME/.config/flameshot"

python - "$HOME/.config/flameshot/flameshot.ini" <<'PY'
from configparser import ConfigParser
from pathlib import Path
import sys

path = Path(sys.argv[1])

def new_parser():
    parser = ConfigParser(interpolation=None)
    # Flameshot diferencia maiúsculas/minúsculas nos nomes das opções.
    # O ConfigParser padrão faria contrastOpacity virar contrastopacity.
    parser.optionxform = str
    return parser

cfg = new_parser()

if path.exists():
    try:
        cfg.read(path, encoding="utf-8")
    except Exception:
        cfg = new_parser()

if not cfg.has_section("General"):
    cfg.add_section("General")

# Limpa resíduos de versões antigas do Wolf Linux que gravaram as
# opções do Flameshot em minúsculas.
legacy_lowercase = {
    "contrastopacity",
    "autocloseidledaemon",
    "disabledtrayicon",
    "showstartuplaunchmessage",
}
for key in list(cfg["General"].keys()):
    if key in legacy_lowercase:
        cfg.remove_option("General", key)

if not cfg.has_option("General", "contrastOpacity"):
    cfg.set("General", "contrastOpacity", "190")
cfg.set("General", "disabledTrayIcon", "true")
cfg.set("General", "autoCloseIdleDaemon", "true")
cfg.set("General", "showStartupLaunchMessage", "false")

with path.open("w", encoding="utf-8") as f:
    cfg.write(f, space_around_delimiters=False)
PY

# Remove daemon antigo/tray da sessão se existir.
pkill -x flameshot >/dev/null 2>&1 || true

# Limpa atalhos de screenshot do Cinnamon para liberar Print.
if gsettings list-schemas 2>/dev/null \
    | grep -Fxq 'org.cinnamon.desktop.keybindings.media-keys'; then

    for key in \
        screenshot \
        screenshot-clip \
        area-screenshot \
        area-screenshot-clip \
        window-screenshot \
        window-screenshot-clip
    do
        if gsettings list-keys \
            org.cinnamon.desktop.keybindings.media-keys \
            2>/dev/null \
            | grep -Fxq "$key"; then

            gsettings set \
                org.cinnamon.desktop.keybindings.media-keys \
                "$key" \
                "[]" \
                2>/dev/null || true
        fi
    done
fi

CUSTOM_SCHEMA='org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/wolf-flameshot/'

gsettings set "$CUSTOM_SCHEMA" name 'Flameshot' 2>/dev/null || true
gsettings set "$CUSTOM_SCHEMA" command '/usr/bin/flameshot gui' \
    2>/dev/null || true
gsettings set "$CUSTOM_SCHEMA" binding "['Print']" \
    2>/dev/null || true

python - <<'PY'
import ast
import subprocess

schema = "org.cinnamon.desktop.keybindings"
raw = subprocess.run(
    ["gsettings", "get", schema, "custom-list"],
    capture_output=True,
    text=True,
).stdout.strip()

if raw.startswith("@as "):
    raw = raw[4:]

try:
    items = ast.literal_eval(raw)
except Exception:
    items = []

if not isinstance(items, list):
    items = []

if "wolf-flameshot" not in items:
    items.append("wolf-flameshot")

value = "[" + ", ".join(repr(x) for x in items) + "]"
subprocess.run(["gsettings", "set", schema, "custom-list", value])
PY

# ----------------------------------------------------------
# Favoritos do Nemo
# ----------------------------------------------------------
xdg-user-dirs-update >/dev/null 2>&1 || true
mkdir -p "$HOME/.config/gtk-3.0"

BOOKMARKS="$HOME/.config/gtk-3.0/bookmarks"
touch "$BOOKMARKS"

add_bookmark() {
    local path="$1"
    local label="$2"
    local line

    [[ -n "$path" && -d "$path" ]] || return 0

    line="file://$path $label"

    grep -Fxq "$line" "$BOOKMARKS" 2>/dev/null \
        || printf '%s\n' "$line" >> "$BOOKMARKS"
}

add_bookmark "$(xdg-user-dir DOCUMENTS 2>/dev/null || true)" "Documentos"
add_bookmark "$(xdg-user-dir DOWNLOAD 2>/dev/null || true)" "Downloads"
add_bookmark "$(xdg-user-dir MUSIC 2>/dev/null || true)" "Música"
add_bookmark "$(xdg-user-dir PICTURES 2>/dev/null || true)" "Imagens"
add_bookmark "$(xdg-user-dir VIDEOS 2>/dev/null || true)" "Vídeos"

# Reinicia portais depois de publicar prefer-dark e Secret provider.
systemctl --user restart \
    xdg-desktop-portal-xapp.service \
    xdg-desktop-portal-gtk.service \
    xdg-desktop-portal.service \
    >/dev/null 2>&1 || true
EOF

        chmod 755 /mnt/usr/local/bin/wolf-cinnamon-session-setup.sh

        cat > /mnt/etc/xdg/autostart/wolf-cinnamon-session-setup.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Cinnamon Session Setup
Comment=Cinnamon X11, menu nativo, aparência, mouse flat, keyring, Flameshot e integrações Wolf Linux
Exec=/usr/local/bin/wolf-cinnamon-session-setup.sh
OnlyShowIn=X-Cinnamon;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

        mkdir -p /mnt/usr/share/nemo-python/extensions

        # ----------------------------------------------------
        # Nemo: Abrir pasta no VS Code.
        # nemo-python carrega extensões de:
        # /usr/share/nemo-python/extensions
        # ----------------------------------------------------
        cat > /mnt/usr/share/nemo-python/extensions/wolf_vscode.py <<'PY'
import shutil
import subprocess

from gi.repository import Nemo, GObject


class WolfVSCodeExtension(GObject.GObject, Nemo.MenuProvider):
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

    def _selected_activate(self, _menu, file_info):
        self._open(file_info)

    def _background_activate(self, _menu, file_info):
        self._open(file_info)

    def get_file_items(self, window, files):
        if not self._code_available() or len(files) != 1:
            return

        file_info = files[0]

        if not file_info.is_directory():
            return

        if file_info.get_uri_scheme() != "file":
            return

        item = Nemo.MenuItem(
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

        item = Nemo.MenuItem(
            name="WolfLinux::VSCodeCurrentFolder",
            label="Abrir esta pasta no VS Code",
            tip="Abrir a pasta atual em uma nova janela do Visual Studio Code",
        )
        item.connect("activate", self._background_activate, current_folder)
        return [item]
PY

        # ----------------------------------------------------
        # Helper seguro de formatação de mídias removíveis.
        # ----------------------------------------------------
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

        # ----------------------------------------------------
        # Nemo: Formatar mídia removível...
        # O item só aparece na raiz de um filesystem USB/MMC/removível.
        # ----------------------------------------------------
        cat > /mnt/usr/share/nemo-python/extensions/wolf_removable_media.py <<'PY'
import os
import subprocess

from gi.repository import Nemo, GObject


HELPER = "/usr/local/bin/wolf-format-removable"


class WolfRemovableMediaExtension(GObject.GObject, Nemo.MenuProvider):
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
        item = Nemo.MenuItem(
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

        ok "Integrações Nemo configuradas: VS Code e formatação de mídias."
        return 0
    fi

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
# A stack gaming pode solicitar o provedor virtual vulkan-driver no pacman.
# Instalar previamente o provedor da GPU identificada evita escolhas implícitas
# (como NVIDIA numa VM VirtIO), antes da etapa geral de aplicativos.
install_preferred_vulkan_provider() {
    stack_selected gaming || return 0
    local -a providers=(vulkan-icd-loader lib32-vulkan-icd-loader)
    case "$GPU_PROFILE" in
        virtio) providers+=(vulkan-virtio lib32-vulkan-virtio) ;;
        intel) providers+=(vulkan-intel lib32-vulkan-intel) ;;
        amd) providers+=(vulkan-radeon lib32-vulkan-radeon) ;;
        nvidia-modern) providers+=(nvidia-utils lib32-nvidia-utils) ;;
        virtualbox|generic) providers+=(vulkan-swrast lib32-vulkan-swrast) ;;
        nvidia-kepler-nouveau|nvidia-legacy-or-unknown)
            providers+=(vulkan-nouveau lib32-vulkan-nouveau) ;;
        *) providers+=(vulkan-swrast lib32-vulkan-swrast) ;;
    esac
    info "Definindo provedor Vulkan para $GPU_PROFILE antes das stacks de jogos..."
    arch-chroot /mnt pacman -S --needed --noconfirm "${providers[@]}"
    ok 'Provedor Vulkan selecionado conforme a GPU detectada.'
}

install_gpu_profile() {
    local -a packages=()
    local -a early_modules=()

    case "$GPU_PROFILE" in
        virtio)
            packages=("${VIRTIO_GPU_PACKAGES[@]}")
            early_modules=(virtio_gpu)
            ;;

        virtualbox)
            packages=("${VIRTUALBOX_GPU_PACKAGES[@]}")
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
        virtualbox)
            arch-chroot /mnt pacman -Q \
                virtualbox-guest-utils \
                mesa \
                lib32-mesa
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

    # Xbox Bluetooth: BlueZ cria o HID via UHID e o xpadneo fornece o gamepad.
    # Carregá-los cedo evita o estado Connected=yes sem /dev/input em firmwares
    # que dependem do caminho userspace HID do BlueZ.
    cat > /mnt/etc/modules-load.d/wolf-gamepad.conf <<'EOF'
uhid
hid_xpadneo
EOF

    cat > /mnt/usr/local/bin/wolf-gamepad-setup <<'WOLF_GAMEPAD'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Wolf Gamepad Setup"
VERSION="0.3"
XPADNEO_MODULE="hid_xpadneo"
XPADNEO_CONF="/etc/modprobe.d/99-wolf-xpadneo-gamepads.conf"
XPADNEO_LOAD_CONF="/etc/modules-load.d/xpadneo.conf"

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"; }
pause() { read -r -p $'\nPressione Enter para continuar...' _ || true; }
normalize_mac() { tr '[:lower:]' '[:upper:]' <<<"$1"; }

header() {
    clear 2>/dev/null || true
    say "======================================================"
    say "           ${APP_NAME} v${VERSION}"
    say "======================================================"
    say "Perfis atuais:"
    say "  - Xbox/XInput Bluetooth + xpadneo"
    say "  - Layout Nintendo (+32) para controles Xbox-like"
    say ""
    say "O perfil PS3 poderá ser acrescentado depois."
    say "======================================================"
}

xpadneo_installed() { modinfo "$XPADNEO_MODULE" >/dev/null 2>&1; }

kernel_headers_package() {
    local rel
    rel="$(uname -r)"
    case "$rel" in
        *-zen*) echo "linux-zen-headers" ;;
        *-lts*) echo "linux-lts-headers" ;;
        *-hardened*) echo "linux-hardened-headers" ;;
        *) echo "linux-headers" ;;
    esac
}

install_support() {
    need_cmd pacman
    local headers
    headers="$(kernel_headers_package)"

    info "Instalando/verificando suporte geral a gamepads Xbox Bluetooth..."
    sudo pacman -S --needed --noconfirm \
        dkms "$headers" bluez bluez-utils steam-devices evtest joyutils

    if pacman -Si xpadneo-dkms >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm xpadneo-dkms
    elif command -v yay >/dev/null 2>&1; then
        yay -S --needed --noconfirm xpadneo-dkms
    elif ! xpadneo_installed; then
        die "xpadneo-dkms não está nos repositórios configurados e yay não foi encontrado. Instale xpadneo-dkms pelo AUR e execute novamente."
    fi

    printf '%s\n' uhid | sudo tee /etc/modules-load.d/uhid.conf >/dev/null
    printf '%s\n' "$XPADNEO_MODULE" | sudo tee "$XPADNEO_LOAD_CONF" >/dev/null
    sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || true
    sudo modprobe uhid
    sudo modprobe "$XPADNEO_MODULE"

    if [[ -e /dev/uhid ]]; then
        ok "UHID disponível em /dev/uhid."
    else
        warn "/dev/uhid não apareceu; controles Bluetooth HID podem conectar sem criar input device."
    fi
    ok "Suporte instalado. uhid e xpadneo serão carregados cedo nos próximos boots."
}

all_bt_macs() { bluetoothctl devices 2>/dev/null | awk '/^Device / {print $2}'; }

bt_info() { bluetoothctl info "$1" 2>/dev/null || true; }

bt_field() {
    local mac="$1" field="$2"
    bt_info "$mac" | sed -n "s/^[[:space:]]*${field}: //p" | head -n1
}

is_xbox_bt_device() {
    local mac="$1" info_out
    info_out="$(bt_info "$mac")"
    grep -qiE 'Name: Xbox Wireless Controller|Modalias: usb:v045Ep(02FD|0B05|0B13|0B20|0B22)' <<<"$info_out"
}

xbox_devices() {
    local mac name connected paired bonded trusted services modalias
    while read -r mac; do
        [[ -n "$mac" ]] || continue
        is_xbox_bt_device "$mac" || continue
        name="$(bt_field "$mac" Name)"
        connected="$(bt_field "$mac" Connected)"
        paired="$(bt_field "$mac" Paired)"
        bonded="$(bt_field "$mac" Bonded)"
        trusted="$(bt_field "$mac" Trusted)"
        services="$(bt_field "$mac" ServicesResolved)"
        modalias="$(bt_field "$mac" Modalias)"
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
            "$(normalize_mac "$mac")" "${name:-?}" "${connected:-?}" "${paired:-?}" \
            "${bonded:-?}" "${trusted:-?}" "${services:-?}" "${modalias:-?}"
    done < <(all_bt_macs)
}

choose_xbox_device() {
    local -a devs=()
    mapfile -t devs < <(xbox_devices)
    ((${#devs[@]} > 0)) || die "Nenhum controle Xbox Bluetooth conhecido foi encontrado. Coloque-o em modo de pareamento e conecte-o primeiro."

    say "Controles Xbox Bluetooth encontrados:"
    local i row mac name connected paired bonded trusted services modalias
    for i in "${!devs[@]}"; do
        row="${devs[$i]}"
        IFS='|' read -r mac name connected paired bonded trusted services modalias <<<"$row"
        printf '  %d) %s  %s\n' "$((i+1))" "$mac" "$name"
        printf '     connected=%s paired=%s bonded=%s trusted=%s services=%s\n' \
            "$connected" "$paired" "$bonded" "$trusted" "$services"
        printf '     %s\n' "$modalias"
    done

    local choice
    if ((${#devs[@]} == 1)); then
        choice=1
    else
        read -r -p "Escolha o controle: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] || die "Seleção inválida."
        ((choice >= 1 && choice <= ${#devs[@]})) || die "Seleção inválida."
    fi

    IFS='|' read -r SELECTED_MAC SELECTED_NAME _ _ _ _ _ SELECTED_MODALIAS <<<"${devs[$((choice-1))]}"
    export SELECTED_MAC SELECTED_NAME SELECTED_MODALIAS
}

input_device_present() {
    grep -qiE 'N: Name="(Xbox Wireless Controller|.*Xbox.*Controller.*)"' /proc/bus/input/devices 2>/dev/null
}

input_device_summary() {
    awk '
        BEGIN{RS=""; ORS="\n\n"}
        tolower($0) ~ /xbox wireless controller|xbox.*controller/ {print}
    ' /proc/bus/input/devices 2>/dev/null || true
}

input_event_nodes() {
    awk '
        BEGIN{RS=""}
        tolower($0) ~ /xbox wireless controller|xbox.*controller/ {
            if (match($0, /Handlers=[^\n]*/)) {
                h=substr($0, RSTART, RLENGTH)
                n=split(h, a, /[[:space:]]+/)
                for (i=1; i<=n; i++) if (a[i] ~ /^event[0-9]+$/) print "/dev/input/" a[i]
            }
        }
    ' /proc/bus/input/devices 2>/dev/null | sort -u
}

xpadneo_hid_devices() {
    local f
    for f in /sys/bus/hid/devices/*/uevent; do
        [[ -r "$f" ]] || continue
        if grep -qiE 'HID_NAME=.*Xbox Wireless Controller|HID_ID=0005:0000045E:' "$f"; then
            local dir driver
            dir="${f%/uevent}"
            driver="$(basename "$(readlink -f "$dir/driver" 2>/dev/null || true)")"
            printf '%s | driver=%s\n' "$(basename "$dir")" "${driver:-nenhum}"
        fi
    done
}

wait_for_input() {
    local seconds="${1:-12}" i
    for ((i=0; i<seconds; i++)); do
        input_device_present && return 0
        sleep 1
    done
    return 1
}

clean_repair_selected() {
    local mac="$1"
    warn "Vou remover o registro Bluetooth atual de $mac e criar um pareamento limpo."
    say "Coloque o controle em modo de pareamento (logo piscando rapidamente)."
    read -r -p "Pressione Enter para continuar, ou Ctrl+C para cancelar..." _ || true

    bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
    bluetoothctl remove "$mac" >/dev/null 2>&1 || true
    sleep 1

    # Faça uma descoberta curta para o BlueZ voltar a conhecer o endereço antes
    # do comando pair. `timeout` só limita o scan; não altera o bluetoothd.
    timeout 8 bluetoothctl scan on >/dev/null 2>&1 || true
    if ! bluetoothctl pair "$mac"; then
        warn "Pareamento limpo falhou. Confirme que o controle continua em modo Sync e tente novamente."
        return 1
    fi
    bluetoothctl trust "$mac" >/dev/null 2>&1 || true
    bluetoothctl connect "$mac" >/dev/null 2>&1 || true
    sleep 2
    return 0
}

repair_selected_gamepad() {
    need_cmd bluetoothctl
    sudo modprobe uhid || true
    sudo modprobe "$XPADNEO_MODULE" || true

    info "Estado atual de ${SELECTED_NAME} (${SELECTED_MAC}):"
    bt_info "$SELECTED_MAC" | grep -E '^[[:space:]]*(Paired|Bonded|Trusted|Connected|ServicesResolved|Modalias):' || true

    bluetoothctl trust "$SELECTED_MAC" >/dev/null 2>&1 || true

    local paired bonded
    paired="$(bt_field "$SELECTED_MAC" Paired)"
    bonded="$(bt_field "$SELECTED_MAC" Bonded)"

    if [[ "$paired" != yes || "$bonded" != yes ]]; then
        warn "O controle não está completamente pareado/bonded. Connected=yes sozinho NÃO cria um gamepad para Steam."
        say ""
        say "Coloque o controle em modo de pareamento (segure o botão Sync até o logo piscar rapidamente)."
        read -r -p "Pressione Enter quando ele estiver em modo de pareamento..." _ || true

        bluetoothctl disconnect "$SELECTED_MAC" >/dev/null 2>&1 || true
        info "Solicitando pareamento/bond ao BlueZ..."
        if ! bluetoothctl pair "$SELECTED_MAC"; then
            warn "O pareamento falhou. Remover e parear novamente pelo bluetoothctl/Blueman pode ser necessário."
        fi
        bluetoothctl trust "$SELECTED_MAC" >/dev/null 2>&1 || true
    fi

    bluetoothctl connect "$SELECTED_MAC" >/dev/null 2>&1 || true
    sleep 2

    if wait_for_input 12; then
        ok "Input device criado. O controle agora pode ser enumerado por SDL/Steam."
        input_device_summary
        say "Eventos:"
        input_event_nodes | sed 's/^/  - /'
        return 0
    fi

    paired="$(bt_field "$SELECTED_MAC" Paired)"
    bonded="$(bt_field "$SELECTED_MAC" Bonded)"
    warn "Bluetooth está ativo, mas nenhum input device do controle apareceu."
    say "Paired=${paired:-?} Bonded=${bonded:-?} Connected=$(bt_field "$SELECTED_MAC" Connected || true) ServicesResolved=$(bt_field "$SELECTED_MAC" ServicesResolved || true)"
    say ""
    if [[ "$bonded" != yes ]]; then
        warn "O vínculo criptográfico ainda não foi criado (Bonded=no). Connected=yes sozinho não basta para expor um gamepad."
        warn "Não vou relaxar ClassicBondedOnly automaticamente, pois isso reduz a política de segurança do BlueZ."
        local answer=""
        read -r -p "Remover o registro atual e tentar um pareamento limpo agora? [s/N] " answer || true
        case "${answer,,}" in
            s|sim|y|yes)
                if clean_repair_selected "$SELECTED_MAC" && wait_for_input 12; then
                    ok "Pareamento limpo concluído e input device criado."
                    input_device_summary
                    say "Eventos:"
                    input_event_nodes | sed 's/^/  - /'
                    return 0
                fi
                ;;
        esac
    else
        warn "O pareamento está correto; verifique abaixo se o dispositivo HID chegou ao kernel/xpadneo."
        xpadneo_hid_devices || true
    fi

    if [[ "${SELECTED_MODALIAS:-}" == *p02FDd0903* ]]; then
        warn "Este PID/firmware 045E:02FD d0903 possui relato upstream com exatamente: conecta no Bluetooth, mas não cria /dev/input."
        warn "Se Paired/Bonded estiverem corretos, atualize o firmware com Xbox Accessories e depois remova/pareie novamente no Linux."
    fi
    return 1
}

ensure_selected_operational() {
    if input_device_present; then
        return 0
    fi
    warn "O controle ainda não existe como input device. Vou tentar reparar o pareamento/ativação antes de aplicar o mapeamento."
    repair_selected_gamepad
}

read_managed_quirks() {
    [[ -f "$XPADNEO_CONF" ]] || return 0
    sed -nE 's/^options[[:space:]]+hid_xpadneo[[:space:]]+quirks=([^[:space:]#]+).*/\1/p' "$XPADNEO_CONF" | tail -n1
}

write_managed_quirks() {
    local quirks="$1" tmp
    tmp="$(mktemp)"
    {
        say "# Gerado por ${APP_NAME} v${VERSION}"
        say "# +32 = layout Nintendo no xpadneo"
        if [[ -n "$quirks" ]]; then
            say "options hid_xpadneo quirks=${quirks}"
        fi
    } >"$tmp"
    sudo install -m 0644 "$tmp" "$XPADNEO_CONF"
    rm -f "$tmp"
}

reload_selected_after_quirk() {
    local mac="$1"
    if [[ -e "/sys/module/${XPADNEO_MODULE}/parameters/quirks" ]]; then
        local current
        current="$(read_managed_quirks || true)"
        printf '%s\n' "$current" | sudo tee "/sys/module/${XPADNEO_MODULE}/parameters/quirks" >/dev/null || true
    fi
    if [[ "$(bt_field "$mac" Connected)" == yes ]]; then
        bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
        sleep 2
    fi
    bluetoothctl connect "$mac" >/dev/null 2>&1 || true
    sleep 3
}

add_nintendo_mapping() {
    need_cmd bluetoothctl
    xpadneo_installed || die "hid_xpadneo não está instalado. Use primeiro a opção de instalar suporte."
    choose_xbox_device
    ensure_selected_operational || die "O controle não está operacional como input device; não faz sentido aplicar o layout ainda."

    local current new entry
    current="$(read_managed_quirks || true)"
    entry="${SELECTED_MAC}+32"

    if [[ -z "$current" ]]; then
        new="$entry"
    elif tr ',' '\n' <<<"$current" | grep -Fxiq "$entry"; then
        new="$current"
    else
        new="$(tr ',' '\n' <<<"$current" | awk -v mac="$SELECTED_MAC" 'BEGIN{IGNORECASE=1} index(toupper($0), toupper(mac)) != 1 && NF {print}' | paste -sd, -)"
        [[ -n "$new" ]] && new+=","
        new+="$entry"
    fi

    write_managed_quirks "$new"
    reload_selected_after_quirk "$SELECTED_MAC"

    ok "Layout Nintendo configurado para ${SELECTED_NAME} (${SELECTED_MAC})."
    info "Quirks gerenciadas: $new"
    [[ -r "/sys/module/${XPADNEO_MODULE}/parameters/quirks" ]] \
        && info "Parâmetro ativo: $(cat "/sys/module/${XPADNEO_MODULE}/parameters/quirks")"

    if input_device_present; then
        ok "O input device continua presente após a reconexão."
    else
        warn "O controle desapareceu de /proc/bus/input/devices após reconectar; rode Diagnóstico/Reparar."
    fi
    info "Na Steam ele continuará Xbox-compatible; +32 apenas troca A/B/X/Y no nível do driver."
}

remove_nintendo_mapping() {
    need_cmd bluetoothctl
    choose_xbox_device

    local current new
    current="$(read_managed_quirks || true)"
    [[ -n "$current" ]] || { warn "Não há quirks gerenciadas pelo Wolf para remover."; return 0; }

    new="$(tr ',' '\n' <<<"$current" | awk -v mac="$SELECTED_MAC" 'BEGIN{IGNORECASE=1} index(toupper($0), toupper(mac)) != 1 && NF {print}' | paste -sd, -)"
    if [[ -n "$new" ]]; then
        write_managed_quirks "$new"
    else
        sudo rm -f "$XPADNEO_CONF"
    fi
    reload_selected_after_quirk "$SELECTED_MAC"
    ok "Mapeamento Nintendo removido para ${SELECTED_MAC}."
}

diagnostics() {
    need_cmd bluetoothctl
    say "--- Kernel ---"
    uname -a
    say ""

    say "--- Pacotes relevantes ---"
    pacman -Q xpadneo-dkms steam-devices bluez bluez-utils dkms evtest joyutils 2>/dev/null || true
    say "Steam: $(command -v steam 2>/dev/null || echo 'comando não encontrado')"
    say ""

    say "--- UHID / módulos ---"
    if [[ -e /dev/uhid ]]; then
        ls -l /dev/uhid
    else
        say "/dev/uhid AUSENTE"
    fi
    if [[ -r /proc/config.gz ]]; then
        zgrep -E '^CONFIG_UHID=' /proc/config.gz 2>/dev/null || true
    fi
    lsmod | grep -Ei 'xpadneo|xpad|uhid|hid_nintendo' || true
    say ""

    say "--- Aliases xpadneo para Xbox ---"
    modinfo "$XPADNEO_MODULE" 2>/dev/null | grep -Ei '^alias:.*045E.*(02FD|0B05|0B13|0B20|0B22)' || true
    say ""

    say "--- Quirks ativas ---"
    if [[ -r "/sys/module/${XPADNEO_MODULE}/parameters/quirks" ]]; then
        cat "/sys/module/${XPADNEO_MODULE}/parameters/quirks"
    else
        say "hid_xpadneo não está carregado."
    fi
    say ""

    say "--- Configuração persistente Wolf ---"
    if [[ -f "$XPADNEO_CONF" ]]; then
        cat "$XPADNEO_CONF"
    else
        say "nenhuma"
    fi
    say ""

    say "--- Controles Xbox Bluetooth conhecidos ---"
    local rows
    rows="$(xbox_devices || true)"
    if [[ -n "$rows" ]]; then
        say "${rows//|/ | }"
    else
        say "nenhum"
    fi
    say ""

    say "--- Dispositivos HID Xbox no sysfs ---"
    xpadneo_hid_devices || true
    say ""

    say "--- Dispositivos de entrada relacionados ---"
    input_device_summary
    if input_device_present; then
        say "Event nodes:"
        input_event_nodes | sed 's/^/  - /'
    else
        say "NENHUM input device Xbox encontrado. A Steam não conseguirá enumerar o controle neste estado."
    fi
    say ""

    say "--- BlueZ input.conf ---"
    if [[ -f /etc/bluetooth/input.conf ]]; then
        grep -E '^[[:space:]]*(UserspaceHID|ClassicBondedOnly|LEAutoSecurity)[[:space:]]*=' /etc/bluetooth/input.conf || say "sem overrides relevantes"
    else
        say "arquivo ausente; defaults do BlueZ em uso (UserspaceHID=true, ClassicBondedOnly=true)."
    fi
    say ""

    say "--- Logs recentes bluetoothd/xpadneo ---"
    journalctl -b -u bluetooth --no-pager -n 120 2>/dev/null | grep -Ei 'xbox|hid|bond|uhid|input|reject|02fd|045e' | tail -n 60 || true
    sudo dmesg 2>/dev/null | grep -Ei 'xpadneo|xbox|045e|02fd|uhid|hid-generic' | tail -n 60 || true
}

repair_gamepad() {
    choose_xbox_device
    repair_selected_gamepad
}

main_menu() {
    while true; do
        header
        say "1) Instalar/verificar suporte Xbox Bluetooth (xpadneo + Steam)"
        say "2) Configurar layout Nintendo (+32) em um controle Xbox Bluetooth"
        say "3) Remover layout Nintendo de um controle"
        say "4) Diagnóstico completo"
        say "5) Reparar pareamento e validar input device"
        say "0) Sair"
        say ""
        read -r -p "Opção: " opt
        case "$opt" in
            1) install_support; pause ;;
            2) add_nintendo_mapping; pause ;;
            3) remove_nintendo_mapping; pause ;;
            4) diagnostics; pause ;;
            5) repair_gamepad; pause ;;
            0) exit 0 ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

need_cmd bluetoothctl
main_menu
WOLF_GAMEPAD
    chmod 755 /mnt/usr/local/bin/wolf-gamepad-setup

    ok "Stack gaming instalada (Steam + ferramentas evdev + xpadneo)."
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

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in
    *MATE*) DESKTOP_ID="mate" ;;
    *X-Cinnamon*|*Cinnamon*) DESKTOP_ID="cinnamon" ;;
    *KDE*|*Plasma*) DESKTOP_ID="plasma" ;;
    *XFCE*|*Xfce*) DESKTOP_ID="xfce" ;;
    *) exit 0 ;;
esac

MARKER="$HOME/.config/wolf-linux/style-${DESKTOP_ID}-v2.done"
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
        # Cinnamon reconhece o tema Breeze pelo diretório "breeze_cursors".
        # O alias "breeze-dark" funciona em outros ambientes, mas pode gerar
        # fallback parcial/inconsistente no Cinnamon.
        CINNAMON_CURSOR_THEME="breeze_cursors"

        if [[ ! -d "/usr/share/icons/$CINNAMON_CURSOR_THEME/cursors" ]]; then
            if [[ -d /usr/share/icons/Breeze_Snow/cursors ]]; then
                CINNAMON_CURSOR_THEME="Breeze_Snow"
            else
                CINNAMON_CURSOR_THEME="Adwaita"
            fi
        fi

        if gsettings list-schemas | grep -Fxq 'org.cinnamon.desktop.interface'; then
            gsettings set org.cinnamon.desktop.interface gtk-theme 'Adwaita-dark' || true
            gsettings set org.cinnamon.desktop.interface icon-theme 'Papirus-Dark' || true
            gsettings set org.cinnamon.desktop.interface cursor-theme "$CINNAMON_CURSOR_THEME" || true
            gsettings set org.cinnamon.desktop.interface cursor-size 24 || true
        fi

        # Alguns aplicativos GTK consultam o schema GNOME mesmo no Cinnamon.
        if gsettings list-schemas | grep -Fxq 'org.gnome.desktop.interface'; then
            gsettings set org.gnome.desktop.interface cursor-theme "$CINNAMON_CURSOR_THEME" 2>/dev/null || true
            gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null || true
        fi

        # Alinha os fallbacks XCursor/GTK com o mesmo nome real do tema.
        sed -i \
            "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$CINNAMON_CURSOR_THEME/" \
            "$HOME/.config/gtk-3.0/settings.ini" \
            "$HOME/.config/gtk-4.0/settings.ini" \
            2>/dev/null || true

        mkdir -p "$HOME/.local/share/icons/default" "$HOME/.icons/default"

        cat > "$HOME/.local/share/icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=$CINNAMON_CURSOR_THEME
EOF

        cat > "$HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=$CINNAMON_CURSOR_THEME
EOF

        {
            grep -vE '^Xcursor\.(theme|size):' "$HOME/.Xresources" 2>/dev/null || true
            echo "Xcursor.theme: $CINNAMON_CURSOR_THEME"
            echo "Xcursor.size: 24"
        } > "$HOME/.Xresources.wolf"

        mv -f "$HOME/.Xresources.wolf" "$HOME/.Xresources"

        if command -v xrdb >/dev/null 2>&1; then
            xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
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

    *XFCE*|*Xfce*)
        if command -v xfconf-query >/dev/null 2>&1; then
            xfconf-query -c xsettings -p /Net/ThemeName -s 'Materia-dark' 2>/dev/null || true
            xfconf-query -c xsettings -p /Net/IconThemeName -s 'Papirus-Dark' 2>/dev/null || true
            xfconf-query -c xsettings -p /Gtk/CursorThemeName -s 'breeze_cursors' 2>/dev/null || true
            xfconf-query -c xfwm4 -p /general/theme -s 'Materia-dark' 2>/dev/null || true
            xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false 2>/dev/null \
                || xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
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

install_wolf_desktop_branding() {
    info "Instalando identidade Wolf para menus Cinnamon/KDE..."

    local src="$PROJECT_DIR/tools/wolf-desktop-branding-0.1.sh"
    [[ -f "$src" ]] || die "Helper de branding ausente no projeto: $src"

    install -Dm0755 "$src" /mnt/usr/local/bin/wolf-desktop-branding
    mkdir -p /mnt/etc/xdg/autostart
    cat > /mnt/etc/xdg/autostart/wolf-desktop-branding.desktop <<'WOLF_BRANDING_DESKTOP'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Identidade do desktop
Comment=Aplica o símbolo Wolf Linux ao menu do Cinnamon e Plasma uma única vez
Exec=/usr/local/bin/wolf-desktop-branding
OnlyShowIn=X-Cinnamon;KDE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
WOLF_BRANDING_DESKTOP

    ok "Branding de menu Cinnamon/KDE preparado para o primeiro login."
}

install_wolf_grub_manager() {
    info "Instalando Wolf GRUB Manager..."

    mkdir -p /mnt/usr/local/bin

    cat > /mnt/usr/local/bin/wolf-grub-manager <<'WOLF_GRUB_MANAGER'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Wolf GRUB Manager"
VERSION="0.3"

GRUB_CFG="/boot/grub/grub.cfg"
GRUB_DEFAULT="/etc/default/grub"
GRUB_D="/etc/grub.d"
WOLF_ENTRIES_DIR="/etc/grub.d/wolf-entries.d"
WOLF_CUSTOM_SCRIPT="/etc/grub.d/42_wolf_custom"
BACKUP_ROOT="/var/backups/wolf-grub"

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

pause() {
    read -r -p $'\nPressione Enter para continuar...' _ || true
}

header() {
    clear 2>/dev/null || true
    say "======================================================"
    say "              ${APP_NAME} v${VERSION}"
    say "======================================================"
    say "Gerencia as FONTES do menu GRUB, não edita grub.cfg"
    say "manualmente. Operações destrutivas exigem confirmação."
    say "======================================================"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

require_grub() {
    need_cmd grub-mkconfig
    [[ -d "$GRUB_D" ]] || die "$GRUB_D não existe."
    [[ -f "$GRUB_DEFAULT" ]] || die "$GRUB_DEFAULT não existe."
}

confirm() {
    local prompt="${1:-Confirmar?}"
    local answer
    read -r -p "$prompt [s/N]: " answer
    [[ "$answer" =~ ^[sS]([iI][mM])?$ ]]
}

boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        say "UEFI"
    else
        say "BIOS/Legacy"
    fi
}

read_grub_cfg() {
    [[ -f "$GRUB_CFG" ]] || return 1

    if [[ -r "$GRUB_CFG" ]]; then
        cat "$GRUB_CFG"
    else
        info "$GRUB_CFG exige privilégio de leitura; solicitando sudo..." >&2
        sudo cat "$GRUB_CFG"
    fi
}

grub_cfg_sha256() {
    read_grub_cfg | sha256sum | awk '{print $1}'
}

backup_grub() {
    local stamp dest
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="${BACKUP_ROOT}/${stamp}"

    info "Criando backup em ${dest}..."
    sudo mkdir -p "$dest"

    [[ -f "$GRUB_DEFAULT" ]] && sudo cp -a "$GRUB_DEFAULT" "$dest/default-grub"
    [[ -d "$GRUB_D" ]] && sudo cp -a "$GRUB_D" "$dest/grub.d"
    [[ -f "$GRUB_CFG" ]] && sudo cp -a "$GRUB_CFG" "$dest/grub.cfg"

    sudo sh -c "printf '%s\n' \
        'Data: $(date -Is)' \
        'Kernel: $(uname -r)' \
        'Boot mode: $(boot_mode)' \
        > '$dest/INFO.txt'"

    ok "Backup criado: $dest"
}

menuentry_stream() {
    read_grub_cfg | awk '
        /^### BEGIN \/etc\/grub\.d\// {
            src=$0
            sub(/^### BEGIN /, "", src)
            sub(/ ###$/, "", src)
        }
        /^[[:space:]]*(menuentry|submenu)[[:space:]]/ {
            line=$0
            kind=line
            sub(/^[[:space:]]*/, "", kind)
            sub(/[[:space:]].*$/, "", kind)

            title=line
            sub(/^[[:space:]]*(menuentry|submenu)[[:space:]]+/, "", title)

            if (substr(title,1,1) == sprintf("%c",39)) {
                title=substr(title,2)
                split(title,a,sprintf("%c",39))
                title=a[1]
            } else if (substr(title,1,1) == "\"") {
                title=substr(title,2)
                split(title,a,"\"")
                title=a[1]
            } else {
                split(title,a,/ --| \{/)
                title=a[1]
            }

            printf "%s\t%s\t%s\n", kind, title, (src ? src : "?")
        }
    '
}

list_entries() {
    say "--- Entradas presentes no grub.cfg atual ---"

    if [[ ! -f "$GRUB_CFG" ]]; then
        warn "$GRUB_CFG não existe."
        return 0
    fi

    local n=0 kind title source
    while IFS=$'\t' read -r kind title source; do
        ((n+=1))
        printf '%3d) %-9s %s\n' "$n" "$kind" "$title"
        printf '     origem: %s\n' "$source"
    done < <(menuentry_stream)

    if (( n == 0 )); then
        warn "Nenhuma menuentry/submenu encontrada."
    else
        say ""
        say "Total: $n"
    fi
}

detect_duplicate_titles() {
    say "--- Títulos repetidos no grub.cfg ---"

    local tmp found title
    tmp="$(mktemp)"

    if ! menuentry_stream \
        | awk -F '\t' '$1=="menuentry" {print $2 "\t" $3}' \
        > "$tmp"; then
        rm -f "$tmp"
        warn "Não foi possível analisar o grub.cfg."
        return 1
    fi

    found=0
    while IFS= read -r title; do
        [[ -n "$title" ]] || continue
        found=1
        printf '\nDuplicada: %s\n' "$title"
        awk -F '\t' -v t="$title" '$1==t {print "  - " $2}' "$tmp" | sort -u
    done < <(
        cut -f1 "$tmp" \
            | sort \
            | uniq -d
    )

    rm -f "$tmp"

    if (( found == 0 )); then
        ok "Não há títulos menuentry idênticos repetidos."
    fi
}

bootnext_entry_count() {
    local count
    count="$(
        menuentry_stream 2>/dev/null \
            | awk -F '\t' '$3=="/etc/grub.d/31_efi_bootnext" && $1=="menuentry" {n++} END{print n+0}'
    )"
    printf '%s\n' "${count:-0}"
}

list_grub_scripts() {
    say "--- Geradores em /etc/grub.d ---"
    local f base mode state

    while IFS= read -r f; do
        base="${f##*/}"
        mode="$(stat -c '%A' "$f" 2>/dev/null || printf '?')"
        if [[ -x "$f" ]]; then
            state="ATIVO"
        else
            state="inativo"
        fi
        printf '%-28s %-8s %s\n' "$base" "$state" "$mode"
    done < <(find "$GRUB_D" -maxdepth 1 -type f -print 2>/dev/null | sort)
}

list_kernels() {
    say "--- Kernels detectados ---"

    say ""
    say "/boot:"
    find /boot -maxdepth 1 -type f \
        \( -name 'vmlinuz-*' -o -name 'initramfs-*.img' -o -name '*-ucode.img' \) \
        -printf '  %f\n' 2>/dev/null | sort || true

    say ""
    say "pkgbase em /usr/lib/modules:"
    local f
    for f in /usr/lib/modules/*/pkgbase; do
        [[ -r "$f" ]] || continue
        printf '  %-28s %s\n' "$(cat "$f")" "${f%/pkgbase}"
    done

    say ""
    say "Pacotes kernel conhecidos pelo pacman:"
    pacman -Qq 2>/dev/null \
        | grep -E '^linux($|-lts$|-zen$|-hardened$|[0-9])' \
        | sed 's/^/  /' || true
}

grub_default_value() {
    local key="$1"
    sed -nE "s/^[[:space:]]*${key}=(.*)$/\1/p" "$GRUB_DEFAULT" | tail -n1
}

diagnostics() {
    require_grub

    say "--- Sistema ---"
    printf 'Boot mode: %s\n' "$(boot_mode)"
    printf 'Kernel atual: %s\n' "$(uname -r)"
    printf 'GRUB package: '
    pacman -Q grub 2>/dev/null || say "não identificado pelo pacman"
    printf 'grub-mkconfig: %s\n' "$(command -v grub-mkconfig)"
    printf 'grub.cfg: %s\n' "$GRUB_CFG"

    if [[ -f "$GRUB_CFG" ]]; then
        printf 'grub.cfg modificado em: %s\n' "$(stat -c '%y' "$GRUB_CFG")"
        printf 'grub.cfg SHA256: %s\n' "$(grub_cfg_sha256)"
    fi

    say ""
    say "--- /etc/default/grub relevante ---"
    grep -E '^[[:space:]]*GRUB_(DEFAULT|TIMEOUT|DISABLE_SUBMENU|DISABLE_OS_PROBER|DISABLE_BOOTNEXT|TOP_LEVEL|SAVEDEFAULT|CMDLINE_LINUX|CMDLINE_LINUX_DEFAULT)=' \
        "$GRUB_DEFAULT" 2>/dev/null || true

    say ""
    list_kernels

    say ""
    list_grub_scripts

    say ""
    detect_duplicate_titles

    if [[ -x "$GRUB_D/31_efi_bootnext" ]]; then
        local bn_count bn_setting
        bn_count="$(bootnext_entry_count)"
        bn_setting="$(grub_default_value GRUB_DISABLE_BOOTNEXT)"
        say ""
        say "--- EFI BootNext (GRUB 2.16+) ---"
        printf 'Gerador 31_efi_bootnext: ATIVO\n'
        printf 'GRUB_DISABLE_BOOTNEXT: %s\n' "${bn_setting:-<não definido>}"
        printf 'Entradas BootNext atuais: %s\n' "$bn_count"

        if (( bn_count > 0 )) && [[ "$bn_setting" != "true" ]]; then
            warn "Há entradas EFI BootNext no menu. Se forem apenas ruído, use a opção"
            warn "'Gerenciar EFI BootNext' e desative-as de forma persistente."
        fi
    fi
}

regenerate_grub() {
    require_grub
    need_cmd grub-script-check

    local tmp count
    tmp="$(sudo mktemp /tmp/wolf-grub.cfg.XXXXXX)"

    info "Gerando configuração temporária..."
    if ! sudo grub-mkconfig -o "$tmp"; then
        sudo rm -f "$tmp"
        die "grub-mkconfig falhou. O grub.cfg atual NÃO foi alterado."
    fi

    info "Validando sintaxe com grub-script-check..."
    if ! sudo grub-script-check "$tmp"; then
        sudo rm -f "$tmp"
        die "A nova configuração falhou na validação. O grub.cfg atual NÃO foi alterado."
    fi

    count="$(sudo grep -cE '^[[:space:]]*menuentry[[:space:]]' "$tmp" || true)"
    if [[ "$count" -lt 1 ]]; then
        sudo rm -f "$tmp"
        die "A configuração nova não contém menuentry. Recusando instalar."
    fi

    say ""
    say "A nova configuração contém ${count} menuentry(s)."

    if ! confirm "Substituir $GRUB_CFG por esta configuração validada?"; then
        sudo rm -f "$tmp"
        warn "Operação cancelada."
        return 0
    fi

    backup_grub
    sudo install -m 0644 "$tmp" "$GRUB_CFG"
    sudo rm -f "$tmp"
    ok "GRUB regenerado e validado."
}

set_grub_key() {
    local key="$1" value="$2"
    local tmp

    tmp="$(mktemp)"
    awk -v key="$key" -v value="$value" '
        BEGIN {done=0}
        $0 ~ "^[[:space:]]*" key "=" {
            print key "=" value
            done=1
            next
        }
        {print}
        END {
            if (!done) print key "=" value
        }
    ' "$GRUB_DEFAULT" > "$tmp"

    sudo install -m 0644 "$tmp" "$GRUB_DEFAULT"
    rm -f "$tmp"
}

manage_bootnext() {
    require_grub

    local current count
    current="$(grub_default_value GRUB_DISABLE_BOOTNEXT)"
    count="$(bootnext_entry_count)"

    say "--- EFI BootNext ---"
    printf 'Gerador: %s\n' "$([[ -x "$GRUB_D/31_efi_bootnext" ]] && printf ATIVO || printf inativo)"
    printf 'GRUB_DISABLE_BOOTNEXT=%s\n' "${current:-<não definido>}"
    printf 'Entradas atuais vindas de 31_efi_bootnext: %s\n' "$count"
    say ""
    say "EFI BootNext permite que o GRUB ofereça atalhos para entradas UEFI."
    say "Isso NÃO é necessário para iniciar normalmente o Wolf Linux, Windows"
    say "ou acessar UEFI Firmware Settings."
    say ""
    say "1) Ocultar entradas EFI BootNext (recomendado para menu limpo)"
    say "2) Reativar entradas EFI BootNext"
    say "0) Voltar"

    local opt
    read -r -p "Opção: " opt
    case "$opt" in
        1)
            backup_grub
            set_grub_key GRUB_DISABLE_BOOTNEXT true
            ok "GRUB_DISABLE_BOOTNEXT=true definido."
            info "Agora regenere o GRUB para remover as entradas do menu."
            ;;
        2)
            backup_grub
            set_grub_key GRUB_DISABLE_BOOTNEXT false
            ok "GRUB_DISABLE_BOOTNEXT=false definido."
            info "Agora regenere o GRUB para aplicar."
            ;;
        0) return 0 ;;
        *) warn "Opção inválida." ;;
    esac
}

manage_os_prober() {
    require_grub

    local current
    current="$(grub_default_value GRUB_DISABLE_OS_PROBER)"

    say "Estado atual em /etc/default/grub:"
    printf '  GRUB_DISABLE_OS_PROBER=%s\n' "${current:-<não definido>}"
    say ""
    say "1) Habilitar detecção de outros sistemas (false)"
    say "2) Desabilitar os-prober (true)"
    say "0) Voltar"

    local opt
    read -r -p "Opção: " opt
    case "$opt" in
        1)
            backup_grub
            set_grub_key GRUB_DISABLE_OS_PROBER false
            ok "os-prober habilitado. Regenere o GRUB para aplicar."
            ;;
        2)
            backup_grub
            set_grub_key GRUB_DISABLE_OS_PROBER true
            ok "os-prober desabilitado. Regenere o GRUB para aplicar."
            ;;
        0) return 0 ;;
        *) warn "Opção inválida." ;;
    esac
}

toggle_generator_script() {
    require_grub

    local -a files=()
    mapfile -t files < <(find "$GRUB_D" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort)

    ((${#files[@]} > 0)) || { warn "Nenhum script encontrado."; return 0; }

    say "Geradores:"
    local i state
    for i in "${!files[@]}"; do
        if [[ -x "$GRUB_D/${files[$i]}" ]]; then
            state="ATIVO"
        else
            state="inativo"
        fi
        printf '%3d) %-28s %s\n' "$((i+1))" "${files[$i]}" "$state"
    done

    say ""
    local choice base target
    read -r -p "Número do script (0 cancela): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "Seleção inválida."; return 0; }
    (( choice == 0 )) && return 0
    (( choice >= 1 && choice <= ${#files[@]} )) || { warn "Seleção inválida."; return 0; }

    base="${files[$((choice-1))]}"
    target="$GRUB_D/$base"

    case "$base" in
        00_header|10_linux)
            warn "O Wolf GRUB Manager não permite desativar $base."
            warn "Isso poderia remover componentes essenciais ou todas as entradas Linux geradas."
            return 0
            ;;
        31_efi_bootnext)
            warn "Não altere o bit executável de 31_efi_bootnext."
            warn "Uma atualização do pacote GRUB pode restaurá-lo."
            warn "Use a opção 'Gerenciar EFI BootNext', que grava GRUB_DISABLE_BOOTNEXT."
            return 0
            ;;
    esac

    if [[ -x "$target" ]]; then
        warn "Desativar $base impede que ele gere entradas no próximo grub-mkconfig."
        confirm "Desativar este gerador?" || return 0
        backup_grub
        sudo chmod a-x "$target"
        ok "$base desativado. Regenere o GRUB para aplicar."
    else
        confirm "Ativar novamente $base?" || return 0
        backup_grub
        sudo chmod a+x "$target"
        ok "$base ativado. Regenere o GRUB para aplicar."
    fi
}

ensure_wolf_custom_generator() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
#!/bin/sh
# Wolf Linux: emite entradas customizadas gerenciadas em arquivos .cfg.
for f in /etc/grub.d/wolf-entries.d/*.cfg; do
    [ -r "$f" ] || continue
    cat "$f"
    printf '\n'
done
EOF
    sudo mkdir -p "$WOLF_ENTRIES_DIR"
    sudo install -m 0755 "$tmp" "$WOLF_CUSTOM_SCRIPT"
    rm -f "$tmp"
}

list_wolf_entries() {
    if [[ ! -d "$WOLF_ENTRIES_DIR" ]]; then
        say "Nenhuma entrada Wolf customizada."
        return 0
    fi

    local -a files=()
    mapfile -t files < <(find "$WOLF_ENTRIES_DIR" -maxdepth 1 -type f -name '*.cfg' -printf '%f\n' 2>/dev/null | sort)

    if ((${#files[@]} == 0)); then
        say "Nenhuma entrada Wolf customizada."
        return 0
    fi

    local i title
    for i in "${!files[@]}"; do
        title="$(sed -nE "s/^[[:space:]]*menuentry[[:space:]]+'([^']+)'.*/\1/p" \
            "$WOLF_ENTRIES_DIR/${files[$i]}" 2>/dev/null | head -n1)"
        printf '%3d) %-32s %s\n' "$((i+1))" "${title:-?}" "${files[$i]}"
    done
}

slugify() {
    local s="$1"
    s="${s,,}"
    s="$(sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' <<<"$s")"
    [[ -n "$s" ]] || s="entrada"
    printf '%s\n' "$s"
}

add_custom_entry() {
    require_grub

    warn "Modo avançado: esta função cria uma entrada GRUB customizada."
    warn "Use principalmente para entradas especiais que não são geradas automaticamente."
    say ""

    local title
    read -r -p "Título da entrada: " title
    [[ -n "$title" ]] || { warn "Título vazio."; return 0; }
    [[ "$title" != *"'"* ]] || { warn "O título não pode conter apóstrofo nesta versão."; return 0; }

    say ""
    say "Digite o CORPO da menuentry, uma linha por vez."
    say "Digite apenas um ponto (.) para finalizar."
    say ""

    local body="" line
    while IFS= read -r line; do
        [[ "$line" == "." ]] && break
        body+=$'    '"$line"$'\n'
    done

    [[ -n "$body" ]] || { warn "Corpo vazio. Cancelado."; return 0; }

    local slug tmp dest
    slug="$(slugify "$title")"
    tmp="$(mktemp)"
    dest="$WOLF_ENTRIES_DIR/${slug}.cfg"

    {
        printf "menuentry '%s' --class wolf-custom {\n" "$title"
        printf '%s' "$body"
        printf '}\n'
    } > "$tmp"

    say ""
    say "--- Entrada proposta ---"
    cat "$tmp"
    say ""

    if ! confirm "Salvar esta entrada?"; then
        rm -f "$tmp"
        return 0
    fi

    backup_grub
    ensure_wolf_custom_generator
    sudo install -m 0644 "$tmp" "$dest"
    rm -f "$tmp"

    ok "Entrada salva em $dest"
    info "Use 'Regenerar GRUB' para validar e aplicar."
}

remove_custom_entry() {
    [[ -d "$WOLF_ENTRIES_DIR" ]] || { warn "Nenhuma entrada Wolf customizada."; return 0; }

    local -a files=()
    mapfile -t files < <(find "$WOLF_ENTRIES_DIR" -maxdepth 1 -type f -name '*.cfg' -printf '%f\n' 2>/dev/null | sort)
    ((${#files[@]} > 0)) || { warn "Nenhuma entrada Wolf customizada."; return 0; }

    list_wolf_entries
    say ""

    local choice target
    read -r -p "Número para remover (0 cancela): " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn "Seleção inválida."; return 0; }
    (( choice == 0 )) && return 0
    (( choice >= 1 && choice <= ${#files[@]} )) || { warn "Seleção inválida."; return 0; }

    target="$WOLF_ENTRIES_DIR/${files[$((choice-1))]}"
    confirm "Remover $target?" || return 0

    backup_grub
    sudo rm -f "$target"
    ok "Entrada removida. Regenere o GRUB para aplicar."
}

show_source_advice() {
    cat <<'EOF'
Como interpretar as origens:

  /etc/grub.d/10_linux
      Entradas dos kernels Linux instalados. NÃO apague no grub.cfg.
      Zen + LTS é esperado quando ambos os kernels estão instalados.

  /etc/grub.d/30_os-prober
      Sistemas encontrados pelo os-prober, como Windows.

  /etc/grub.d/30_uefi-firmware
      Atalho "UEFI Firmware Settings".

  /etc/grub.d/31_efi_bootnext
      GRUB 2.16+: atalhos para entradas UEFI BootNext.
      Para ocultá-los persistentemente, use GRUB_DISABLE_BOOTNEXT=true.
      Não é recomendado apenas chmod -x no script, pois atualização do pacote
      pode restaurar a permissão.

  /etc/grub.d/40_custom, 41_custom ou outros *_custom
      Entradas customizadas.

  /etc/grub.d/42_wolf_custom
      Entradas criadas pelo Wolf GRUB Manager.

O grub.cfg é um ARQUIVO GERADO. Alterações diretas nele podem desaparecer no
próximo grub-mkconfig.
EOF
}

main_menu() {
    require_grub

    while true; do
        header
        say "1) Diagnóstico completo"
        say "2) Listar entradas e origem"
        say "3) Detectar títulos duplicados"
        say "4) Listar kernels e initramfs"
        say "5) Listar scripts geradores /etc/grub.d"
        say "6) Gerenciar EFI BootNext (GRUB 2.16+)"
        say "7) Ativar/desativar outro script gerador"
        say "8) Configurar os-prober"
        say "9) Adicionar entrada customizada Wolf"
        say "10) Remover entrada customizada Wolf"
        say "11) Listar entradas customizadas Wolf"
        say "12) Regenerar GRUB com backup + validação"
        say "13) Explicar como remover entradas corretamente"
        say "0) Sair"
        say ""

        local opt
        read -r -p "Opção: " opt
        case "$opt" in
            1) diagnostics; pause ;;
            2) list_entries; pause ;;
            3) detect_duplicate_titles; pause ;;
            4) list_kernels; pause ;;
            5) list_grub_scripts; pause ;;
            6) manage_bootnext; pause ;;
            7) toggle_generator_script; pause ;;
            8) manage_os_prober; pause ;;
            9) add_custom_entry; pause ;;
            10) remove_custom_entry; pause ;;
            11) list_wolf_entries; pause ;;
            12) regenerate_grub; pause ;;
            13) show_source_advice; pause ;;
            0) exit 0 ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

require_grub
main_menu
WOLF_GRUB_MANAGER

    chmod 755 /mnt/usr/local/bin/wolf-grub-manager

    install -Dm755 \
        /mnt/usr/local/bin/wolf-grub-manager \
        /mnt/usr/local/share/wolf-linux/tools/wolf-grub-manager-0.3.sh

    ok "Wolf GRUB Manager instalado: /usr/local/bin/wolf-grub-manager"
}

configure_bootloader() {
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        info "Instalando GRUB UEFI..."

        local -a physical_grub_options=()
        if [[ -n "$GUI_PHYSICAL_PLAN" || ( -n "$GUI_VM_PLAN" && "$GUI_VM_MODE" == "reuse" && "$VM_TYPE" == "none" ) ]]; then
            # Preservar entradas NVRAM em instalações que reutilizam uma ESP existente.
            physical_grub_options+=(--no-nvram)
        fi
        arch-chroot /mnt grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot/efi \
            --bootloader-id=WolfLinux \
            "${physical_grub_options[@]}" \
            --recheck

        # Em ESP criada/formatada pelo Wolf, oferecemos também o caminho
        # fallback EFI/BOOT/BOOTX64.EFI para firmwares que ignoram BootOrder.
        # Se a ESP é preservada, NUNCA sobrescrever o fallback já existente
        # (pode ser do Windows, outro SO ou gerenciador de boot).
        local fallback_path='/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI'
        if [[ "$FORMAT_ESP" == 'yes' || ! -e "$fallback_path" ]]; then
            info 'Configurando caminho EFI alternativo sem substituir um loader existente...'
            arch-chroot /mnt grub-install \
                --target=x86_64-efi \
                --efi-directory=/boot/efi \
                --removable \
                --no-nvram \
                --recheck
        else
            info 'Caminho EFI/BOOT existente preservado; WolfLinux em EFI/WolfLinux.'
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

    # Sempre deixe o menu visível por alguns segundos. O linux-lts é instalado
    # em paralelo ao linux-zen e funciona como kernel independente de recuperação
    # caso uma atualização do kernel principal seja interrompida.
    if grep -q '^GRUB_TIMEOUT_STYLE=' /mnt/etc/default/grub; then
        sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /mnt/etc/default/grub
    else
        printf '\nGRUB_TIMEOUT_STYLE=menu\n' >> /mnt/etc/default/grub
    fi
    if grep -q '^GRUB_TIMEOUT=' /mnt/etc/default/grub; then
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /mnt/etc/default/grub
    else
        printf 'GRUB_TIMEOUT=5\n' >> /mnt/etc/default/grub
    fi
    if grep -q '^GRUB_TOP_LEVEL=' /mnt/etc/default/grub; then
        sed -i 's|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"|' /mnt/etc/default/grub
    else
        printf 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"\n' >> /mnt/etc/default/grub
    fi

    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
}

validate_boot_installation() {
    echo
    echo "Validando instalação de boot..."

    local kernel="/mnt/boot/vmlinuz-linux-zen"
    local initramfs="/mnt/boot/initramfs-linux-zen.img"
    local recovery_kernel="/mnt/boot/vmlinuz-linux-lts"
    local recovery_initramfs="/mnt/boot/initramfs-linux-lts.img"
    local grub_cfg="/mnt/boot/grub/grub.cfg"

    [[ -s "$kernel" ]] ||
        die "Kernel linux-zen ausente ou vazio: /boot/vmlinuz-linux-zen"

    [[ -s "$initramfs" ]] ||
        die "Initramfs linux-zen ausente ou vazio: /boot/initramfs-linux-zen.img"

    [[ -s "$recovery_kernel" ]] ||
        die "Kernel de recuperação linux-lts ausente ou vazio."

    [[ -s "$recovery_initramfs" ]] ||
        die "Initramfs de recuperação linux-lts ausente ou vazio."

    [[ -s "$grub_cfg" ]] ||
        die "grub.cfg ausente ou vazio."

    arch-chroot /mnt grub-script-check /boot/grub/grub.cfg

    grep -q 'vmlinuz-linux-zen' "$grub_cfg" ||
        die "grub.cfg não contém uma entrada para vmlinuz-linux-zen."

    grep -q 'initramfs-linux-zen.img' "$grub_cfg" ||
        die "grub.cfg não referencia initramfs-linux-zen.img."

    grep -q 'vmlinuz-linux-lts' "$grub_cfg" ||
        die "grub.cfg não contém o kernel de recuperação linux-lts."

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
        [[ -s /mnt/boot/efi/EFI/WolfLinux/grubx64.efi ]] ||
            die 'GRUB EFI WolfLinux ausente (EFI/WolfLinux/grubx64.efi).'
        findmnt -rn --mountpoint /mnt/boot/efi >/dev/null ||
            die 'A ESP não está montada em /mnt/boot/efi durante a validação do boot.'

        echo
        echo "Executáveis EFI:"
        find /mnt/boot/efi/EFI \
            -maxdepth 3 \
            -type f \
            -iname '*.efi' \
            -print 2>/dev/null || true

        [[ -s "$fallback_efi" ]] ||
            warn 'EFI/BOOT/BOOTX64.EFI não existe: sem fallback UEFI (a entrada WolfLinux dependerá da NVRAM).'

        echo
        echo 'Entradas NVRAM e caminhos EFI (para diagnóstico de boot):'
        efibootmgr -v 2>/dev/null || warn 'Firmware não disponibilizou efibootmgr -v; confira pelo menu de boot.'
        echo 'Destino EFI WolfLinux:'
        ls -lh /mnt/boot/efi/EFI/WolfLinux/grubx64.efi "$fallback_efi" 2>/dev/null || true
    fi

    ok "GRUB, kernel, initramfs e arquivos de boot validados."
}

install_wolf_multimonitor_all_desktops() {
    info "Instalando suporte Wolf MultiMonitor para $DESKTOP..."

    mkdir -p /mnt/usr/local/bin /mnt/etc/xdg/autostart

    if [[ "$DESKTOP" == "plasma" ]]; then
        cat > /mnt/usr/local/bin/wolf-plasma-multimonitor <<'WOLF_PLASMA_MM'
#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.3"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/plasma-multimonitor"
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/wolf-linux"
DISABLED_MARKER="$CONFIG_ROOT/plasma-multimonitor.disabled"
PLASMA_CONFIG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

log()  { printf '\033[1;34m[Wolf Plasma MultiMonitor]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

check_environment() {
    case "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" in
        *KDE*|*Plasma*) ;;
        *) die "Este helper é somente para KDE Plasma." ;;
    esac
    command -v qdbus6 >/dev/null 2>&1 || die "qdbus6 não encontrado."
}

wait_plasma_ready() {
    local _
    for _ in {1..40}; do
        if qdbus6 org.kde.plasmashell /PlasmaShell \
            org.kde.PlasmaShell.evaluateScript 'print("wolf-ready")' \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

plasma_eval() {
    local script="$1"
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script"
}

make_backup() {
    mkdir -p "$STATE_ROOT"
    local stamp dir
    stamp="$(date +%Y%m%d-%H%M%S)"
    dir="$STATE_ROOT/$stamp"
    mkdir -p "$dir"
    [[ -f "$PLASMA_CONFIG" ]] && cp -a "$PLASMA_CONFIG" "$dir/plasma-org.kde.plasma.desktop-appletsrc"
    printf '%s\n' "$dir" > "$STATE_ROOT/latest"
    ok "Backup salvo em $dir"
}

ensure_baseline_backup() {
    local marker="$STATE_ROOT/automatic-baseline"
    [[ -f "$marker" ]] && return 0
    make_backup
    cp "$STATE_ROOT/latest" "$marker"
}

reconcile_plasma() {
    check_environment
    wait_plasma_ready || die "Plasma ainda não ficou pronto para configurar os painéis."

    local js
    read -r -d '' js <<'JS' || true
function uniqueScreens() {
    var seen = {};
    var out = [];
    desktops().forEach(function(d) {
        var s = d.screen;
        if (s >= 0 && !seen[s]) {
            seen[s] = true;
            out.push(s);
        }
    });
    out.sort(function(a, b) { return a - b; });
    return out;
}

function isTaskWidget(w) {
    return w.type === "org.kde.plasma.taskmanager" ||
           w.type === "org.kde.plasma.icontasks";
}

function makeTasksLocal(panel) {
    panel.widgets().forEach(function(w) {
        if (!isTaskWidget(w)) return;
        w.currentConfigGroup = ["General"];
        w.writeConfig("showOnlyCurrentScreen", true);
        w.reloadConfig();
    });
}

function makeKickoffWolf(panel) {
    panel.widgets().forEach(function(w) {
        if (w.type !== "org.kde.plasma.kickoff") return;
        w.currentConfigGroup = ["General"];
        w.writeConfig("icon", "wolf-linux");
        w.reloadConfig();
    });
}

var screens = uniqueScreens();
var allPanels = panels();
var panelForScreen = {};

allPanels.forEach(function(p) {
    if (p.screen >= 0 && panelForScreen[p.screen] === undefined) {
        panelForScreen[p.screen] = p;
    }
    makeTasksLocal(p);
    makeKickoffWolf(p);
});

screens.forEach(function(screen) {
    if (panelForScreen[screen] !== undefined) return;

    var panel = new Panel;
    panel.screen = screen;
    panel.location = "bottom";
    panel.height = Math.round(gridUnit * 2.2);

    var kickoff = panel.addWidget("org.kde.plasma.kickoff");
    kickoff.currentConfigGroup = ["General"];
    kickoff.writeConfig("icon", "wolf-linux");
    kickoff.reloadConfig();

    var tasks = panel.addWidget("org.kde.plasma.icontasks");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("showOnlyCurrentScreen", true);
    tasks.writeConfig("showOnlyCurrentActivity", true);
    tasks.reloadConfig();

    panel.addWidget("org.kde.plasma.panelspacer");
    panel.addWidget("org.kde.plasma.digitalclock");
    panel.addWidget("org.kde.plasma.showdesktop");

    print("Wolf Plasma MultiMonitor: painel criado na tela " + screen + " (id=" + panel.id + ")");
});

panels().forEach(function(p) { makeTasksLocal(p); makeKickoffWolf(p); });
JS
    plasma_eval "$js" >/dev/null
}

show_state() {
    check_environment
    echo
    echo "======================================================"
    echo "       WOLF PLASMA MULTIMONITOR v${VERSION}"
    echo "======================================================"
    echo
    if [[ -e "$DISABLED_MARKER" ]]; then
        log "Configuração automática no login: DESATIVADA"
    else
        log "Configuração automática no login: ATIVADA"
    fi
    log "Watcher permanente: NÃO (Plasma/KScreen gerencia hotplug nativamente)"
    echo
    plasma_eval '
        print("Painéis:");
        panels().forEach(function(p) {
            print("  panel" + p.id + " screen=" + p.screen + " location=" + p.location);
            p.widgets().forEach(function(w) {
                if (w.type === "org.kde.plasma.taskmanager" || w.type === "org.kde.plasma.icontasks") {
                    w.currentConfigGroup = ["General"];
                    print("    " + w.type + " showOnlyCurrentScreen=" + w.readConfig("showOnlyCurrentScreen"));
                }
            });
        });
    '
}

disable_automatic() {
    mkdir -p "$CONFIG_ROOT"
    : > "$DISABLED_MARKER"
    ok "Configuração automática do Plasma no login desativada; painéis existentes foram preservados."
}

enable_automatic() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    rm -f "$DISABLED_MARKER"
    ensure_baseline_backup
    reconcile_plasma
    ok "Configuração automática do Plasma ativada sem watcher permanente."
}

restore_latest() {
    check_environment
    disable_automatic >/dev/null
    [[ -f "$STATE_ROOT/latest" ]] || die "Nenhum backup encontrado."
    local dir
    dir="$(cat "$STATE_ROOT/latest")"
    [[ -f "$dir/plasma-org.kde.plasma.desktop-appletsrc" ]] || die "Backup inválido: $dir"
    cp -a "$dir/plasma-org.kde.plasma.desktop-appletsrc" "$PLASMA_CONFIG"
    if systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1; then
        :
    else
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        nohup plasmashell --replace >/dev/null 2>&1 &
    fi
    ok "Layout Plasma restaurado; configuração automática ficou desativada."
}

apply_now() {
    check_environment
    mkdir -p "$CONFIG_ROOT" "$STATE_ROOT"
    [[ ! -e "$DISABLED_MARKER" ]] || exit 0
    ensure_baseline_backup
    reconcile_plasma
    ok "Painéis Plasma reconciliados; sem watcher/polling permanente."
}

watch_compat() {
    warn "O modo watch foi removido na v${VERSION} para eliminar polling periódico."
    warn "Executando uma reconciliação única; hotplug fica a cargo do Plasma/KScreen."
    apply_now
}

usage() {
    cat <<EOF2
Uso: $(basename "$0") {status|apply|reconcile|watch|enable|disable|restore}
EOF2
}

case "${1:-status}" in
    status) show_state ;;
    apply) apply_now ;;
    reconcile) reconcile_plasma ;;
    watch) watch_compat ;;
    enable) enable_automatic ;;
    disable) disable_automatic ;;
    restore) restore_latest ;;
    *) usage; exit 2 ;;
esac
WOLF_PLASMA_MM
        chmod 755 /mnt/usr/local/bin/wolf-plasma-multimonitor

        cat > /mnt/etc/xdg/autostart/wolf-plasma-multimonitor.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Plasma MultiMonitor
Comment=Configura painéis por monitor sem watcher permanente
Exec=/usr/local/bin/wolf-plasma-multimonitor apply
OnlyShowIn=KDE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

        ok "Wolf MultiMonitor para Plasma instalado em modo one-shot, sem polling permanente."
    fi

    if [[ "$DESKTOP" == "mate" ]]; then
        mkdir -p /mnt/usr/lib/wolf-linux/mate
        mkdir -p /mnt/usr/share/mate-panel/applets
        mkdir -p /mnt/usr/share/dbus-1/services

        cat > /mnt/usr/lib/wolf-linux/mate/wolf-monitor-tasks.py <<'WOLF_MATE_APPLET'
#!/usr/bin/env python3
# Wolf Linux - MATE Monitor Tasks
# Lista de janelas limitada ao monitor onde a instância do applet está.

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Wnck", "3.0")
gi.require_version("MatePanelApplet", "4.0")

from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, MatePanelApplet, Pango, Wnck

try:
    Wnck.set_client_type(Wnck.ClientType.PAGER)
except Exception:
    pass


class MonitorTasks:
    def __init__(self, applet):
        self.applet = applet
        self.screen = Wnck.Screen.get_default()
        self.box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.box.set_hexpand(True)
        self.applet.add(self.box)

        try:
            self.applet.set_flags(MatePanelApplet.AppletFlags.EXPAND_MAJOR)
        except Exception:
            pass

        self.applet.connect("realize", self._schedule_refresh)
        self.applet.connect("size-allocate", self._schedule_refresh)

        for signal in ("window-opened", "window-closed", "active-window-changed", "active-workspace-changed"):
            try:
                self.screen.connect(signal, self._schedule_refresh)
            except Exception:
                pass

        self._last_signature = None
        GLib.timeout_add(700, self._poll)
        self.applet.show_all()

    def _schedule_refresh(self, *args):
        GLib.idle_add(self.refresh)

    def _monitor_geometry(self):
        gdk_window = self.applet.get_window()
        if gdk_window is None:
            return None
        display = gdk_window.get_display()
        monitor = display.get_monitor_at_window(gdk_window)
        if monitor is None:
            return None
        return monitor.get_geometry()

    @staticmethod
    def _window_center(window):
        x, y, w, h = window.get_geometry()
        return x + max(w, 1) // 2, y + max(h, 1) // 2

    def _is_on_this_monitor(self, window, geom):
        cx, cy = self._window_center(window)
        return geom.x <= cx < geom.x + geom.width and geom.y <= cy < geom.y + geom.height

    def _visible_windows(self):
        self.screen.force_update()
        geom = self._monitor_geometry()
        if geom is None:
            return []

        workspace = self.screen.get_active_workspace()
        windows = []
        for window in self.screen.get_windows_stacked():
            try:
                if window.is_skip_tasklist():
                    continue
                if workspace is not None and not (window.is_pinned() or window.is_on_workspace(workspace)):
                    continue
                if not self._is_on_this_monitor(window, geom):
                    continue
                windows.append(window)
            except Exception:
                continue
        return windows

    @staticmethod
    def _signature(windows):
        items = []
        for w in windows:
            try:
                items.append((w.get_xid(), w.get_name(), w.is_active(), w.is_minimized(), w.get_geometry()))
            except Exception:
                pass
        return tuple(items)

    def _poll(self):
        try:
            windows = self._visible_windows()
            sig = self._signature(windows)
            if sig != self._last_signature:
                self.refresh(windows)
        except Exception:
            pass
        return True

    def _on_clicked(self, button, window):
        timestamp = Gtk.get_current_event_time()
        try:
            if window.is_active() and not window.is_minimized():
                window.minimize()
            else:
                window.unminimize(timestamp)
                window.activate(timestamp)
        except Exception:
            pass

    def _on_button_press(self, button, event, window):
        if event.button == 2:
            try:
                window.close(getattr(event, "time", Gtk.get_current_event_time()))
            except Exception:
                pass
            return True
        return False

    def _make_button(self, window):
        button = Gtk.Button()
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_can_focus(False)

        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        try:
            icon = window.get_mini_icon()
            if icon is not None:
                if icon.get_width() > 20 or icon.get_height() > 20:
                    icon = icon.scale_simple(20, 20, GdkPixbuf.InterpType.BILINEAR)
                content.pack_start(Gtk.Image.new_from_pixbuf(icon), False, False, 0)
        except Exception:
            pass

        title = window.get_name() or "Aplicativo"
        label_text = title if len(title) <= 26 else title[:23] + "…"
        label = Gtk.Label(label=label_text)
        label.set_ellipsize(Pango.EllipsizeMode.END)
        label.set_max_width_chars(26)
        content.pack_start(label, False, False, 0)

        button.add(content)
        button.set_tooltip_text(title)
        button.connect("clicked", self._on_clicked, window)
        button.connect("button-press-event", self._on_button_press, window)
        return button

    def refresh(self, windows=None):
        if windows is None:
            windows = self._visible_windows()
        self._last_signature = self._signature(windows)

        for child in self.box.get_children():
            self.box.remove(child)
            child.destroy()

        for window in windows:
            self.box.pack_start(self._make_button(window), False, False, 0)

        self.box.show_all()
        return False


def applet_factory(applet, iid, data):
    if iid != "WolfMonitorTasksApplet":
        return False
    MonitorTasks(applet)
    return True


MatePanelApplet.Applet.factory_main(
    "WolfMonitorTasksFactory",
    True,
    MatePanelApplet.Applet.__gtype__,
    applet_factory,
    None,
)
WOLF_MATE_APPLET
        chmod 755 /mnt/usr/lib/wolf-linux/mate/wolf-monitor-tasks.py

        cat > /mnt/usr/share/mate-panel/applets/org.wolflinux.panel.WolfMonitorTasks.mate-panel-applet <<'EOF'
[Applet Factory]
Id=WolfMonitorTasksFactory
InProcess=false
Location=/usr/lib/wolf-linux/mate/wolf-monitor-tasks.py
Name=Wolf Monitor Tasks Factory
Description=Task list filtered to the monitor containing the MATE panel

[WolfMonitorTasksApplet]
Name=Wolf Monitor Tasks
Description=Mostra apenas as janelas do monitor deste painel
Icon=preferences-system-windows
MateComponentId=OAFIID:WolfLinux_WolfMonitorTasksApplet;
EOF

        cat > /mnt/usr/share/dbus-1/services/org.mate.panel.applet.WolfMonitorTasksFactory.service <<'EOF'
[D-BUS Service]
Name=org.mate.panel.applet.WolfMonitorTasksFactory
Exec=/usr/bin/python3 /usr/lib/wolf-linux/mate/wolf-monitor-tasks.py
EOF

        cat > /mnt/usr/local/bin/wolf-mate-multimonitor <<'WOLF_MATE_MM'
#!/usr/bin/env python3
# Wolf Linux - MATE MultiMonitor
# Experimental until validated on real multi-monitor MATE hardware.

import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gio, Gdk

VERSION = "0.3"
STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "wolf-linux" / "mate-multimonitor"
CONFIG_ROOT = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wolf-linux"
ENABLED_MARKER = CONFIG_ROOT / "mate-multimonitor.enabled"
PID_FILE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / f"wolf-mate-multimonitor-{os.getuid()}.pid"
APPLET_DESCRIPTOR = Path("/usr/share/mate-panel/applets/org.wolflinux.panel.WolfMonitorTasks.mate-panel-applet")


def die(msg):
    print(f"[ERRO] {msg}", file=sys.stderr)
    raise SystemExit(1)


def check_env():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", os.environ.get("XDG_SESSION_DESKTOP", ""))
    if "MATE" not in desktop.upper():
        die("Este helper é somente para MATE.")
    if os.environ.get("XDG_SESSION_TYPE", "x11") != "x11":
        die("O Wolf MultiMonitor para MATE foi projetado para X11.")
    if Gdk.Display.get_default() is None:
        die("Não foi possível acessar o display GTK/GDK atual.")
    if not APPLET_DESCRIPTOR.exists():
        die("Wolf Monitor Tasks não está instalado.")


def gdk_monitor_records():
    """Return monitors exactly as GTK/MATE sees them.

    mate-panel places panels by GDK/Xinerama monitor index.  RandR 1.5
    logical monitors created with `xrandr --setmonitor` are not necessarily
    exposed as distinct GdkMonitor objects, so using xrandr here can create
    unusable/overlapping panels.
    """
    display = Gdk.Display.get_default()
    if display is None:
        return []

    records = []
    for idx in range(display.get_n_monitors()):
        mon = display.get_monitor(idx)
        geo = mon.get_geometry()
        records.append({
            "index": idx,
            "x": geo.x,
            "y": geo.y,
            "width": geo.width,
            "height": geo.height,
            "scale": mon.get_scale_factor(),
            "manufacturer": mon.get_manufacturer() or "",
            "model": mon.get_model() or "",
        })
    return records


def gdk_monitors():
    return [m["index"] for m in gdk_monitor_records()]


def topology_signature():
    rows = []
    for m in gdk_monitor_records():
        rows.append(
            f"{m['index']}:{m['width']}x{m['height']}+{m['x']}+{m['y']}"
            f":scale={m['scale']}:{m['manufacturer']}:{m['model']}"
        )
    return "\n".join(rows)


def general_settings():
    return Gio.Settings.new("org.mate.panel")


def toplevel_settings(tid):
    return Gio.Settings.new_with_path("org.mate.panel.toplevel", f"/org/mate/panel/toplevels/{tid}/")


def object_settings(oid):
    return Gio.Settings.new_with_path("org.mate.panel.object", f"/org/mate/panel/objects/{oid}/")


def make_backup():
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = STATE_ROOT / stamp
    dest.mkdir(parents=True, exist_ok=True)
    with (dest / "mate-panel.dconf").open("w") as f:
        subprocess.run(["dconf", "dump", "/org/mate/panel/"], stdout=f, check=True)
    (STATE_ROOT / "latest").write_text(str(dest) + "\n")
    print(f"[OK] Backup salvo em {dest}")
    return dest


def ensure_baseline_backup():
    marker = STATE_ROOT / "automatic-baseline"
    if marker.exists():
        return
    dest = make_backup()
    marker.write_text(str(dest) + "\n")


def set_applet_object(oid, panel_id, iid, pack="start", index=0, position=0):
    s = object_settings(oid)
    # MATE 1.28 (Arch atual) ainda usa position/panel-right-stick.
    # MATE mais novo adicionou pack-type/pack-index. Detectamos as chaves
    # em runtime para o helper funcionar nas duas gerações do schema.
    keys = set(s.list_keys())

    s.set_string("object-type", "applet")
    s.set_string("applet-iid", iid)
    s.set_string("toplevel-id", panel_id)

    if "pack-type" in keys:
        s.set_string("pack-type", pack)
    if "pack-index" in keys:
        s.set_int("pack-index", index)
    if "position" in keys:
        s.set_int("position", position)
    if "panel-right-stick" in keys:
        s.set_boolean("panel-right-stick", pack == "end")
    if "locked" in keys:
        s.set_boolean("locked", True)


def reconcile():
    check_env()
    monitors = gdk_monitors()
    if not monitors:
        die("Nenhum monitor ativo detectado.")

    general = general_settings()
    toplevel_ids = list(general.get_strv("toplevel-id-list"))
    object_ids = list(general.get_strv("object-id-list"))

    panel_by_monitor = {}
    for tid in toplevel_ids:
        try:
            s = toplevel_settings(tid)
            mon = s.get_int("monitor")
            if mon not in panel_by_monitor:
                panel_by_monitor[mon] = tid
        except Exception:
            continue

    created_panels = []
    for mon in monitors:
        if mon in panel_by_monitor:
            continue
        tid = f"wolf-monitor-{mon}"
        suffix = 1
        while tid in toplevel_ids:
            suffix += 1
            tid = f"wolf-monitor-{mon}-{suffix}"
        s = toplevel_settings(tid)
        s.set_string("name", f"Wolf Monitor {mon}")
        s.set_int("screen", 0)
        s.set_int("monitor", mon)
        s.set_boolean("expand", True)
        s.set_string("orientation", "bottom")
        s.set_int("size", 28)
        s.set_boolean("auto-hide", False)
        toplevel_ids.append(tid)
        panel_by_monitor[mon] = tid
        created_panels.append((mon, tid))

    # Remove Window List nativa apenas dos painéis em monitores ativos e
    # substitua pelo applet Wolf, preservando as configurações antigas no dconf.
    active_panels = {panel_by_monitor[m] for m in monitors}
    filtered_objects = []
    for oid in object_ids:
        try:
            s = object_settings(oid)
            iid = s.get_string("applet-iid")
            panel_id = s.get_string("toplevel-id")
        except Exception:
            filtered_objects.append(oid)
            continue
        if panel_id in active_panels and iid == "WnckletFactory::WindowListApplet":
            continue
        filtered_objects.append(oid)
    object_ids = filtered_objects

    def has_iid(panel_id, iid):
        for oid in object_ids:
            try:
                s = object_settings(oid)
                if s.get_string("toplevel-id") == panel_id and s.get_string("applet-iid") == iid:
                    return True
            except Exception:
                pass
        return False

    def add_unique(base):
        oid = base
        n = 1
        while oid in object_ids:
            n += 1
            oid = f"{base}-{n}"
        object_ids.append(oid)
        return oid

    for mon in monitors:
        panel = panel_by_monitor[mon]

        if not has_iid(panel, "BriskMenuFactory::BriskMenu"):
            oid = add_unique(f"wolf-brisk-m{mon}")
            set_applet_object(oid, panel, "BriskMenuFactory::BriskMenu", "start", 0, 0)

        if not has_iid(panel, "WolfMonitorTasksFactory::WolfMonitorTasksApplet"):
            oid = add_unique(f"wolf-tasks-m{mon}")
            set_applet_object(oid, panel, "WolfMonitorTasksFactory::WolfMonitorTasksApplet", "start", 1, 42)

        if not has_iid(panel, "ClockAppletFactory::ClockApplet"):
            oid = add_unique(f"wolf-clock-m{mon}")
            set_applet_object(oid, panel, "ClockAppletFactory::ClockApplet", "end", 0, 42)

        if not has_iid(panel, "WnckletFactory::ShowDesktopApplet"):
            oid = add_unique(f"wolf-showdesktop-m{mon}")
            set_applet_object(oid, panel, "WnckletFactory::ShowDesktopApplet", "end", 1, 0)

    general.set_strv("toplevel-id-list", toplevel_ids)
    general.set_strv("object-id-list", object_ids)
    Gio.Settings.sync()

    for mon, tid in created_panels:
        print(f"Wolf MATE MultiMonitor: painel criado no monitor {mon}: {tid}")


def show_status():
    check_env()
    print(f"Wolf MATE MultiMonitor v{VERSION}")
    print(f"Experimental habilitado: {'sim' if ENABLED_MARKER.exists() else 'não'}")
    records = gdk_monitor_records()
    print("Monitores GTK/GDK:", [m["index"] for m in records])
    for m in records:
        print(f"  GDK {m['index']}: {m['width']}x{m['height']}+{m['x']}+{m['y']} modelo={m['model'] or '?'}")
    g = general_settings()
    for tid in g.get_strv("toplevel-id-list"):
        s = toplevel_settings(tid)
        print(f"  painel {tid}: monitor={s.get_int('monitor')} orientação={s.get_string('orientation')}")
    print("Wolf Monitor Tasks:")
    for oid in g.get_strv("object-id-list"):
        s = object_settings(oid)
        if s.get_string("applet-iid") == "WolfMonitorTasksFactory::WolfMonitorTasksApplet":
            print(f"  {oid} -> {s.get_string('toplevel-id')}")


def stop_watch():
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, signal.SIGTERM)
        except Exception:
            pass
        PID_FILE.unlink(missing_ok=True)


def enable():
    check_env()
    CONFIG_ROOT.mkdir(parents=True, exist_ok=True)
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    ENABLED_MARKER.touch()
    ensure_baseline_backup()
    reconcile()
    subprocess.Popen([sys.argv[0], "watch"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print("[OK] Wolf MultiMonitor experimental para MATE habilitado.")


def disable():
    ENABLED_MARKER.unlink(missing_ok=True)
    stop_watch()
    print("[OK] Wolf MultiMonitor para MATE desativado; painéis existentes foram preservados.")


def restore():
    disable()
    latest = STATE_ROOT / "latest"
    if not latest.exists():
        die("Nenhum backup encontrado.")
    src = Path(latest.read_text().strip()) / "mate-panel.dconf"
    if not src.exists():
        die("Backup inválido.")
    subprocess.run(["dconf", "reset", "-f", "/org/mate/panel/"], check=True)
    with src.open() as f:
        subprocess.run(["dconf", "load", "/org/mate/panel/"], stdin=f, check=True)
    subprocess.Popen(["mate-panel", "--replace"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print("[OK] Configuração MATE restaurada e automação desativada.")


def watch():
    check_env()
    if not ENABLED_MARKER.exists():
        return
    if PID_FILE.exists():
        try:
            old = int(PID_FILE.read_text().strip())
            os.kill(old, 0)
            return
        except Exception:
            pass
    PID_FILE.write_text(str(os.getpid()) + "\n")

    def cleanup(*_):
        PID_FILE.unlink(missing_ok=True)
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)
    time.sleep(8)
    previous = ""
    while ENABLED_MARKER.exists():
        current = topology_signature()
        if current and current != previous:
            time.sleep(2)
            ensure_baseline_backup()
            try:
                reconcile()
            except Exception as exc:
                print(f"Wolf MATE MultiMonitor: {exc}", file=sys.stderr)
            previous = current
        time.sleep(3)
    cleanup()


def apply():
    check_env()
    make_backup()
    reconcile()
    print("[OK] Configuração multi-monitor MATE aplicada.")


def usage():
    print(f"Uso: {Path(sys.argv[0]).name} status|apply|reconcile|enable|disable|restore|watch")


cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
if cmd == "status":
    show_status()
elif cmd == "apply":
    apply()
elif cmd == "reconcile":
    reconcile()
elif cmd == "enable":
    enable()
elif cmd == "disable":
    disable()
elif cmd == "restore":
    restore()
elif cmd == "watch":
    watch()
else:
    usage()
    raise SystemExit(2)
WOLF_MATE_MM
        chmod 755 /mnt/usr/local/bin/wolf-mate-multimonitor

        cat > /mnt/etc/xdg/autostart/wolf-mate-multimonitor.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - MATE MultiMonitor (experimental)
Comment=Gerenciamento multi-monitor experimental para MATE
Exec=/usr/local/bin/wolf-mate-multimonitor watch
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

        ok "Wolf MultiMonitor para MATE instalado em modo experimental (não habilitado automaticamente)."
        info "Após teste em hardware: wolf-mate-multimonitor enable"
    fi

    cat > /mnt/usr/local/bin/wolf-multimonitor <<'EOF'
#!/usr/bin/env bash
set -e
DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in
    *Cinnamon*) exec /usr/local/bin/wolf-cinnamon-multimonitor "$@" ;;
    *MATE*) exec /usr/local/bin/wolf-mate-multimonitor "$@" ;;
    *KDE*|*Plasma*) exec /usr/local/bin/wolf-plasma-multimonitor "$@" ;;
    *XFCE*|*Xfce*) exec /usr/local/bin/wolf-xfce-multimonitor "$@" ;;
    *) echo "[ERRO] Desktop não suportado pelo Wolf MultiMonitor: $DESKTOP" >&2; exit 1 ;;
esac
EOF
    chmod 755 /mnt/usr/local/bin/wolf-multimonitor
}

# Personaliza o layout PADRÃO do Plasma, antes do primeiro login do usuário.
# Sem scripts em autostart: o layout não deve fixar o Discover no painel.
install_wolf_plasma_panel_defaults() {
    info "Ajustando layout padrão do Plasma: removendo atalho Discover..."
    local pruner="$PROJECT_DIR/tests/wolf-prune-discover-launchers.py"
    [[ -f "$pruner" ]] || die "Limpador do painel Plasma ausente: $pruner"
    command -v python >/dev/null 2>&1 || die 'Python não disponível na live para ajustar layout Plasma.'
    python "$pruner" /mnt
    if arch-chroot /mnt pacman -Q discover >/dev/null 2>&1; then
        die 'Discover foi instalado indevidamente (dependência de metapacote ou stack).'
    fi
    if arch-chroot /mnt pacman -Q plasma-meta >/dev/null 2>&1; then
        die 'plasma-meta instalado: ele depende do Discover. Verifique as stacks.'
    fi
    ok 'Baseline Plasma sem Discover e painel padrão revisado.'
}

install_wolf_helper_bundle() {
    local source_root="$PROJECT_DIR/tools"
    local target_root="/mnt/usr/local/lib/wolf-linux/helpers"
    info "Instalando helpers Wolf (Branding/MultiMonitor uma vez no login; demais manuais)..."
    rm -rf "$target_root"
    install -d "$target_root/stable" "$target_root/experimental" /mnt/usr/local/bin /mnt/etc/wolf-linux

    local dir file
    for dir in stable experimental; do
        if [[ -d "$source_root/$dir" ]]; then
            while IFS= read -r -d '' file; do
                install -m 0755 "$file" "$target_root/$dir/$(basename "$file")"
            done < <(find "$source_root/$dir" -maxdepth 1 -type f -print0)
        fi
    done

    if [[ -f "$source_root/wolf-helper-manager-0.2.sh" ]]; then
        install -m 0755 "$source_root/wolf-helper-manager-0.2.sh" /mnt/usr/local/bin/wolf-helper
    fi
    if [[ -f "$source_root/wolf-validate-helpers-0.1.sh" ]]; then
        install -m 0755 "$source_root/wolf-validate-helpers-0.1.sh" /mnt/usr/local/bin/wolf-validate-helpers
    fi

    # Only the two VM-validated Plasma helpers run once at the first login.
    # Other helpers remain strictly manual.
    if [[ -f "$source_root/wolf-first-login-plasma.sh" ]]; then
        install -m 0755 "$source_root/wolf-first-login-plasma.sh" /mnt/usr/local/bin/wolf-first-login-plasma
    else
        die 'Configurador one-shot do Plasma ausente.'
    fi

    # Control Center usa PySide6 dos repos oficiais. UI não executa watchers.
    local gui_source="$source_root/control-center"
    local gui_target="/mnt/usr/local/lib/wolf-linux/control-center"
    [[ -f "$gui_source/main.py" && -f "$gui_source/backend.py" ]] || \
        die "Fontes do Wolf Control Center ausentes."
    install -d "$gui_target" /mnt/usr/share/applications
    install -m 0644 "$gui_source/main.py" "$gui_target/main.py"
    install -m 0644 "$gui_source/backend.py" "$gui_target/backend.py"
    cat > /mnt/usr/local/bin/wolf-control-center <<'WOLF_CC_WRAPPER'
#!/usr/bin/env sh
exec /usr/bin/python3 /usr/local/lib/wolf-linux/control-center/main.py "$@"
WOLF_CC_WRAPPER
    chmod 0755 /mnt/usr/local/bin/wolf-control-center
    install -m 0644 "$gui_source/wolf-control-center.desktop" \
        /mnt/usr/share/applications/wolf-control-center.desktop

    # Stable tools get friendly command names; they are still manual tools.
    [[ -f "$target_root/stable/wolf-grub-manager-0.3.sh" ]] && \
        ln -sfn ../lib/wolf-linux/helpers/stable/wolf-grub-manager-0.3.sh /mnt/usr/local/bin/wolf-grub-manager
    [[ -f "$target_root/stable/wolf-gamepad-setup-0.3.sh" ]] && \
        ln -sfn ../lib/wolf-linux/helpers/stable/wolf-gamepad-setup-0.3.sh /mnt/usr/local/bin/wolf-gamepad-setup

    cat > /mnt/etc/wolf-linux/install-stacks.conf <<EOF
WOLF_VERSION=$WOLF_VERSION
DESKTOP=plasma-wayland
STACKS=$(selected_stacks_text)
EOF

    # Guardrail: no system-wide Wolf helper autostart; only the installed
    # user's own one-time launcher is created by the profile configurator.
    if find /mnt/etc/xdg/autostart -maxdepth 1 -type f -name 'wolf-*.desktop' -print -quit 2>/dev/null | grep -q .; then
        warn "Removendo autostarts Wolf globais herdados: mantido apenas o setup unico do usuario."
        find /mnt/etc/xdg/autostart -maxdepth 1 -type f -name 'wolf-*.desktop' -delete
    fi
    ok "Helpers copiados. Use 'wolf-helper list' para inspecioná-los após o boot."
}

finalize_vm_install() {
    sync
    echo
    echo "============================================================"
    echo "         WOLF LINUX 2.0 — INSTALAÇÃO CONCLUÍDA"
    echo "============================================================"
    echo "Desktop ....: KDE Plasma / Wayland"
    echo "Usuário ....: $USERNAME_VALUE"
    echo "GPU ........: $GPU_PROFILE"
    echo "Stacks .....: $(selected_stacks_text)"
    echo "Kernel .....: linux-zen + linux-lts fallback"
    echo "Plasma ......: Branding/MultiMonitor one-shot no primeiro login"
    echo "Outros helpers: Gamepad e GRUB permanecem manuais"
    echo
    echo "Após o primeiro boot:"
    echo "  wolf-helper list"
    echo "  wolf-helper validate"
    echo "  wolf-control-center"
    echo "  wolf-grub-manager"
    echo "  wolf-gamepad-setup"
    if [[ -s "$STATE_DIR/optional-failures.log" ]]; then
        echo
        warn 'Instalação do sistema concluída COM PENDÊNCIAS OPCIONAIS:'
        cat "$STATE_DIR/optional-failures.log"
        echo 'Registro: /var/log/wolf-optional-failures.log no sistema instalado.'
    fi
    echo "============================================================"
}

load_gui_physical_plan() {
    [[ -n "$GUI_PHYSICAL_PLAN" ]] || return 0
    (( EUID == 0 )) || die 'Plano físico exige root.'
    [[ "$BOOT_MODE" == UEFI ]] || die 'Plano físico exige UEFI.'
    is_supported_test_vm && die 'Execução física recusada dentro de VM.'
    [[ -d /run/archiso/airootfs ]] || die 'Execução física exige a Live Wolf.'
    local temp
    temp="$(mktemp /tmp/wolf47-physical.XXXXXXXX)"
    chmod 600 "$temp"
    if ! /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_physical_executor.py" export "$GUI_PHYSICAL_PLAN" > "$temp"; then
        rm -f -- "$temp"
        die 'Pré-validação física recusada; nenhuma operação destrutiva realizada.'
    fi
    local -a f=()
    mapfile -d '' -t f < "$temp"
    rm -f -- "$temp"
    (( ${#f[@]} == 12 )) || die 'Contrato físico incompleto.'
    ROOT_DEVICE="${f[0]}"; ESP_DEVICE="${f[1]}"; HOME_DEVICE="${f[2]}"
    PHYSICAL_ROOT_UUID="${f[3]}"; PHYSICAL_ESP_UUID="${f[4]}"; PHYSICAL_HOME_UUID="${f[5]}"
    HOSTNAME_VALUE="${f[6]}"; USERNAME_VALUE="${f[7]}"; STACK_PRESET="${f[8]}"
    if [[ "$STACK_PRESET" == custom ]]; then
        STACKS_ARG="${f[9]}"
        [[ -n "$STACKS_ARG" ]] || die 'Custom sem stacks não suportado.'
    else
        STACKS_ARG=""
    fi
    XKB_LAYOUT="${f[10]}"; XKB_VARIANT="${f[11]}"
    if [[ "$XKB_VARIANT" == thinkpad ]]; then
        KEYBOARD_PROFILE=thinkpad
        CINNAMON_LAYOUT=br+thinkpad
        MATE_LAYOUT=$'br\tthinkpad'
    else
        KEYBOARD_PROFILE=abnt2
        XKB_LAYOUT=br
        XKB_VARIANT=abnt2
        CINNAMON_LAYOUT=br
        MATE_LAYOUT=$'br\tabnt2'
    fi
    STORAGE_MODE="reuse-manual"
    GUI_VM_MODE="reuse" # preservar ESP sem instalação fallback
    INSTALL_DISK="${ROOT_DEVICE%p[0-9]*}" # usado apenas para planejamento; NUNCA apagado
    FORMAT_ROOT=yes; FORMAT_ESP=no; FORMAT_HOME=no; CLEAN_HOME_DOTFILES=no
    PHYSICAL_PLAN_SHA256="$(sha256sum "$GUI_PHYSICAL_PLAN" | cut -d' ' -f1)"
    ok "FÍSICO: formatar somente $ROOT_DEVICE; preservar $ESP_DEVICE e $HOME_DEVICE."
}

revalidate_gui_physical_target() {
    [[ -n "$GUI_PHYSICAL_PLAN" ]] || return 0
    [[ "$(sha256sum "$GUI_PHYSICAL_PLAN" | cut -d' ' -f1)" == "$PHYSICAL_PLAN_SHA256" ]] ||
        die 'Plano físico foi modificado depois do consentimento: ABORTADO.'
    local temp
    temp="$(mktemp /tmp/wolf47-recheck.XXXXXXXX)"
    chmod 600 "$temp"
    if ! /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_physical_executor.py" export "$GUI_PHYSICAL_PLAN" > "$temp"; then
        rm -f -- "$temp"
        die 'UUID, fstab, topologia LVM ou dispositivo mudou: ABORTAR SEM FORMATAR.'
    fi
    local -a f=()
    mapfile -d '' -t f < "$temp"
    rm -f -- "$temp"
    (( ${#f[@]} == 12 )) || die 'Revalidação física incompleta.'
    [[ "${f[0]}" == "$ROOT_DEVICE" && "${f[1]}" == "$ESP_DEVICE" &&
       "${f[2]}" == "$HOME_DEVICE" && "${f[3]}" == "$PHYSICAL_ROOT_UUID" &&
       "${f[4]}" == "$PHYSICAL_ESP_UUID" && "${f[5]}" == "$PHYSICAL_HOME_UUID" &&
       "${f[6]}" == "$HOSTNAME_VALUE" && "${f[7]}" == "$USERNAME_VALUE" &&
       "${f[8]}" == "$STACK_PRESET" ]] || die 'Identidade do plano físico mudou.'
    ok 'Dispositivos físicos revalidados por UUID, partuuid, fstab e PVs.'
}

load_gui_lab42_plan() {
    [[ -n "$GUI_LAB42_PLAN" ]] || return 0
    (( EUID == 0 )) || die 'Laboratório alpha42 exige root.'
    [[ "$BOOT_MODE" == UEFI ]] || die 'Laboratório alpha42 exige UEFI.'
    [[ "$VM_TYPE" == qemu || "$VM_TYPE" == kvm ]] || die 'Laboratório somente QEMU/KVM.'
    local temp
    temp="$(mktemp /tmp/wolf42-fields.XXXXXXXX)"
    chmod 600 "$temp"
    if ! /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_lab42.py" export "$GUI_LAB42_PLAN" > "$temp"; then
        rm -f -- "$temp"
        die 'Preflight multidisco alpha42 recusado. NADA formatado.'
    fi
    local -a f=()
    mapfile -d '' -t f < "$temp"
    rm -f -- "$temp"
    (( ${#f[@]} == 12 )) || die 'Contrato Lab42 incompleto.'
    ROOT_DEVICE="${f[0]}"; ESP_DEVICE="${f[1]}"; HOME_DEVICE="${f[2]}"
    LAB42_ROOT_UUID="${f[3]}"; LAB42_ESP_UUID="${f[4]}"; LAB42_HOME_UUID="${f[5]}"
    HOSTNAME_VALUE="${f[6]}"; USERNAME_VALUE="${f[7]}"; STACK_PRESET="${f[8]}"
    if [[ "$STACK_PRESET" == custom ]]; then
        STACKS_ARG="${f[9]}"
        [[ -n "$STACKS_ARG" ]] || die 'Custom sem stacks não suportado.'
    else
        STACKS_ARG=""
    fi
    XKB_LAYOUT="${f[10]}"; XKB_VARIANT="${f[11]}"
    if [[ "$XKB_VARIANT" == thinkpad ]]; then
        KEYBOARD_PROFILE=thinkpad
        CINNAMON_LAYOUT=br+thinkpad
        MATE_LAYOUT=$'br\tthinkpad'
    else
        KEYBOARD_PROFILE=abnt2
        XKB_LAYOUT=br
        XKB_VARIANT=abnt2
        CINNAMON_LAYOUT=br
        MATE_LAYOUT=$'br\tabnt2'
    fi
    STORAGE_MODE="reuse-manual"
    GUI_VM_MODE="reuse" # GRUB: NÃO sobrescrever EFI/BOOT fallback
    INSTALL_DISK=/dev/vdb
    FORMAT_ROOT=yes; FORMAT_ESP=no; FORMAT_HOME=no; CLEAN_HOME_DOTFILES=no
    [[ "$ROOT_DEVICE" == /dev/vdb1 && "$ESP_DEVICE" == /dev/vda1 &&
       "$HOME_DEVICE" == /dev/mapper/vg_monstro-lv_projetos ]] ||
        die 'Exportador retornou destinos fora do laboratório.'
    ok 'Lab42 validado: FORMATAR /dev/vdb1; PRESERVAR EFI /dev/vda1, NTFS /dev/vdb2 e /home LVM.'
}

revalidate_gui_lab42_target() {
    [[ -n "$GUI_LAB42_PLAN" ]] || return 0
    local temp
    temp="$(mktemp /tmp/wolf42-recheck.XXXXXXXX)"
    chmod 600 "$temp"
    if ! /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_lab42.py" export "$GUI_LAB42_PLAN" > "$temp"; then
        rm -f -- "$temp"
        die 'Revalidação alpha42 mudou antes de FORMATAR; abortado.'
    fi
    local -a f=()
    mapfile -d '' -t f < "$temp"
    rm -f -- "$temp"
    (( ${#f[@]} == 12 )) || die 'Revalidação do laboratório incompleta.'
    [[ "${f[0]}" == "$ROOT_DEVICE" && "${f[1]}" == "$ESP_DEVICE" &&
       "${f[2]}" == "$HOME_DEVICE" && "${f[3]}" == "$LAB42_ROOT_UUID" &&
       "${f[4]}" == "$LAB42_ESP_UUID" && "${f[5]}" == "$LAB42_HOME_UUID" &&
       "${f[6]}" == "$HOSTNAME_VALUE" && "${f[7]}" == "$USERNAME_VALUE" &&
       "${f[8]}" == "$STACK_PRESET" ]] || die 'Plano ou UUID alterado; não formatar.'
    [[ ! -s "$CHECKPOINT_FILE" ]] || die 'Checkpoints existentes; laboratório não retomará uma instalação incerta.'
    ok 'REVALIDAÇÃO LAB42: os dois seriais, três UUIDs e PVs foram conferidos novamente.'
}

load_gui_vm_plan() {
    [[ -n "$GUI_VM_PLAN" ]] || return 0
    (( EUID == 0 )) || die 'A execução VM exige root.'
    if (( GUI_VM_CLICK_CONFIRMED == 1 )); then
        [[ -d /run/archiso/airootfs ]] || die 'Instalação autorizada por cliques exige a sessão Live Archiso.'
    fi
    # Um temporário privado permite capturar corretamente o exit code do Python;
    # process substitution com mapfile ocultaria falhas de validação.
    local tmp
    tmp="$(mktemp /tmp/wolf-gui-fields.XXXXXXXX)"
    chmod 600 "$tmp"
    if ! /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_plan.py" vm-export "$GUI_VM_PLAN" > "$tmp"; then
        rm -f -- "$tmp"
        die 'Plano da GUI reprovado pela validação independente.'
    fi
    local -a fields=()
    mapfile -d '' -t fields < "$tmp"
    rm -f -- "$tmp"
    (( ${#fields[@]} == 19 )) || die 'Contrato JSON devolveu número incorreto de campos.' 
    GUI_VM_DISK="${fields[0]}"
    GUI_VM_MAJMIN="${fields[2]}"
    [[ "$BOOT_MODE" == "${fields[3]}" ]] || die 'Firmware atual diferente do plano.'
    HOSTNAME_VALUE="${fields[4]}"
    USERNAME_VALUE="${fields[5]}"
    STACK_PRESET="${fields[6]}"
    if [[ "$STACK_PRESET" == "custom" ]]; then
        STACKS_ARG="${fields[7]}"
        [[ -n "$STACKS_ARG" ]] || die 'Custom vazio não implementado no primeiro executor VM.'
    else
        STACKS_ARG=""
    fi
    INSTALL_DISK="$GUI_VM_DISK"
    GUI_VM_MODE="${fields[10]}"
    if [[ "$GUI_VM_MODE" == "manual" || "$GUI_VM_MODE" == "reuse" ]]; then
        # BIOS manual/reuse aceitos apenas em VM com MBR; verificação de
        # tabela, identidade e papéis ocorre no validador Python independente.
        [[ "$BOOT_MODE" == "UEFI" || "$BOOT_MODE" == "BIOS" ]] || die 'Firmware desconhecido.' 
        STORAGE_MODE="reuse-manual"
        ROOT_DEVICE="${fields[11]}"
        ESP_DEVICE="${fields[12]}"
        HOME_DEVICE="${fields[13]}"
        FORMAT_ROOT="yes"
        FORMAT_ESP="${fields[14]}"
        FORMAT_HOME="${fields[15]}"
        [[ "$FORMAT_ESP" =~ ^(yes|no)$ && "$FORMAT_HOME" =~ ^(yes|no)$ ]] || die 'Flags de formatação malformadas.'
        if [[ "$GUI_VM_MODE" == "reuse" ]]; then
            [[ -n "$HOME_DEVICE" && "$FORMAT_ESP" == "no" && "$FORMAT_HOME" == "no" ]] ||
                die 'Reutilização exige /home separada e preservada, além de EFI preservada somente em UEFI.'
            if [[ "$BOOT_MODE" == "UEFI" ]]; then
                [[ -n "$ESP_DEVICE" ]] || die 'Reutilização UEFI exige EFI preservada.'
            else
                [[ -z "$ESP_DEVICE" ]] || die 'Reutilização BIOS não deve utilizar EFI.'
            fi
            CLEAN_HOME_DOTFILES="${fields[16]}"
            [[ "$CLEAN_HOME_DOTFILES" =~ ^(yes|no)$ ]] || die 'Limpeza de home malformada.'
        else
            CLEAN_HOME_DOTFILES="no"
        fi
    elif [[ "$GUI_VM_MODE" == "erase" ]]; then
        STORAGE_MODE="erase"
        GUI_ERASE_ROOT_GIB="${fields[17]}"
        GUI_ERASE_HOME_GIB="${fields[18]}"
        [[ "$GUI_ERASE_ROOT_GIB" =~ ^[0-9]{1,5}$ && "$GUI_ERASE_HOME_GIB" =~ ^[0-9]{1,5}$ ]] || die 'Tamanhos automáticos inválidos.'
        case "${fields[13]}" in
            separate) GUI_ERASE_SEPARATE=yes ;;
            '') GUI_ERASE_SEPARATE=no ;;
            *) die 'Formato de /home automático desconhecido.' ;;
        esac
        if [[ "$GUI_ERASE_SEPARATE" == yes ]]; then
            (( GUI_ERASE_ROOT_GIB >= 20 )) || die 'Raiz automática com home separada exige pelo menos 20 GiB.'
        else
            (( GUI_ERASE_HOME_GIB == 0 )) || die 'Home integrada não recebe tamanho separado.'
        fi
        if [[ "$BOOT_MODE" == "UEFI" ]]; then
        ESP_DEVICE="$(partition_path "$INSTALL_DISK" 1)"
        ROOT_DEVICE="$(partition_path "$INSTALL_DISK" 2)"
        FORMAT_ESP="yes"
        else
            ESP_DEVICE=""
            ROOT_DEVICE="$(partition_path "$INSTALL_DISK" 1)"
            FORMAT_ESP="no"
        fi
        if [[ "$GUI_ERASE_SEPARATE" == "yes" ]]; then
            if [[ "$BOOT_MODE" == "UEFI" ]]; then
                HOME_DEVICE="$(partition_path "$INSTALL_DISK" 3)"
            else
                HOME_DEVICE="$(partition_path "$INSTALL_DISK" 2)"
            fi
        else
            HOME_DEVICE=""
        fi
        FORMAT_ROOT="yes"
        FORMAT_HOME="yes"
        CLEAN_HOME_DOTFILES="no"
    else
        die "Estratégia GUI desconhecida: $GUI_VM_MODE"
    fi
    XKB_LAYOUT="${fields[8]}"
    XKB_VARIANT="${fields[9]}"
    case "$XKB_LAYOUT:$XKB_VARIANT" in
        br:thinkpad) KEYBOARD_PROFILE=thinkpad; CINNAMON_LAYOUT=br+thinkpad; MATE_LAYOUT=$'br\tthinkpad' ;;
        br:abnt2|br:) KEYBOARD_PROFILE=abnt2; XKB_VARIANT=abnt2; CINNAMON_LAYOUT=br; MATE_LAYOUT=$'br\tabnt2' ;;
        us:|pt:|es:|fr:|de:|it:)
            KEYBOARD_PROFILE="$XKB_LAYOUT"; CINNAMON_LAYOUT="$XKB_LAYOUT"; MATE_LAYOUT="$XKB_LAYOUT" ;;
        *) die 'Teclado recebido fora da lista permitida.' ;;
    esac
    ok "Plano gráfico importado: $INSTALL_DISK; usuário=$USERNAME_VALUE; perfil=$STACK_PRESET; $BOOT_MODE"
}

revalidate_gui_vm_target() {
    [[ -n "$GUI_VM_PLAN" ]] || return 0
    local tmp
    tmp="$(mktemp /tmp/wolf-gui-recheck.XXXXXXXX)"
    chmod 600 "$tmp"
    if ! /usr/bin/python3 "$PROJECT_DIR/live-gui/wolf_plan.py" vm-export "$GUI_VM_PLAN" > "$tmp"; then
        rm -f -- "$tmp"
        die 'Disco ou plano VM alterado antes da operação destrutiva. ABORTADO.'
    fi
    local -a fields=()
    mapfile -d '' -t fields < "$tmp"
    rm -f -- "$tmp"
    (( ${#fields[@]} == 19 )) || die 'Revalidação VM com dados incompletos.' 
    [[ "${fields[0]}" == "$INSTALL_DISK" && "${fields[2]}" == "$GUI_VM_MAJMIN" ]] ||
        die 'Disco/identidade da VM mudou após confirmação.'
    [[ -b "$INSTALL_DISK" && ! -L "$INSTALL_DISK" ]] || die 'Disco de destino deixou de ser um dispositivo de bloco válido.'
    [[ "${fields[10]}" == "$GUI_VM_MODE" ]] || die 'Modo GUI mudou após confirmação.'
    if [[ "$GUI_VM_MODE" == "erase" ]]; then
        local expected_home_role=""
        [[ "$GUI_ERASE_SEPARATE" == yes ]] && expected_home_role=separate
        [[ "${fields[13]}" == "$expected_home_role" &&
           "${fields[17]}" == "$GUI_ERASE_ROOT_GIB" &&
           "${fields[18]}" == "$GUI_ERASE_HOME_GIB" ]] || die 'Layout/tamanhos alterados após confirmação.'
    fi
    if [[ "$GUI_VM_MODE" == "manual" || "$GUI_VM_MODE" == "reuse" ]]; then
        [[ "${fields[11]}" == "$ROOT_DEVICE" && "${fields[12]}" == "$ESP_DEVICE" && "${fields[13]}" == "$HOME_DEVICE" && "${fields[14]}" == "$FORMAT_ESP" && "${fields[15]}" == "$FORMAT_HOME" && "${fields[16]}" == "$CLEAN_HOME_DOTFILES" ]] ||
            die 'Partições ou flags de formatação mudaram; ABORTADO.' 
    fi
    if mountpoint -q /mnt 2>/dev/null; then
        die 'Montagem inesperada em /mnt. Recusando alterar partições.'
    fi
    ok "Destino revalidado imediatamente antes das operações de armazenamento: $INSTALL_DISK ($GUI_VM_MODE)."
}

# Falhas de SDK de terceiros não devem impedir a configuração do boot.
# O subshell mantém errexit ativo dentro de install_flutter_sdk, mesmo quando
# chamado num 'if' de retry. Comando timeout específico para git/flutter abaixo.
install_optional_flutter_sdk() {
    stack_selected android || { info 'Flutter não selecionado; ignorando SDK opcional.'; return 0; }
    local decision status attempt=0
    while true; do
        attempt=$((attempt+1))
        if (set -Eeuo pipefail; install_flutter_sdk); then
            ok 'Flutter/Android SDK concluídos.'
            return 0
        else
            status=$?
        fi
        warn "Flutter/Android falhou (tentativa $attempt, código $status). O sistema básico e o GRUB serão configurados normalmente se você pular."
        printf '%s\n' ' [1] Tentar novamente' ' [2] Pular Flutter e continuar a instalação'
        while true; do
            read -r -p 'Escolha 1 ou 2: ' decision || decision=2
            case "$decision" in
                1) break ;;
                2)
                    printf 'Flutter pendente: etapa 68 falhou (%s), usuário pulou.\n' "$status" >> "$STATE_DIR/optional-failures.log"
                    if [[ -d /mnt/var/log ]]; then
                        cp "$STATE_DIR/optional-failures.log" /mnt/var/log/wolf-optional-failures.log || true
                    fi
                    warn 'Continuando sem validar Flutter. Depois da inicialização, conclua a instalação do SDK manualmente.'
                    return 0 ;;
                *) echo 'Escolha 1 para repetir ou 2 para pular.' ;;
            esac
        done
    done
}

main() {
    banner
    check_runtime
    detect_boot
    detect_cpu
    detect_gpu
    detect_keyboard
    choose_desktop
    if [[ -n "$GUI_PHYSICAL_PLAN" ]]; then
        load_gui_physical_plan
        check_network
        choose_stacks
    elif [[ -n "$GUI_LAB42_PLAN" ]]; then
        load_gui_lab42_plan
        check_network
        choose_stacks
    elif [[ -n "$GUI_VM_PLAN" ]]; then
        load_gui_vm_plan
        check_network
        choose_stacks
    else
        check_network
        choose_stacks
        collect_identity
        storage_planner
        plan_preserved_home_cleanup
    fi
    show_plan
    echo "Stacks ............: $(selected_stacks_text)"
    if [[ -n "$GUI_LAB42_PLAN" ]]; then
        echo 'LAB42: EFI em /dev/vda1; RAIZ /dev/vdb1; /home LVM multi-PV; preservação obrigatória.'
    fi

    if (( DRY_RUN == 1 || PLAN_ONLY == 1 )); then
        ok "Dry-run/plano concluído: nenhuma operação destrutiva executada."
        exit 0
    fi

    confirm_installation
    revalidate_gui_vm_target
    revalidate_gui_lab42_target
    revalidate_gui_physical_target
    confirm_preserved_home_cleanup
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
    # Minimal não seleciona nenhuma stack opcional: não inicializa Chaotic-AUR,
    # yay ou resolução de pacotes AUR. As demais instalações preservam a
    # prioridade Arch oficial -> Chaotic-AUR -> AUR fallback.
    if (( ${#SELECTED_STACKS[@]} == 0 )); then
        ok "Perfil sem stacks opcionais: etapas 63 Chaotic-AUR e 64 AUR ignoradas."
    else
        stage "63-chaotic-aur" configure_chaotic_aur
        stage "63b-vulkan" install_preferred_vulkan_provider
        stage "64-resolver-stacks" install_selected_stack_packages
    fi
    stage "67-servicos" configure_services
    stage "68-android-flutter" install_optional_flutter_sdk
    stage "69-video" install_gpu_profile
    stage "69b-validar-video" validate_graphics_stack
    stage "69c-branding-boot" install_wolf_branding
    stage "69c2-painel-sem-discover" install_wolf_plasma_panel_defaults
    stage "69c3-preferencias-kde" install_wolf_kde_personal_defaults
    stage "69d-helpers-primeiro-login" install_wolf_helper_bundle
    stage "69e-grub-manager" install_wolf_grub_manager
    stage "70-bootloader" configure_bootloader
    stage "72-validar-boot" validate_boot_installation
    stage "80-finalizar" finalize_vm_install
}

main "$@"
