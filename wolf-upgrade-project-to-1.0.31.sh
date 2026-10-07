#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-${WOLF_PROJECT:-$HOME/wolf-linux}}"

echo "============================================================"
echo "         WOLF LINUX - UPGRADE DO PROJETO PARA 1.0.31"
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
    wolf-mate-multimonitor-0.1.py \
    wolf-monitor-tasks.py
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
rm -f "$PROJECT/tests"/wolf-fix-monitor-toggle-*.sh
rm -f "$PROJECT/tests/wolf-fix-audio-titlebar-v0.43.sh"
rm -f "$PROJECT/tests/wolf-fix-csd-dark-v0.45.sh"
rm -f "$PROJECT/tests/wolf-fix-csd-gnome-disks-v0.46.sh"

"$PROJECT/tests/wolf-customize-iso-profile.sh"
TERM="${TERM:-xterm}" "$PROJECT/tests/wolf-smoke-test.sh"

echo
echo "[OK] Projeto Wolf Linux 1.0.31 atualizado."
echo "Cinnamon: Wolf MultiMonitor v0.4 permanece automático; Super abre o CinnVII do monitor do ponteiro."
echo "KDE Plasma: painel por tela + Task Manager limitado à tela atual, automático por padrão."
echo "MATE: Wolf Monitor Tasks instalado, mas MultiMonitor permanece experimental até teste em hardware."
echo
echo "No MATE, quando houver hardware para validar:"
echo "  wolf-multimonitor status"
echo "  wolf-multimonitor enable"
echo
echo "Próximos comandos:"
echo "  cd \"$PROJECT\""
echo "  ./tests/wolf-build-iso.sh"
