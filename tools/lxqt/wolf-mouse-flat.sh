#!/usr/bin/env bash
# Wolf LXQt X11: mouses sem aceleração (libinput flat), nunca touchpads.
set -u
[[ "${XDG_SESSION_TYPE:-x11}" == x11 && -n "${DISPLAY:-}" ]] || exit 0
command -v xinput >/dev/null 2>&1 || exit 0
# Não mascarar falha de permissão do X11; apenas omitir dispositivos sem suporte.
while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    props="$(xinput list-props "$id" 2>/dev/null || true)"
    [[ -n "$props" ]] || continue
    # Não modificar touchpad (tem regras próprias).
    grep -q 'libinput Tapping Enabled' <<< "$props" && continue
    if grep -q 'libinput Accel Profile Enabled (' <<< "$props"; then
        line="$(grep -m1 'libinput Accel Profile Enabled (' <<< "$props")"
        values="$(tr -d '[:space:]' <<< "${line##*:}")"
        case "$values" in
            *,*,*) xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 0 >/dev/null 2>&1 || true ;;
            *,*) xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 >/dev/null 2>&1 || true ;;
        esac
    fi
    if grep -q 'libinput Accel Speed (' <<< "$props"; then
        xinput set-prop "$id" 'libinput Accel Speed' 0 >/dev/null 2>&1 || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
