#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
SOURCE="$PROJECT/live-gui"
CUSTOMIZER="$PROJECT/tests/wolf-customize-iso-profile.sh"
STAGER="$PROJECT/tests/wolf-stage-live-desktop.sh"
[[ -r "$SOURCE/main.py" && -x "$STAGER" ]] || { echo '[ERRO] Sources live GUI ausentes.' >&2; exit 1; }
python3 -m py_compile "$SOURCE/main.py" "$SOURCE/wolf_plan.py"
python3 "$SOURCE/main.py" --self-test
# A variante ThinkPad usa XKB br(thinkpad), sem interferir com ABNT2 padrão.
grep -Fq '"Português (Brasil) — ThinkPad (IBM/Lenovo)", "br", "abnt2", "thinkpad"' "$SOURCE/main.py" || { echo '[ERRO] Variante ThinkPad brasileira ausente.' >&2; exit 1; }
# Regressões específicas da alpha21: teclado primeiro, resumo sem botão,
# seletor gráfico de Wi-Fi e gerenciamento exclusivo pelo NetworkManager.
grep -Fq 'keyboard = KeyboardDialog()' "$SOURCE/main.py" || { echo '[ERRO] Teclado não antecede a janela principal.' >&2; exit 1; }
grep -Fq 'self.refresh_summary()' "$SOURCE/main.py" || { echo '[ERRO] Resumo automático ausente.' >&2; exit 1; }
if grep -Fq 'Gerar resumo de pré-planejamento' "$SOURCE/main.py"; then
    echo '[ERRO] Botão redundante de resumo presente.' >&2; exit 1
fi
grep -Fq 'nm-applet' "$SOURCE/home/.config/openbox/autostart" || { echo '[ERRO] Seletor Wi-Fi gráfico ausente no autostart.' >&2; exit 1; }
grep -Fq 'stalonetray' "$SOURCE/home/.config/openbox/autostart" || { echo '[ERRO] Bandeja gráfica ausente.' >&2; exit 1; }
grep -Fq 'GParted — Particionador' "$SOURCE/main.py" || { echo '[ERRO] Rótulo GParted não ajustado.' >&2; exit 1; }
python3 "$PROJECT/tests/wolf-test-live-planner.py"
python3 "$PROJECT/tests/wolf-test-gui-contract.py"
python3 "$PROJECT/tests/wolf-test-gui-ux.py"
python3 "$PROJECT/tests/wolf-test-gui-vm26.py"
python3 "$PROJECT/tests/wolf-test-gui-vm27.py"
python3 "$PROJECT/tests/wolf-test-gui-finish.py"
python3 "$PROJECT/tests/wolf-test-gui-alpha29.py"
python3 "$PROJECT/tests/wolf-test-aur-empty-alpha29.py"
grep -Fq 'wolf-live-simulate-plan' "$SOURCE/main.py" || { echo '[ERRO] Botão de simulação ausente na GUI.' >&2; exit 1; }
grep -Fq 'self.home_layout' "$SOURCE/main.py" || { echo '[ERRO] /home integrado ausente na GUI.' >&2; exit 1; }
python3 - "$SOURCE" <<'PYXML'
from pathlib import Path
import sys, xml.etree.ElementTree as ET
p=Path(sys.argv[1])
for f in [p/'home/.config/openbox/menu.xml']:
    ET.parse(f)
print('[OK] Configurações XML Openbox válidas')
PYXML
grep -Fq 'wolf-brand-live-boot.py' "$CUSTOMIZER" || { echo '[ERRO] Identidade do boot não é aplicada.' >&2; exit 1; }
grep -Fq 'wolf-stage-live-desktop.sh' "$CUSTOMIZER" || { echo '[ERRO] Stager não chamado pelo customizador.' >&2; exit 1; }
grep -Fq 'wolf-stage-live-desktop.sh' "$PROJECT/tests/wolf-build-iso.sh" || { echo '[ERRO] Build não chama stager gráfico.' >&2; exit 1; }
python3 - "$SOURCE/main.py" <<'PYSAFETY'
from pathlib import Path
import ast, sys
source=Path(sys.argv[1]).read_text()
tree=ast.parse(source)
# Lista conservadora de chamadas de execução destrutiva que não podem aparecer na prévia.
for token in ('--install', '--vm-install', 'mkfs.', 'wipefs', 'parted --script', 'dd if='):
    assert token not in source, f'GUI contém operação destrutiva direta: {token}'
assert 'wolf-live-execute-vm-plan' in source, 'GUI não oferece executor VM limitado'
print('[OK] GUI mantém comandos destrutivos isolados no backend Bash com confirmação')
PYSAFETY
[[ -f "$PROJECT/install/wolf-install.sh" ]] || exit 1
if grep -Fq 'openbox' "$PROJECT/package-profiles/packages.conf"; then
    echo '[ERRO] Openbox não pode entrar nas stacks do sistema instalado.' >&2; exit 1
fi
if [[ -d "$PROJECT/iso-profile" ]]; then
    PROFILE="$PROJECT/iso-profile"
    WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROFILE" "$STAGER" >/dev/null
    WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROFILE" "$STAGER" >/dev/null
    for pkg in openbox xorg-server xorg-xinit xorg-setxkbmap pyside6 qterminal pcmanfm-qt gparted network-manager-applet nm-connection-editor stalonetray lxqt-policykit; do
        [[ "$(grep -Fxc "$pkg" "$PROFILE/packages.x86_64")" == 1 ]] || { echo "[ERRO] Pacote live duplicado/ausente: $pkg" >&2; exit 1; }
    done
    for f in \
        "$PROFILE/airootfs/usr/local/bin/wolf-live-installer" \
        "$PROFILE/airootfs/usr/local/bin/wolf-live-network" \
        "$PROFILE/airootfs/usr/local/bin/wolf-live-review-plan" \
        "$PROFILE/airootfs/usr/local/bin/wolf-live-simulate-plan" \
        "$PROFILE/airootfs/usr/local/bin/wolf-live-execute-vm-plan" \
        "$PROFILE/airootfs/usr/local/bin/wolf-live-create-user" \
        "$PROFILE/airootfs/usr/local/share/wolf-linux-live/gui/main.py" \
        "$PROFILE/airootfs/usr/local/share/wolf-linux-live/gui/wolf_plan.py" \
        "$PROFILE/airootfs/root/wolf-linux/live-gui/wolf_plan.py" \
        "$PROFILE/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf" \
        "$PROFILE/airootfs/etc/sudoers.d/90-wolf-live" \
        "$PROFILE/airootfs/usr/share/wolf-live/home/.config/openbox/menu.xml"; do
        [[ -f "$f" ]] || { echo "[ERRO] Staging live ausente: $f" >&2; exit 1; }
    done
    [[ -L "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/wolf-live-user.service" ]] || exit 1
    [[ -L "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]] || exit 1
    [[ "$(stat -c %a "$PROFILE/airootfs/etc/sudoers.d/90-wolf-live")" == 440 ]] || exit 1
    echo '[OK] Staging live: scripts, usuário, autologin, permissões e pacotes idempotentes.'
else
    echo '[AVISO] Sem iso-profile; verificando apenas fontes do Wolf Live GUI.'
fi
