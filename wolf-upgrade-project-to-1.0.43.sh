#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-${WOLF_PROJECT:-$HOME/wolf-linux}}"

echo "============================================================"
echo "         WOLF LINUX - UPGRADE DO PROJETO PARA 1.0.43"
echo "============================================================"
echo
echo "Projeto: $PROJECT"
echo "assets/ será preservado."
echo

[[ -d "$PROJECT" ]] || {
    echo "[ERRO] Projeto não encontrado: $PROJECT"
    exit 1
}

mkdir -p "$PROJECT/install" "$PROJECT/package-profiles" "$PROJECT/tests" "$PROJECT/tools"

cp -f "$SELF_DIR/wolf-install.sh" "$PROJECT/install/wolf-install.sh"
chmod 755 "$PROJECT/install/wolf-install.sh"

cp -f "$SELF_DIR/wolf-linux-packages-v0.1.conf" \
    "$PROJECT/package-profiles/packages.conf"

for tool in \
    wolf-fix-directory-handler-1.0.22.sh \
    wolf-apply-current-system-hooks-1.0.21.sh \
    wolf-multimonitor-setup-0.4.sh \
    wolf-install-multimonitor-auto-0.4.sh \
    wolf-fix-cinnvii-super-monitor-0.2.sh \
    wolf-plasma-multimonitor-0.1.sh \
    wolf-mate-multimonitor-0.3.py \
    wolf-monitor-tasks.py \
    wolf-xfce-multimonitor-0.5.sh \
    wolf-xfce-desktop-setup-0.7.sh \
    wolf-xfce-whisker-current-0.3.sh \
    wolf-xfce-whisker-placement-0.2.sh \
    wolf-xfce-default-apps-0.2.sh \
    wolf-xfce-alttab-0.1.sh \
    wolf-xfce-launch-here-0.1.sh \
    wolf-gamepad-setup-0.3.sh \
    wolf-fix-xfce-polish-1.0.43.sh \
    wolf-repair-kernels-1.0.35.sh
do
    [[ -f "$SELF_DIR/$tool" ]] || {
        echo "[ERRO] Arquivo do DevKit ausente: $tool"
        exit 1
    }
    cp -f "$SELF_DIR/$tool" "$PROJECT/tools/$tool"
    chmod 755 "$PROJECT/tools/$tool"
done

for helper in \
    wolf-build-iso.sh \
    wolf-test-iso.sh \
    wolf-smoke-test.sh \
    wolf-serve.sh \
    wolf-run-arch-test.sh \
    wolf-enable-ssh-live.sh \
    wolf-vm-ssh.sh \
    wolf-customize-iso-profile.sh \
    wolf-finalize-1.0.sh \
    wolf-fix-mouse-no-accel-1.0.2.sh \
    wolf-remove-window-mover-1.0.6.sh \
    wolf-fix-cinnamon-polish-1.0.17.sh
do
    cp -f "$SELF_DIR/$helper" "$PROJECT/tests/$helper"
    chmod 755 "$PROJECT/tests/$helper"
done

# Remove versões antigas de helpers que podem confundir testes manuais.
rm -f "$PROJECT/tests"/wolf-fix-cinnamon-polish-1.0.15.sh
rm -f "$PROJECT/tests"/wolf-fix-cinnamon-polish-1.0.16.sh
rm -f "$PROJECT/tools/wolf-multimonitor-setup-0.3.sh"
rm -f "$PROJECT/tools/wolf-install-multimonitor-auto-0.3.sh"
rm -f "$PROJECT/tools/wolf-fix-cinnvii-super-monitor-0.1.sh"
rm -f "$PROJECT/tools/wolf-mate-multimonitor-0.1.py"
rm -f "$PROJECT/tools/wolf-mate-multimonitor-0.2.py"
rm -f "$PROJECT/tools/wolf-xfce-multimonitor-0.1.sh"
rm -f "$PROJECT/tools/wolf-xfce-multimonitor-0.2.sh"
rm -f "$PROJECT/tools/wolf-xfce-desktop-setup-0.1.sh"
rm -f "$PROJECT/tools/wolf-xfce-desktop-setup-0.2.sh"
rm -f "$PROJECT/tools/wolf-xfce-desktop-setup-0.3.sh"
rm -f "$PROJECT/tools/wolf-xfce-desktop-setup-0.4.sh"
rm -f "$PROJECT/tools/wolf-xfce-desktop-setup-0.5.sh"
rm -f "$PROJECT/tools/wolf-xfce-whisker-current-0.1.sh"
rm -f "$PROJECT/tools/wolf-gamepad-setup-0.1.sh"
rm -f "$PROJECT/tools/wolf-xfce-default-apps-0.1.sh"
rm -f "$PROJECT/tools/wolf-xfce-multimonitor-0.3.sh"
rm -f "$PROJECT/tools/wolf-xfce-multimonitor-0.4.sh"
rm -f "$PROJECT/tools/wolf-xfce-desktop-setup-0.6.sh"
rm -f "$PROJECT/tools/wolf-xfce-whisker-current-0.2.sh"
rm -f "$PROJECT/tools/wolf-xfce-whisker-placement-0.1.sh"
rm -f "$PROJECT/tools/wolf-gamepad-setup-0.2.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-polish-1.0.41.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-polish-1.0.42.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-polish-1.0.36.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-polish-1.0.37.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-polish-1.0.38.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-polish-1.0.39.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-polish-1.0.40.sh"
rm -f "$PROJECT/tools/wolf-fix-xfce-layout-1.0.35.sh"
rm -f "$PROJECT/tests"/wolf-fix-monitor-toggle-*.sh
rm -f "$PROJECT/tests/wolf-fix-audio-titlebar-v0.43.sh"
rm -f "$PROJECT/tests/wolf-fix-csd-dark-v0.45.sh"
rm -f "$PROJECT/tests/wolf-fix-csd-gnome-disks-v0.46.sh"

WOLF_PROJECT="$PROJECT" "$PROJECT/tests/wolf-customize-iso-profile.sh"
WOLF_PROJECT="$PROJECT" TERM="${TERM:-xterm}" "$PROJECT/tests/wolf-smoke-test.sh"

echo
echo "[OK] Projeto Wolf Linux 1.0.43 atualizado."
echo "Cinnamon: permanece validado e sem alterações funcionais nesta revisão."
echo "KDE Plasma: permanece validado e sem alterações funcionais nesta revisão."
echo "MATE: marcado como legado/para remoção; mantido temporariamente apenas para rollback."
echo "XFCE: elimina polling contínuo dos helpers, preserva customizações do painel, ancora o Whisker explicitamente ao applet e corrige o ícone de volume.
XFCE: launchers Chrome/Home/Terminal e lançamentos via Whisker usam contexto de monitor orientado a eventos.
Fontes: mantém Noto/emoji e acrescenta fallbacks Nerd Symbols normal e mono."
echo "Gamepad: helper 0.3 mantém o reparo validado e corrige o último alerta ShellCheck."
echo ""
echo "Próximos comandos:"
echo "  cd \"$PROJECT\""
echo "  ./tests/wolf-build-iso.sh"
