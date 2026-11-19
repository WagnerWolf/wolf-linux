#!/usr/bin/env bash
# Wolf Linux - Picom VM guard v1
# Escolhe o compositor apenas quando a sessão LXQt realmente inicia.
# VM: desativado por padrão. XRender opt-in: WOLF_PICOM_VM_MODE=xrender.
set -uo pipefail

session="${XDG_SESSION_TYPE:-x11}"
if [[ "$session" != "x11" ]]; then
    if [[ "${1:-}" == "--status" ]]; then
        printf 'Wolf Picom: sessão %s, não iniciar compositor X11\n' "$session"
    fi
    exit 0
fi

is_vm=0
vm_type="nenhuma"
if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --vm --quiet; then
    is_vm=1
    vm_type="$(systemd-detect-virt --vm 2>/dev/null || printf 'desconhecida')"
fi

mode="${WOLF_PICOM_VM_MODE:-off}"
if (( is_vm )); then
    case "$mode" in
        off)      chosen="desativado" ;;
        xrender)  chosen="xrender" ;;
        glx)      chosen="glx (forçado pelo usuário)" ;;
        *)        printf '[ERRO] WOLF_PICOM_VM_MODE deve ser off, xrender ou glx\n' >&2; exit 2 ;;
    esac
else
    chosen="glx (hardware físico)"
fi

if [[ "${1:-}" == "--status" ]]; then
    printf 'Wolf Picom: sessão=%s; VM=%s; compositor=%s\n' "$session" "$vm_type" "$chosen"
    exit 0
fi

if (( is_vm )) && [[ "$mode" == off ]]; then
    exit 0
fi

if ! command -v picom >/dev/null 2>&1; then
    printf '[AVISO] Picom não instalado.\n' >&2
    exit 0
fi

if (( is_vm )) && [[ "$mode" == xrender ]]; then
    # Ignora o picom.conf GLX. /dev/null evita herdar GLX/VSync do perfil físico.
    exec picom --config /dev/null --backend xrender
fi

exec picom --config "$HOME/.config/picom/picom.conf"
