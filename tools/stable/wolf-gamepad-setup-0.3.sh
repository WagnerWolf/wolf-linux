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
