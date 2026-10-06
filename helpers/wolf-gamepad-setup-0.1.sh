#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="Wolf Gamepad Setup"
VERSION="0.1"
XPADNEO_MODULE="hid_xpadneo"
XPADNEO_CONF="/etc/modprobe.d/99-wolf-xpadneo-gamepads.conf"
XPADNEO_LOAD_CONF="/etc/modules-load.d/xpadneo.conf"

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"
}

pause() {
    read -r -p $'\nPressione Enter para continuar...' _ || true
}

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

normalize_mac() {
    tr '[:lower:]' '[:upper:]' <<<"$1"
}

xpadneo_installed() {
    modinfo "$XPADNEO_MODULE" >/dev/null 2>&1
}

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
        dkms "$headers" bluez bluez-utils steam-devices xpadneo-dkms

    printf '%s\n' "$XPADNEO_MODULE" | sudo tee "$XPADNEO_LOAD_CONF" >/dev/null
    sudo modprobe uhid || true
    sudo modprobe "$XPADNEO_MODULE" || true

    ok "Suporte instalado. O xpadneo será carregado cedo nos próximos boots."
}

all_bt_macs() {
    bluetoothctl devices 2>/dev/null | awk '/^Device / {print $2}'
}

is_xbox_bt_device() {
    local mac="$1" info_out
    info_out="$(bluetoothctl info "$mac" 2>/dev/null || true)"
    grep -qiE 'Name: Xbox Wireless Controller|Modalias: usb:v045Ep(02FD|0B05|0B13|0B20|0B22)' <<<"$info_out"
}

xbox_devices() {
    local mac
    while read -r mac; do
        [[ -n "$mac" ]] || continue
        if is_xbox_bt_device "$mac"; then
            local name connected bonded trusted modalias
            name="$(bluetoothctl info "$mac" 2>/dev/null | sed -n 's/^\s*Name: //p' | head -n1)"
            connected="$(bluetoothctl info "$mac" 2>/dev/null | sed -n 's/^\s*Connected: //p' | head -n1)"
            bonded="$(bluetoothctl info "$mac" 2>/dev/null | sed -n 's/^\s*Bonded: //p' | head -n1)"
            trusted="$(bluetoothctl info "$mac" 2>/dev/null | sed -n 's/^\s*Trusted: //p' | head -n1)"
            modalias="$(bluetoothctl info "$mac" 2>/dev/null | sed -n 's/^\s*Modalias: //p' | head -n1)"
            printf '%s|%s|%s|%s|%s|%s\n' "$(normalize_mac "$mac")" "${name:-?}" "${connected:-?}" "${bonded:-?}" "${trusted:-?}" "${modalias:-?}"
        fi
    done < <(all_bt_macs)
}

choose_xbox_device() {
    local -a devs=()
    mapfile -t devs < <(xbox_devices)
    ((${#devs[@]} > 0)) || die "Nenhum controle Xbox Bluetooth conhecido foi encontrado pelo bluetoothctl. Pareie/conecte o controle e tente novamente."

    say "Controles Xbox Bluetooth encontrados:"
    local i row mac name connected bonded trusted modalias
    for i in "${!devs[@]}"; do
        row="${devs[$i]}"
        IFS='|' read -r mac name connected bonded trusted modalias <<<"$row"
        printf '  %d) %s  %s  conectado=%s bonded=%s trusted=%s\n' "$((i+1))" "$mac" "$name" "$connected" "$bonded" "$trusted"
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

    IFS='|' read -r SELECTED_MAC SELECTED_NAME _ _ _ _ <<<"${devs[$((choice-1))]}"
    export SELECTED_MAC SELECTED_NAME
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

add_nintendo_mapping() {
    need_cmd bluetoothctl
    xpadneo_installed || die "hid_xpadneo não está instalado. Use primeiro a opção de instalar suporte."
    choose_xbox_device

    local current new entry
    current="$(read_managed_quirks || true)"
    entry="${SELECTED_MAC}+32"

    if [[ -z "$current" ]]; then
        new="$entry"
    elif tr ',' '\n' <<<"$current" | grep -Fxiq "$entry"; then
        new="$current"
    else
        # Remove uma entrada antiga para o mesmo MAC e acrescenta +32.
        new="$(tr ',' '\n' <<<"$current" | awk -v mac="$SELECTED_MAC" 'BEGIN{IGNORECASE=1} index(toupper($0), toupper(mac)) != 1 && NF {print}' | paste -sd, -)"
        [[ -n "$new" ]] && new+=","
        new+="$entry"
    fi

    write_managed_quirks "$new"
    printf '%s\n' "$new" | sudo tee "/sys/module/${XPADNEO_MODULE}/parameters/quirks" >/dev/null || true

    ok "Layout Nintendo configurado para ${SELECTED_NAME} (${SELECTED_MAC})."
    info "Quirks gerenciadas: $new"

    if bluetoothctl info "$SELECTED_MAC" 2>/dev/null | grep -q 'Connected: yes'; then
        info "Reconectando o controle para aplicar o mapeamento..."
        bluetoothctl disconnect "$SELECTED_MAC" >/dev/null 2>&1 || true
        sleep 2
        bluetoothctl connect "$SELECTED_MAC" >/dev/null 2>&1 || true
        sleep 2
    fi

    if [[ -r "/sys/module/${XPADNEO_MODULE}/parameters/quirks" ]]; then
        info "Parâmetro ativo: $(cat "/sys/module/${XPADNEO_MODULE}/parameters/quirks")"
    fi
    say ""
    info "Na Steam, o controle continuará sendo Xbox-compatible, mas A/B/X/Y seguirão o layout Nintendo no nível do driver."
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

    if [[ -w "/sys/module/${XPADNEO_MODULE}/parameters/quirks" || -e "/sys/module/${XPADNEO_MODULE}/parameters/quirks" ]]; then
        printf '%s\n' "$new" | sudo tee "/sys/module/${XPADNEO_MODULE}/parameters/quirks" >/dev/null || true
    fi

    ok "Mapeamento Nintendo removido para ${SELECTED_MAC}."
    info "Desconecte/reconecte o controle (ou reinicie) para garantir que o novo mapeamento seja aplicado."
}

diagnostics() {
    need_cmd bluetoothctl
    say "--- Kernel ---"
    uname -a
    say ""

    say "--- Pacotes relevantes ---"
    pacman -Q xpadneo-dkms steam-devices bluez bluez-utils dkms 2>/dev/null || true
    say ""

    say "--- Módulos ---"
    lsmod | grep -Ei 'xpadneo|xpad|uhid|hid_nintendo' || true
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
        while IFS='|' read -r mac name connected bonded trusted modalias; do
            say "${mac} | ${name} | Connected=${connected} Bonded=${bonded} Trusted=${trusted}"
            say "  ${modalias}"
        done <<<"$rows"
    else
        say "nenhum"
    fi
    say ""

    say "--- Dispositivos de entrada relacionados ---"
    grep -A 12 -B 2 -Ei 'Xbox Wireless Controller|gamepad|controller' /proc/bus/input/devices 2>/dev/null || true
    say ""

    say "--- Logs recentes xpadneo ---"
    dmesg 2>/dev/null | grep -E 'xpadneo|quirks added|controller quirks' | tail -n 40 || \
        warn "Leia o dmesg com sudo se o kernel bloquear acesso para usuário comum."
}

main_menu() {
    while true; do
        header
        say "1) Instalar/verificar suporte Xbox Bluetooth (xpadneo + Steam)"
        say "2) Configurar layout Nintendo (+32) em um controle Xbox Bluetooth"
        say "3) Remover layout Nintendo de um controle"
        say "4) Diagnóstico"
        say "0) Sair"
        say ""
        read -r -p "Opção: " opt
        case "$opt" in
            1) install_support; pause ;;
            2) add_nintendo_mapping; pause ;;
            3) remove_nintendo_mapping; pause ;;
            4) diagnostics; pause ;;
            0) exit 0 ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

need_cmd bluetoothctl
main_menu
