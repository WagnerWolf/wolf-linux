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

    [[ -f "$PROJECT/iso-profile/syslinux/archiso_head.cfg" ]] \
        && grep -Fxq 'MENU TITLE Wolf Linux' \
            "$PROJECT/iso-profile/syslinux/archiso_head.cfg" \
        && grep -Fxq 'MENU BACKGROUND boot/syslinux/splash.png' \
            "$PROJECT/iso-profile/syslinux/archiso_head.cfg" \
        && [[ -f "$PROJECT/iso-profile/syslinux/splash.png" ]] \
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

# Regressões que já apareceram durante a estabilização do Cinnamon.
# Estes checks falham cedo antes de gerar uma ISO se algum dos fixes
# consolidados desaparecer do instalador ou do manifesto de pacotes.
INSTALLER="$PROJECT/install/wolf-install.sh"
PACKAGES="$PROJECT/package-profiles/packages.conf"

if [[ -f "$INSTALLER" && -f "$PACKAGES" ]]; then
    echo
    echo ">> Validando perfil Cinnamon consolidado..."
    CINNAMON_FAIL=0

    CINNAMON_BLOCK="$(
        sed -n '/^CINNAMON_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true
    )"

    for pkg in cinnamon xarchiver flameshot gnome-keyring libsecret seahorse; do
        grep -Eq "^[[:space:]]*${pkg}([[:space:]]|$)" <<<"$CINNAMON_BLOCK" \
            || CINNAMON_FAIL=1
    done

    grep -Fq 'wolf-disable-cinnamon-wayland' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq 'wolf-cinnamon-x11-only.hook' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq '/usr/share/wayland-sessions/cinnamon*.desktop' "$INSTALLER" \
        || CINNAMON_FAIL=1

    grep -Fq 'pam_gnome_keyring.so' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq '"password-store": "gnome-libsecret"' "$INSTALLER" \
        || CINNAMON_FAIL=1

    grep -Fq 'parser.optionxform = str' "$INSTALLER" \
        || CINNAMON_FAIL=1
    for key in \
        contrastopacity \
        autocloseidledaemon \
        disabledtrayicon \
        showstartuplaunchmessage
    do
        grep -Fq "\"$key\"" "$INSTALLER" || CINNAMON_FAIL=1
    done

    if (( CINNAMON_FAIL == 0 )); then
        echo "[OK] Cinnamon X11-only + Flameshot + Keyring/Seahorse + VS Code"
    else
        echo "[ERRO] perfil Cinnamon perdeu um ou mais fixes consolidados."
        FAIL=1
    fi
fi

# Player de vídeo e associação de diretórios devem permanecer protegidos.
if [[ -f "$INSTALLER" && -f "$PACKAGES" ]]; then
    echo
    echo ">> Validando MPC-QT e proteção do gerenciador de arquivos..."
    MIME_FAIL=0

    MULTIMEDIA_BLOCK="$(
        sed -n '/^MULTIMEDIA_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true
    )"

    grep -Eq '^[[:space:]]*mpc-qt([[:space:]]|$)' <<<"$MULTIMEDIA_BLOCK" \
        || MIME_FAIL=1

    if grep -Eq '^[[:space:]]*vlc(-plugins-all)?([[:space:]]|$)' <<<"$MULTIMEDIA_BLOCK"; then
        echo "[ERRO] VLC voltou ao perfil multimídia; o padrão validado é MPC-QT."
        MIME_FAIL=1
    fi

    grep -Fq 'io.github.mpc_qt.mpc-qt.desktop' "$INSTALLER" \
        || MIME_FAIL=1
    grep -Fq 'wolf-protect-directory-handler' "$INSTALLER" \
        || MIME_FAIL=1
    grep -Fq 'inode/directory' "$INSTALLER" \
        || MIME_FAIL=1
    for desktop in nemo.desktop caja.desktop org.kde.dolphin.desktop; do
        grep -Fq "$desktop" "$INSTALLER" || MIME_FAIL=1
    done

    if (( MIME_FAIL == 0 )); then
        echo "[OK] MPC-QT + inode/directory protegido em Cinnamon/MATE/KDE"
    else
        echo "[ERRO] player padrão ou proteção de diretórios perdeu configuração."
        FAIL=1
    fi
fi

# Toolchain Flutter/Android/Web deve ser igual nos três desktops.
if [[ -f "$INSTALLER" && -f "$PACKAGES" ]]; then
    echo
    echo ">> Validando Flutter / Android / Chrome..."
    DEV_FAIL=0

    DEV_THIRD_BLOCK="$(
        sed -n '/^DEV_THIRD_PARTY_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true
    )"

    for pkg in \
        android-sdk \
        android-sdk-build-tools \
        android-sdk-platform-tools \
        android-platform; do
        grep -Eq "^[[:space:]]*${pkg}([[:space:]]|$)" <<<"$DEV_THIRD_BLOCK" \
            || DEV_FAIL=1
    done

    DEV_BLOCK="$(
        sed -n '/^DEV_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true
    )"
    grep -Eq '^[[:space:]]*acl([[:space:]]|$)' <<<"$DEV_BLOCK" \
        || DEV_FAIL=1

    # Um único adb: o fornecido pelo Android SDK em /opt/android-sdk/platform-tools.
    if grep -Eq '^[[:space:]]*android-tools[[:space:]]*$' "$PACKAGES"; then
        echo "[ERRO] android-tools voltou ao manifesto e duplicará /usr/bin/adb."
        DEV_FAIL=1
    fi

    # Flutter 3.47 ainda não entende o fluxo de licenças do cmdline-tools 23+.
    if grep -Eq '^[[:space:]]*android-sdk-cmdline-tools-latest[[:space:]]*$' "$PACKAGES"; then
        echo "[ERRO] cmdline-tools-latest voltou ao manifesto; Flutter 3.47 perde a checagem de licenças com 23+."
        DEV_FAIL=1
    fi
    grep -Fq 'commandlinetools-linux-15859902_latest.zip' "$INSTALLER" || DEV_FAIL=1
    grep -Fq '4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583' "$INSTALLER" || DEV_FAIL=1
    grep -Fq 'Pkg.Revision' "$INSTALLER" || DEV_FAIL=1

    grep -Fq 'google-chrome-stable /mnt/usr/local/bin/google-chrome' "$INSTALLER" \
        || grep -Fq 'ln -sfn /usr/bin/google-chrome-stable /mnt/usr/local/bin/google-chrome' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'CHROME_EXECUTABLE=/usr/bin/google-chrome-stable' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'wolf-android-licenses' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'groupadd -f android-sdk' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'usermod -aG android-sdk' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'wolf-fix-android-sdk-permissions' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'setfacl -R -m' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq "d:g:\${SDK_GROUP}:rwx" "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'wolf-android-sdk-permissions.hook' "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq 'flutter doctor --android-licenses' "$INSTALLER" \
        || DEV_FAIL=1
    if grep -Fq "exec sudo \"\$SDKMANAGER\"" "$INSTALLER"; then
        echo "[ERRO] helper de licenças voltou a depender de sudo."
        DEV_FAIL=1
    fi
    grep -Fq "chown -R \"\$USERNAME_VALUE:\$USERNAME_VALUE\" \"\$target_flutter\"" "$INSTALLER" \
        || DEV_FAIL=1
    grep -Fq "platforms/android-*" "$INSTALLER" \
        || DEV_FAIL=1

    if (( DEV_FAIL == 0 )); then
        echo "[OK] Android SDK + ACL/grupo + ADB único + cmdline-tools 22.0 + Chrome Web + licenças"
    else
        echo "[ERRO] toolchain Flutter/Android/Web perdeu um ou mais fixes."
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
