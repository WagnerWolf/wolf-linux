#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
FAIL=0

echo "======================================================"
echo "          WOLF LINUX - TESTES RÁPIDOS"
echo "======================================================"

check_shell() {
    local f="$1"

    echo
    echo ">> $f"

    if bash -n "$f"; then
        echo "[OK] bash -n"
    else
        echo "[ERRO] bash -n"
        FAIL=1
        return
    fi

    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck -x -s bash "$f"; then
            echo "[OK] shellcheck"
        else
            echo "[AVISO] shellcheck encontrou pontos a revisar."
            FAIL=1
        fi
    fi
}

while IFS= read -r -d '' f; do
    check_shell "$f"
done < <(
    find "$PROJECT/install" "$PROJECT/tests" \
        -type f -name '*.sh' -print0 2>/dev/null
)

if [[ -d "$PROJECT/iso-profile" ]]; then
    echo
    echo ">> Validando perfil da ISO Wolf Linux..."

    ISO_FAIL=0

    [[ -f "$PROJECT/iso-profile/airootfs/etc/vconsole.conf" ]] \
        && grep -Fxq 'KEYMAP=br-abnt2' \
            "$PROJECT/iso-profile/airootfs/etc/vconsole.conf" \
        && grep -Fxq 'FONT=ter-v16n' \
            "$PROJECT/iso-profile/airootfs/etc/vconsole.conf" \
        || ISO_FAIL=1

    [[ -x "$PROJECT/iso-profile/airootfs/usr/local/bin/wolf-install" ]] \
        || ISO_FAIL=1

    [[ -f "$PROJECT/iso-profile/airootfs/etc/os-release" ]] \
        && grep -Fxq 'PRETTY_NAME="Wolf Linux Live"' \
            "$PROJECT/iso-profile/airootfs/etc/os-release" \
        || ISO_FAIL=1

    [[ -L "$PROJECT/iso-profile/airootfs/etc/systemd/system/multi-user.target.wants/wolf-loadkeys.service" ]] \
        || ISO_FAIL=1

    [[ -f "$PROJECT/iso-profile/profiledef.sh" ]] \
        && grep -Fq '["/usr/local/bin/wolf-install"]="0:0:755"' \
            "$PROJECT/iso-profile/profiledef.sh" \
        || ISO_FAIL=1

    [[ -f "$PROJECT/iso-profile/profiledef.sh" ]] \
        && grep -Fq '["/root/wolf-linux/install/wolf-install.sh"]="0:0:755"' \
            "$PROJECT/iso-profile/profiledef.sh" \
        || ISO_FAIL=1

    # Fundo Wolf Linux no GRUB da mídia live (usado no boot BIOS).
    [[ -f "$PROJECT/iso-profile/grub/wolf-linux-background.png" ]] \
        || ISO_FAIL=1

    [[ -f "$PROJECT/iso-profile/grub/grub.cfg" ]] \
        && grep -Fq 'background_image /grub/wolf-linux-background.png' \
            "$PROJECT/iso-profile/grub/grub.cfg" \
        || ISO_FAIL=1

    if (( ISO_FAIL == 0 )); then
        echo "[OK] perfil ISO"
    else
        echo "[ERRO] perfil ISO incompleto. Rode:"
        echo "  $PROJECT/tests/wolf-customize-iso-profile.sh"
        FAIL=1
    fi
fi

if [[ -f "$PROJECT/package-profiles/packages.conf" ]]; then
    echo
    echo ">> Validando manifesto..."
    if bash -n "$PROJECT/package-profiles/packages.conf"; then
        echo "[OK] manifesto"
    else
        echo "[ERRO] manifesto"
        FAIL=1
    fi
fi

echo
if (( FAIL == 0 )); then
    echo "[OK] Testes rápidos concluídos."
else
    echo "[ERRO] Há itens a corrigir antes do teste em VM."
    exit 1
fi
