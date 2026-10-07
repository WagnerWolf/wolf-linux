#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
FAIL=0

fail() {
    echo "[ERRO] $*" >&2
    FAIL=1
}

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

MULTIMONITOR_HELPER="$PROJECT/tools/wolf-multimonitor-setup-0.5.sh"
if [[ -f "$MULTIMONITOR_HELPER" ]]; then
    check_shell "$MULTIMONITOR_HELPER"
fi

MULTIMONITOR_INSTALLER="$PROJECT/tools/wolf-install-multimonitor-auto-0.5.sh"
if [[ -f "$MULTIMONITOR_INSTALLER" ]]; then
    check_shell "$MULTIMONITOR_INSTALLER"
fi

CINNVII_HOTKEY_HELPER="$PROJECT/tools/wolf-fix-cinnvii-super-monitor-0.2.sh"
if [[ -f "$CINNVII_HOTKEY_HELPER" ]]; then
    check_shell "$CINNVII_HOTKEY_HELPER"

    echo
    echo ">> Validando patch CinnVII multiversão (3.2/4.2)..."
    CINNVII_FIXTURE="$(mktemp -d)"
    mkdir -p "$CINNVII_FIXTURE/3.2" "$CINNVII_FIXTURE/4.2"
    cat > "$CINNVII_FIXTURE/3.2/applet.js" <<'EOF_CINNVII_32'
_updateKeybinding: function() {
    Main.keybindingManager.addHotKey("overlay-key-" + this.instance_id, this.overlayKey, Lang.bind(this, function() {
        this.menu.toggle();
    }));
},
on_applet_removed_from_panel: function () {
    Main.keybindingManager.removeHotKey("overlay-key-" + this.instance_id)
},
EOF_CINNVII_32
    cat > "$CINNVII_FIXTURE/4.2/applet.js" <<'EOF_CINNVII_42'
_updateKeybinding() {
    Main.keybindingManager.addHotKey("overlay-key-" + this.instance_id, this.overlayKey, Lang.bind(this, function() {
        this.menu.toggle();
    }));
}
on_applet_removed_from_panel () {
    Main.keybindingManager.removeHotKey("overlay-key-" + this.instance_id);
}
EOF_CINNVII_42

    if "$CINNVII_HOTKEY_HELPER" "$CINNVII_FIXTURE" >/dev/null 2>&1        && grep -Fq 'addXletHotKey(this, "overlay-key"' "$CINNVII_FIXTURE/3.2/applet.js"        && grep -Fq 'removeXletHotKey(this, "overlay-key")' "$CINNVII_FIXTURE/3.2/applet.js"        && grep -Fq 'addXletHotKey(this, "overlay-key"' "$CINNVII_FIXTURE/4.2/applet.js"        && grep -Fq 'removeXletHotKey(this, "overlay-key")' "$CINNVII_FIXTURE/4.2/applet.js"; then
        echo "[OK] patch CinnVII multiversão"
    else
        echo "[ERRO] patch CinnVII falhou em fixture 3.2/4.2"
        FAIL=1
    fi
    rm -rf "$CINNVII_FIXTURE"
fi

XFCE_DESKTOP_SETUP="$PROJECT/tools/wolf-xfce-desktop-setup-0.7.sh"
XFCE_MULTIMONITOR_HELPER="$PROJECT/tools/wolf-xfce-multimonitor-0.5.sh"
[[ -f "$XFCE_DESKTOP_SETUP" ]] && check_shell "$XFCE_DESKTOP_SETUP"
[[ -f "$XFCE_MULTIMONITOR_HELPER" ]] && check_shell "$XFCE_MULTIMONITOR_HELPER"
XFCE_WHISKER_HELPER="$PROJECT/tools/wolf-xfce-whisker-current-0.3.sh"
XFCE_DEFAULTS_HELPER="$PROJECT/tools/wolf-xfce-default-apps-0.3.sh"
XFCE_POLISH_FIX="$PROJECT/tools/wolf-fix-xfce-polish-1.0.51.sh"
XFCE_PLACEMENT_HELPER="$PROJECT/tools/wolf-xfce-whisker-placement-0.2.sh"
XFCE_ALTTAB_HELPER="$PROJECT/tools/wolf-xfce-alttab-0.1.sh"
XFCE_LAUNCH_HELPER="$PROJECT/tools/wolf-xfce-launch-here-0.1.sh"
XFCE_SUPER_HELPER="$PROJECT/tools/wolf-xfce-super-setup-0.2.sh"
GAMEPAD_HELPER="$PROJECT/tools/wolf-gamepad-setup-0.3.sh"
GRUB_MANAGER_HELPER="$PROJECT/tools/wolf-grub-manager-0.3.sh"
DESKTOP_BRANDING_HELPER="$PROJECT/tools/wolf-desktop-branding-0.1.sh"
XFCE_COMPOSITOR_HELPER="$PROJECT/tools/wolf-xfce-compositor-0.1.sh"
DESKTOP_BRANDING_FIX="$PROJECT/tools/wolf-fix-desktop-branding-1.0.50.sh"
require_shell() {
    local f="$1" label="$2"
    if [[ ! -f "$f" ]]; then
        fail "$label ausente: $f"
        return 0
    fi
    check_shell "$f"
}

require_shell "$XFCE_WHISKER_HELPER" "helper Whisker XFCE"
require_shell "$XFCE_DEFAULTS_HELPER" "helper aplicativos padrão XFCE"
require_shell "$XFCE_PLACEMENT_HELPER" "helper placement XFCE"
require_shell "$XFCE_ALTTAB_HELPER" "helper Alt+Tab XFCE"
require_shell "$XFCE_LAUNCH_HELPER" "helper launcher contextual XFCE"
require_shell "$XFCE_SUPER_HELPER" "helper Super XFCE"
require_shell "$XFCE_POLISH_FIX" "fixer XFCE 1.0.51"
if grep -Fq "\$SELF_DIR/" "$XFCE_POLISH_FIX"; then
    grep -Fq "SELF_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\"" "$XFCE_POLISH_FIX" \
        || fail "fixer XFCE usa SELF_DIR sem inicializá-lo"
fi
require_shell "$GAMEPAD_HELPER" "helper gamepad"
require_shell "$GRUB_MANAGER_HELPER" "Wolf GRUB Manager"
require_shell "$DESKTOP_BRANDING_HELPER" "helper branding Cinnamon/KDE"
require_shell "$XFCE_COMPOSITOR_HELPER" "helper compositor XFCE"
require_shell "$DESKTOP_BRANDING_FIX" "fixer branding 1.0.50"

PLASMA_MULTIMONITOR_HELPER="$PROJECT/tools/wolf-plasma-multimonitor-0.2.sh"
if [[ -f "$PLASMA_MULTIMONITOR_HELPER" ]]; then
    check_shell "$PLASMA_MULTIMONITOR_HELPER"
fi

check_python() {
    local f="$1"
    echo
    echo ">> $f"
    if python3 -m py_compile "$f"; then
        echo "[OK] python3 -m py_compile"
    else
        echo "[ERRO] sintaxe Python"
        FAIL=1
    fi
}

MATE_MULTIMONITOR_HELPER="$PROJECT/tools/wolf-mate-multimonitor-0.3.py"
MATE_MONITOR_TASKS="$PROJECT/tools/wolf-monitor-tasks.py"
[[ -f "$MATE_MULTIMONITOR_HELPER" ]] && check_python "$MATE_MULTIMONITOR_HELPER"
[[ -f "$MATE_MONITOR_TASKS" ]] && check_python "$MATE_MONITOR_TASKS"

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

    [[ -x "$PROJECT/iso-profile/airootfs/root/wolf-linux/tools/wolf-grub-manager-0.3.sh" ]] \
        || ISO_FAIL=1

    [[ -f "$PROJECT/iso-profile/profiledef.sh" ]] \
        && grep -Fq '["/root/wolf-linux/tools/wolf-grub-manager-0.3.sh"]="0:0:755"' \
            "$PROJECT/iso-profile/profiledef.sh" \
        || ISO_FAIL=1

    for tool in wolf-desktop-branding-0.1.sh wolf-xfce-compositor-0.1.sh; do
        [[ -x "$PROJECT/iso-profile/airootfs/root/wolf-linux/tools/$tool" ]] \
            || ISO_FAIL=1
        [[ -f "$PROJECT/iso-profile/profiledef.sh" ]] \
            && grep -Fq "[\"/root/wolf-linux/tools/$tool\"]=\"0:0:755\"" \
                "$PROJECT/iso-profile/profiledef.sh" \
            || ISO_FAIL=1
    done

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

    grep -Fq 'CinnVIIStarkMenu@NikoKrause' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq 'cinnamon-spices.linuxmint.com/files/applets/CinnVIIStarkMenu%40NikoKrause.zip' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq 'cinnvii-default-v1.done' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq 'wolf-cinnvii-hotkey-fix' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq 'addXletHotKey(this, "overlay-key"' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq 'removeXletHotKey(this, "overlay-key")' "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq "CinnVII é multiversão" "$INSTALLER" \
        || CINNAMON_FAIL=1
    grep -Fq "old_remove_re = re.compile" "$INSTALLER" \
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
        echo "[OK] Cinnamon X11-only + CinnVII/Super por monitor + Flameshot + Keyring/Seahorse + VS Code"
    else
        echo "[ERRO] perfil Cinnamon perdeu um ou mais fixes consolidados."
        FAIL=1
    fi
fi

# Wolf MultiMonitor: Cinnamon foi validado em hardware; Plasma usa recursos
# nativos e é automático; MATE inclui o Wolf Monitor Tasks, mas permanece
# experimental até validação em hardware real.
if [[ -f "$MULTIMONITOR_HELPER" && -f "$INSTALLER" && -f "$PACKAGES" ]]; then
    echo
    echo ">> Validando Wolf MultiMonitor multi-desktop..."
    MULTI_FAIL=0

    # Cinnamon: baseline já validada em hardware real.
    grep -Fq 'CinnVIIStarkMenu@NikoKrause' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'grouped-window-list@cinnamon.org' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'window-display-settings' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'alttab-switcher-show-current-monitor' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'topology_signature' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'watch_loop' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'restore_latest' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'wolf-cinnamon-multimonitor.desktop' "$INSTALLER" || MULTI_FAIL=1
    grep -Fq 'ensure_cinnvii_hotkey_fix' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'apply_wolf_menu_branding' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    grep -Fq 'menu-icon' "$MULTIMONITOR_HELPER" || MULTI_FAIL=1
    [[ -f "$CINNVII_HOTKEY_HELPER" ]] || MULTI_FAIL=1
    if [[ -f "$CINNVII_HOTKEY_HELPER" ]]; then
        grep -Fq 'addXletHotKey(this, "overlay-key"' "$CINNVII_HOTKEY_HELPER" || MULTI_FAIL=1
        grep -Fq 'removeXletHotKey(this, "overlay-key")' "$CINNVII_HOTKEY_HELPER" || MULTI_FAIL=1
    fi

    # Plasma: painel por tela usando scripting oficial e Task Manager local.
    [[ -f "$PLASMA_MULTIMONITOR_HELPER" ]] || MULTI_FAIL=1
    if [[ -f "$PLASMA_MULTIMONITOR_HELPER" ]]; then
        grep -Fq 'showOnlyCurrentScreen' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'panel.screen = screen' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'org.kde.plasma.kickoff' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'org.kde.plasma.icontasks' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'kscreen-doctor' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'watch_loop' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'restore_latest' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'writeConfig("icon", "wolf-linux")' "$PLASMA_MULTIMONITOR_HELPER" || MULTI_FAIL=1
    fi
    grep -Fq 'wolf-plasma-multimonitor.desktop' "$INSTALLER" || MULTI_FAIL=1
    grep -Fq 'Exec=/usr/local/bin/wolf-plasma-multimonitor watch' "$INSTALLER" || MULTI_FAIL=1

    PLASMA_BLOCK="$(sed -n '/^PLASMA_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"
    for pkg in qt6-tools kscreen; do
        grep -Eq "^[[:space:]]*${pkg}([[:space:]]|$)" <<<"$PLASMA_BLOCK" || MULTI_FAIL=1
    done

    # MATE: applet próprio por monitor; instalação existe mas ativação automática
    # continua guardada por marcador até o teste em hardware.
    [[ -f "$MATE_MULTIMONITOR_HELPER" ]] || MULTI_FAIL=1
    [[ -f "$MATE_MONITOR_TASKS" ]] || MULTI_FAIL=1
    if [[ -f "$MATE_MULTIMONITOR_HELPER" ]]; then
        grep -Fq 'WolfMonitorTasksFactory::WolfMonitorTasksApplet' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'WnckletFactory::WindowListApplet' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'mate-multimonitor.enabled' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'if "pack-type" in keys:' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'if "panel-right-stick" in keys:' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'gi.require_version("Gdk", "3.0")' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'def gdk_monitor_records()' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        grep -Fq 'display.get_n_monitors()' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
        if grep -Fq '["xrandr", "--listmonitors"]' "$MATE_MULTIMONITOR_HELPER"; then
            MULTI_FAIL=1
        fi
        grep -Fq 'def restore' "$MATE_MULTIMONITOR_HELPER" || MULTI_FAIL=1
    fi
    if [[ -f "$MATE_MONITOR_TASKS" ]]; then
        grep -Fq 'Wnck.Screen' "$MATE_MONITOR_TASKS" || MULTI_FAIL=1
        grep -Fq '_is_on_this_monitor' "$MATE_MONITOR_TASKS" || MULTI_FAIL=1
        grep -Fq 'WolfMonitorTasksFactory' "$MATE_MONITOR_TASKS" || MULTI_FAIL=1
    fi
    grep -Fq 'wolf-mate-multimonitor.desktop' "$INSTALLER" || MULTI_FAIL=1
    grep -Fq 'WolfMonitorTasksFactory' "$INSTALLER" || MULTI_FAIL=1
    # Antes da validação em hardware, o instalador deve deixar explícito que
    # o MATE foi instalado mas não habilitado automaticamente.
    grep -Fq 'não habilitado automaticamente' "$INSTALLER" || MULTI_FAIL=1

    MATE_BLOCK="$(sed -n '/^MATE_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"
    grep -Eq '^[[:space:]]*python-gobject([[:space:]]|$)' <<<"$MATE_BLOCK" || MULTI_FAIL=1

    grep -Fq '/usr/local/bin/wolf-multimonitor' "$INSTALLER" || MULTI_FAIL=1

    if (( MULTI_FAIL == 0 )); then
        echo "[OK] MultiMonitor: Cinnamon validado + Plasma nativo automático + MATE experimental preparado"
    else
        echo "[ERRO] Wolf MultiMonitor perdeu uma ou mais garantias multi-desktop."
        FAIL=1
    fi
fi

# VirtualBox: a ISO deve aceitar --vm-install, instalar Guest Additions
# oficiais e habilitar vboxservice para que múltiplas telas funcionem no guest.
if [[ -f "$INSTALLER" && -f "$PACKAGES" ]]; then
    echo
    echo ">> Validando suporte de teste no VirtualBox..."
    VBOX_FAIL=0

    VBOX_BLOCK="$(sed -n '/^VIRTUALBOX_GUEST_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"
    grep -Eq '^[[:space:]]*virtualbox-guest-utils([[:space:]]|$)' <<<"$VBOX_BLOCK" || VBOX_FAIL=1
    grep -Fq 'oracle|virtualbox|vbox' "$INSTALLER" || VBOX_FAIL=1
    grep -Fq 'vboxservice.service' "$INSTALLER" || VBOX_FAIL=1
    grep -Fq 'GPU_PROFILE="virtualbox"' "$INSTALLER" || VBOX_FAIL=1
    grep -Fq 'VIRTUALBOX_GPU_PACKAGES' "$INSTALLER" || VBOX_FAIL=1
    grep -Fq 'qemu|kvm|oracle|virtualbox|vbox)' "$PROJECT/tests/wolf-customize-iso-profile.sh" || VBOX_FAIL=1

    if (( VBOX_FAIL == 0 )); then
        echo "[OK] VirtualBox: --vm-install + Guest Additions + vboxservice + perfil gráfico"
    else
        echo "[ERRO] suporte de teste no VirtualBox incompleto."
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

    MULTIMEDIA_THIRD_BLOCK="$(
        sed -n '/^MULTIMEDIA_THIRD_PARTY_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true
    )"

    # mpc-qt depende do Chaotic-AUR/AUR. Não pode voltar ao bloco base,
    # pois a validação/pacstrap acontece antes de habilitarmos o Chaotic.
    if grep -Eq '^[[:space:]]*mpc-qt([[:space:]]|$)' <<<"$MULTIMEDIA_BLOCK"; then
        echo "[ERRO] mpc-qt voltou ao MULTIMEDIA_PACKAGES e quebrará a validação antes do pacstrap."
        MIME_FAIL=1
    fi
    grep -Eq '^[[:space:]]*mpc-qt([[:space:]]|$)' <<<"$MULTIMEDIA_THIRD_BLOCK" \
        || MIME_FAIL=1
    grep -Fq "\${MULTIMEDIA_THIRD_PARTY_PACKAGES[@]}" "$INSTALLER" \
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
    for desktop in nemo.desktop caja.desktop org.kde.dolphin.desktop thunar.desktop; do
        grep -Fq "$desktop" "$INSTALLER" || MIME_FAIL=1
    done

    if (( MIME_FAIL == 0 )); then
        echo "[OK] MPC-QT + inode/directory protegido em Cinnamon/MATE/KDE/XFCE"
    else
        echo "[ERRO] player padrão ou proteção de diretórios perdeu configuração."
        FAIL=1
    fi
fi

# Identidade de menu Cinnamon/KDE e helper opcional de compositor XFCE.
if [[ -f "$INSTALLER" ]]; then
    echo
    echo ">> Validando branding Cinnamon/KDE e Picom/XRender padrão no XFCE..."
    BRAND_FAIL=0

    grep -Fq 'install_wolf_desktop_branding' "$INSTALLER" || BRAND_FAIL=1
    grep -Fq 'wolf-desktop-branding.desktop' "$INSTALLER" || BRAND_FAIL=1
    grep -Fq 'wolf-xfce-compositor-0.1.sh' "$INSTALLER" || BRAND_FAIL=1
    grep -Fq 'menu-custom' "$DESKTOP_BRANDING_HELPER" || BRAND_FAIL=1
    grep -Fq 'menu-icon' "$DESKTOP_BRANDING_HELPER" || BRAND_FAIL=1
    grep -Fq 'writeConfig("icon","wolf-linux")' "$DESKTOP_BRANDING_HELPER" || BRAND_FAIL=1
    grep -Fq 'backend = "xrender";' "$XFCE_COMPOSITOR_HELPER" || BRAND_FAIL=1
    grep -Fq 'backend = "glx";' "$XFCE_COMPOSITOR_HELPER" || BRAND_FAIL=1
    grep -Fq 'xrender-sync-fence = true;' "$XFCE_COMPOSITOR_HELPER" || BRAND_FAIL=1
    grep -Fq 'ensure-default' "$XFCE_COMPOSITOR_HELPER" || BRAND_FAIL=1
    grep -Fq 'wolf-xfce-compositor-default.desktop' "$INSTALLER" || BRAND_FAIL=1

    if (( BRAND_FAIL == 0 )); then
        echo "[OK] Cinnamon/KDE com símbolo Wolf + Picom/XRender padrão reversível no XFCE"
    else
        echo "[ERRO] branding Cinnamon/KDE ou helper Picom incompleto."
        FAIL=1
    fi
fi

# Toolchain Flutter/Android/Web deve ser igual nos três desktops.
if [[ -f "$INSTALLER" && -f "$PACKAGES" ]]; then
    echo
    echo ">> Validando kernel de recuperação, identidade e XFCE..."

grep -Fq 'linux-lts' "$PACKAGES" || fail "linux-lts ausente do manifesto"
grep -Fq 'linux-lts-headers' "$PACKAGES" || fail "linux-lts-headers ausente do manifesto"
grep -Fq 'XFCE_PACKAGES=(' "$PACKAGES" || fail "perfil XFCE ausente"
XFCE_BLOCK="$(sed -n '/^XFCE_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"
for pkg in xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin picom xcape xdotool wmctrl xorg-xprop xorg-xev xdg-user-dirs-gtk gvfs materia-gtk-theme ristretto xreader xarchiver; do
    grep -Eq "^[[:space:]]*${pkg}([[:space:]]|$)" <<<"$XFCE_BLOCK" || fail "pacote XFCE ausente: $pkg"
done
grep -Fq 'LOGO="wolf-linux"' "$INSTALLER" || fail "LOGO Wolf ausente do os-release"
grep -Fq 'GRUB_TIMEOUT_STYLE=menu' "$INSTALLER" || fail "menu GRUB de recuperação não protegido"
grep -Fq 'GRUB_DISABLE_BOOTNEXT=true' "$INSTALLER" || fail "GRUB 2.16 BootNext não está desabilitado por padrão"
grep -Fq 'cat > /mnt/usr/local/bin/wolf-grub-manager' "$INSTALLER" || fail "Wolf GRUB Manager não é instalado no sistema alvo"
grep -Fq 'wolf-xfce-multimonitor' "$INSTALLER" || fail "Wolf MultiMonitor XFCE ausente"
grep -Fq 'wolf-xfce-desktop-setup' "$INSTALLER" || fail "setup determinístico do XFCE ausente"
grep -Fq 'wolf-disable-xfce-wayland' "$INSTALLER" || fail "política XFCE X11-only ausente"
grep -Fq 'Target = xfce4-session' "$INSTALLER" || fail "hook de persistência X11 do XFCE ausente"
grep -Fq 'Session=xfce.desktop' "$INSTALLER" || fail "SDDM não está fixando XFCE X11"
grep -Fq 'wolf-xfce-browser.desktop' "$INSTALLER" || fail "launcher Chrome do XFCE ausente"
grep -Fq 'wolf-xfce-home.desktop' "$INSTALLER" || fail "launcher Pasta pessoal do XFCE ausente"
grep -Fq 'wolf-xfce-terminal.desktop' "$INSTALLER" || fail "launcher Terminal do XFCE ausente"
grep -Fq "launcher-\$id" "$INSTALLER" || fail "launchers XFCE não são materializados no perfil do usuário"
grep -Fq 'MesloLGS Nerd Font 11' "$INSTALLER" || fail "fonte correta do terminal XFCE ausente"
FONT_BLOCK="$(sed -n '/^FONT_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"
for pkg in noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-meslo-nerd ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono; do
    grep -Eq "^[[:space:]]*${pkg}([[:space:]]|$)" <<<"$FONT_BLOCK" || fail "fonte/fallback ausente: $pkg"
done
grep -Fq "base=\"/backdrop/screen0/monitor\${out}/workspace0\"" "$INSTALLER" || fail "wallpaper XFCE não cobre outputs dinamicamente"
grep -Fq '/general/workspace_count' "$INSTALLER" || fail "XFCE não está reduzindo workspaces para 1"
grep -Fq 'Materia-dark' "$INSTALLER" || fail "tema escuro XFCE ausente"
grep -Fq 'breeze_cursors' "$INSTALLER" || fail "cursor XFCE não usa nome real Breeze"
grep -Fq 'wolf-managed' "$INSTALLER" || fail "painéis secundários XFCE não estão marcados"
grep -Fq 'wolf-layout-version' "$INSTALLER" || fail "versão de layout secundário XFCE ausente"
grep -Fq '/usr/local/bin/wolf-xfce-whisker-current' "$INSTALLER" || fail "roteamento Whisker por monitor ausente"
grep -Fq 'xfce4-popup-whiskermenu --instance=' "$INSTALLER" || fail "Whisker não seleciona instância do painel"
grep -Fq 'popup:bool:false' "$INSTALLER" || fail "Whisker não força popup ancorado com bool:false"
grep -Fq 'xfce-appearance-v1.done' "$INSTALLER" || fail "marcador de aparência inicial do XFCE ausente"
grep -Fq '/plugins/plugin-8 string pulseaudio' "$INSTALLER" || fail "plugin de volume não está fixo no painel principal XFCE"
grep -Fq '#pulseaudio-button > box > image' "$INSTALLER" || fail "ajuste de escala do ícone de volume XFCE ausente"
if [[ -f "$XFCE_WHISKER_HELPER" ]] && grep -Eq -- '^[[:space:]]*(exec[[:space:]]+)?xfce4-popup-whiskermenu([^#]*[[:space:]])(-p|--pointer)([[:space:]]|$)' "$XFCE_WHISKER_HELPER"; then
    fail "helper Whisker voltou a abrir literalmente sob o ponteiro"
fi
if [[ -f "$XFCE_WHISKER_HELPER" ]]; then
    event_line="$(grep -nE '^[[:space:]]*(if[[:space:]]+)?xfce4-panel --plugin-event=.*whiskermenu-' "$XFCE_WHISKER_HELPER" | head -n1 | cut -d: -f1 || true)"
    instance_line="$(grep -nF 'xfce4-popup-whiskermenu --instance=' "$XFCE_WHISKER_HELPER" | head -n1 | cut -d: -f1 || true)"
    if [[ ! "$event_line" =~ ^[0-9]+$ || ! "$instance_line" =~ ^[0-9]+$ || "$event_line" -ge "$instance_line" ]]; then
        fail "Whisker não prioriza o remote event do painel antes do fallback --instance"
    fi
fi
if [[ -f "$XFCE_DESKTOP_SETUP" ]]; then
    xfce_apply_block="$(sed -n '/^[[:space:]]*apply)$/,/^[[:space:]]*;;/p' "$XFCE_DESKTOP_SETUP" 2>/dev/null || true)"
    if grep -Eq 'apply_(style|wallpaper|terminal_style)' <<<"$xfce_apply_block"; then
        fail "autostart XFCE reaplica aparência após o primeiro login"
    fi
fi
if grep -Fq "setcmd '<Primary><Alt><Shift>F12' 'xfce4-popup-whiskermenu --pointer'" "$INSTALLER"; then
    fail "atalho Super do XFCE voltou a usar --pointer"
fi
grep -Fq '/general/placement_mode' "$INSTALLER" || fail "XFWM não posiciona novas janelas pelo monitor do ponteiro"
grep -Fq '/general/use_compositing' "$INSTALLER" || fail "política de compositor XFCE ausente no instalador"
grep -Fq 'set_prop xfwm4 /general/use_compositing bool false' "$XFCE_DESKTOP_SETUP" || fail "setup XFCE não desliga compositor por padrão"
grep -Fq '/general/use_compositing' "$XFCE_POLISH_FIX" || fail "fixer XFCE não mantém compositor nativo desligado"
grep -Fq 'wolf-xfce-compositor persist-xrender' "$XFCE_POLISH_FIX" || fail "fixer XFCE não promove Picom/XRender persistente"
grep -Fq '/usr/local/bin/wolf-xfce-whisker-placement' "$INSTALLER" || fail "posicionamento contextual XFCE ausente"
grep -Fq 'wolf-xfce-whisker-placement.desktop' "$INSTALLER" || fail "autostart do posicionamento contextual ausente"
grep -Fq 'wolf-xfce-super-key.desktop' "$INSTALLER" || fail "autostart persistente do Super/xcape ausente"
grep -Fq '/usr/local/bin/wolf-xfce-super-setup' "$INSTALLER" || fail "setup autocorretivo do Super XFCE ausente"
grep -Fq 'NotShowIn=XFCE;' "$INSTALLER" || fail "helper global de atalhos ainda compete no XFCE"
if grep -Fq "sleep 4; exec /usr/local/bin/wolf-xfce-super-setup" "$INSTALLER"; then
    fail "Super XFCE ainda possui atraso fixo de 4s"
fi
if [[ -f "$XFCE_SUPER_HELPER" ]]; then
    grep -Fq "setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'" "$XFCE_SUPER_HELPER" \
        || fail "binding privado do Super ausente"
    grep -Fq "setcmd '<Primary><Alt><Shift>F12' '/usr/local/bin/wolf-xfce-whisker-current'" "$XFCE_SUPER_HELPER" \
        || fail "helper Super não reafirma binding privado do Whisker"
    if grep -Fq -- 'xfce4-popup-whiskermenu --pointer' "$XFCE_SUPER_HELPER"; then
        fail "helper Super contém binding --pointer legado"
    fi
fi
grep -Fq '/usr/local/bin/wolf-xfce-launch-here' "$INSTALLER" || fail "wrapper de launchers por monitor ausente"
grep -Fq 'xprop -root -spy _NET_CLIENT_LIST _NET_ACTIVE_WINDOW' "$INSTALLER" || fail "placement XFCE não está orientado a eventos EWMH"
grep -Fq 'xev -root -event randr' "$INSTALLER" || fail "MultiMonitor XFCE não está orientado a eventos RandR"
if [[ -f "$XFCE_PLACEMENT_HELPER" ]] && grep -Fq 'POLL_SECONDS=' "$XFCE_PLACEMENT_HELPER"; then
    fail "placement XFCE voltou a usar polling contínuo"
fi
if [[ -f "$XFCE_PLACEMENT_HELPER" ]]; then
    grep -Fq 'whisker_until=0' "$XFCE_PLACEMENT_HELPER" \
        || fail "contexto Whisker não é consumido após a primeira janela"
fi
if [[ -f "$XFCE_MULTIMONITOR_HELPER" ]] && grep -Eq '^[[:space:]]*xfce4-panel[[:space:]]+-r([[:space:]]|$)' "$XFCE_MULTIMONITOR_HELPER"; then
    fail "MultiMonitor XFCE não deve reiniciar o painel em reconciliações normais"
fi
grep -Fq 'wmctrl' "$PROJECT/package-profiles/packages.conf" || fail "wmctrl ausente do perfil XFCE"
grep -Fq 'xorg-xprop' "$PROJECT/package-profiles/packages.conf" || fail "xorg-xprop ausente do perfil XFCE"
grep -Fq 'xorg-xev' "$PROJECT/package-profiles/packages.conf" || fail "xorg-xev ausente do perfil XFCE"
grep -Fq 'Abrir esta pasta no VS Code' "$INSTALLER" || fail "ação Thunar -> VS Code ausente"
grep -Fq 'org.xfce.ristretto.desktop' "$INSTALLER" || fail "Ristretto não definido como visualizador de imagens"
grep -Fq 'wolf-xfce-default-apps' "$INSTALLER" || fail "defaults XFCE ausentes"
if [[ -f "$XFCE_DEFAULTS_HELPER" ]]; then
    grep -Fq 'set_default org.xfce.mousepad.desktop text/plain' "$XFCE_DEFAULTS_HELPER" \
        || fail "text/plain não é reafirmado como Mousepad após LibreOffice"
fi
grep -Fq 'OnlyShowIn=XFCE;' "$INSTALLER" || fail "autostarts XFCE ausentes"
grep -Fq '50-wolf-mouse-no-accel.conf' "$INSTALLER" || fail "perfil flat do mouse ausente no XFCE"
grep -Fq 'wolf-whisker.png' "$INSTALLER" || fail "ícone Wolf do Whisker ausente"

# Regressões do painel XFCE:
# - 1.0.37: expansão de variável na mesma declaração `local` (SC2318);
# - 1.0.38: status 1 vazando de configure_all_whiskers sob `set -e`.
for xfce_source in "$INSTALLER" "$XFCE_DESKTOP_SETUP" "$XFCE_POLISH_FIX"; do
    [[ -f "$xfce_source" ]] || continue
    if grep -Eq '^[[:space:]]*local[[:space:]]+id=.*[[:space:]]+rc=' "$xfce_source"; then
        fail "regressão SC2318 no configure_whisker: $xfce_source"
    fi
    whisker_block="$(sed -n '/configure_all_whiskers()/,/^}/p' "$xfce_source" 2>/dev/null || true)"
    grep -Fq 'return 0' <<<"$whisker_block"         || fail "configure_all_whiskers pode propagar status 1 sob set -e: $xfce_source"
done
grep -Fq 'PANEL_RESTART_PENDING=1' "$INSTALLER" || fail "fail-safe de reinício do painel XFCE ausente"
grep -Fq 'report_setup_error' "$INSTALLER" || fail "diagnóstico de erro do setup XFCE ausente"

literal_dollar='$'
printf -v bad_mime_regex '"\\%smime"[[:space:]]*==[[:space:]]*\\%sfilter' \
    "$literal_dollar" "$literal_dollar"
for defaults_source in "$INSTALLER" "$XFCE_DEFAULTS_HELPER" "$XFCE_POLISH_FIX"; do
    [[ -f "$defaults_source" ]] || continue
    if grep -Eq "$bad_mime_regex" "$defaults_source"; then
        fail "regressão SC2053 no filtro MIME: $defaults_source"
    fi
done

# Alt+Tab do XFCE: somente workspace atual e monitor sob o ponteiro.
grep -Fq 'XFCE_THIRD_PARTY_PACKAGES' "$PACKAGES" || fail "bloco third-party do XFCE ausente"
grep -Eq '^[[:space:]]*alttab([[:space:]]|$)' <<<"$(sed -n '/^XFCE_THIRD_PARTY_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"     || fail "alttab ausente do perfil third-party do XFCE"
grep -Fq '/usr/local/bin/wolf-xfce-alttab' "$INSTALLER" || fail "helper Alt+Tab do XFCE ausente"
grep -Fq 'ALTTAB_ARGS=(-w 1 -d 0 -sc 0 -vp pointer)' "$INSTALLER" || fail "Alt+Tab XFCE não está filtrando pelo monitor do ponteiro"
grep -Fq '/xfwm4/custom/<Alt>Tab' "$INSTALLER" || fail "Alt+Tab nativo do xfwm4 não é liberado"
grep -Fq 'wolf-xfce-alttab.desktop' "$INSTALLER" || fail "autostart do Alt+Tab por monitor ausente"
# Systray deve existir no painel principal, mas nunca no layout secundário v0.5.
if [[ -f "$XFCE_MULTIMONITOR_HELPER" ]]; then
    if sed -n '/create_secondary_layout()/,/^}/p' "$XFCE_MULTIMONITOR_HELPER" | grep -Fq 'systray'; then
        fail "painel secundário XFCE ainda tenta criar systray duplicado"
    fi
    if sed -n '/create_secondary_layout()/,/^}/p' "$XFCE_MULTIMONITOR_HELPER" | grep -Fq 'showdesktop'; then
        fail "painel secundário XFCE não deve ter Show Desktop global"
    fi
fi
grep -Fq "'<Super>e'" "$INSTALLER" || fail "atalho Super+E não configurado"
grep -Fq 'button.connect("clicked", self._on_clicked, window)' "$INSTALLER" || fail "Wolf Monitor Tasks sem clique funcional"

if [[ -f "$GAMEPAD_HELPER" ]]; then
    grep -Fq 'Bonded' "$GAMEPAD_HELPER" || fail "helper de gamepad não valida bonding BlueZ"
    grep -Fq '/dev/uhid' "$GAMEPAD_HELPER" || fail "helper de gamepad não valida UHID"
    grep -Fq '/proc/bus/input/devices' "$GAMEPAD_HELPER" || fail "helper de gamepad não valida input device"
    grep -Fq 'ClassicBondedOnly' "$GAMEPAD_HELPER" || fail "helper de gamepad não diagnostica política HID do BlueZ"
    grep -Fq 'input_event_nodes' "$GAMEPAD_HELPER" || fail "helper de gamepad não identifica event nodes"
    grep -Fq 'clean_repair_selected' "$GAMEPAD_HELPER" || fail "helper de gamepad não oferece reparo de bonding"
fi
GAMING_BLOCK="$(sed -n '/^GAMING_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"
for pkg in steam-devices evtest joyutils; do
    grep -Eq "^[[:space:]]*${pkg}([[:space:]]|$)" <<<"$GAMING_BLOCK" || fail "pacote gaming ausente: $pkg"
done
GAMING_3P_BLOCK="$(sed -n '/^GAMING_THIRD_PARTY_PACKAGES=(/,/^)/p' "$PACKAGES" 2>/dev/null || true)"
grep -Eq '^[[:space:]]*xpadneo-dkms([[:space:]]|$)' <<<"$GAMING_3P_BLOCK" || fail "xpadneo-dkms ausente do perfil third-party gaming"
grep -Fq '/usr/local/bin/wolf-gamepad-setup' "$INSTALLER" || fail "helper Wolf Gamepad não é instalado no sistema"
grep -Fq 'hid_xpadneo' "$INSTALLER" || fail "xpadneo não é pré-carregado pela instalação"
grep -Fq 'uhid' "$INSTALLER" || fail "UHID não é pré-carregado pela instalação"

echo "[OK] linux-lts fallback + identidade Wolf + XFCE polido; MATE marcado como legado"
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
