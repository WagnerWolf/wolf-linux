#!/usr/bin/env python3
"""Wolf KDE 2.3 Stable: baseline static regression checks (no devices touched)."""
from pathlib import Path
import re, subprocess, sys, tempfile, os
project=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
pkg=(project/'package-profiles/packages.conf').read_text()
installer=(project/'install/wolf-install.sh').read_text()
def check(condition, desc):
    if not condition: raise SystemExit('[FALHA] '+desc)
    print('[OK] '+desc)
check('KDE_PACKAGES=(' in pkg and 'LXQT_PACKAGES=(' not in pkg,'KDE stack declarativa ativa')
for key in ('plasma-workspace','plasma-desktop','kwin','kscreen','xdg-desktop-portal-kde','dolphin','xorg-xwayland','kwallet-pam'):
    check(key in pkg, 'pacote KDE '+key)
for banned in ('plasma-meta','discover','plasma-x11-session','lxqt-panel','openbox','picom','pcmanfm-qt'):
    lines=re.findall(r'^\s*'+re.escape(banned)+r'(?:\s|$)',pkg,re.M)
    check(not lines, 'sem componente legado instalado: '+banned)
check('DESKTOP="plasma"' in installer,'desktop padrao Plasma')
# Garantir coerência entre a identidade gravada e a validação no instalador.
# Isso previne regressão 2.2 -> 2.3: a validação antiga interrompia TODAS as instalações.
os_release_match = re.search(r"cat > /mnt/etc/os-release <<'EOF'\n(.*?)\nEOF", installer, re.S)
check(os_release_match is not None, 'bloco /etc/os-release presente')
os_release_body = os_release_match.group(1)
pretty_name = re.search(r'^PRETTY_NAME="([^"]+)"$', os_release_body, re.M)
check(pretty_name is not None, 'PRETTY_NAME gravado explicitamente')
identity_guard = re.search(r"grep -Fxq 'PRETTY_NAME=\"([^\"]+)\"' /mnt/etc/os-release", installer)
check(identity_guard is not None, 'validação PRETTY_NAME explícita')
check(pretty_name.group(1) == identity_guard.group(1), 'nome do sistema coincide com validação da etapa 61')
version_file = (project/'VERSION').read_text().strip()
version_value = re.search(r'^VERSION_ID="([^"]+)"$', os_release_body, re.M)
check(version_value is not None and version_value.group(1) == version_file, 'VERSION_ID coincide com VERSION do projeto')
check(r'grep -Fxq "VERSION_ID=\"${WOLF_VERSION}\""' in installer, 'validação de VERSION_ID dinâmica')
check('  3) Minimal - somente KDE Plasma/Wayland' in installer, 'CLI Minimal sem referências LXQt')
check('stage "69c2-plasma-base" validate_plasma_base' in installer,'valida Plasma')
check('stage "69c2-painel-sem-discover" install_wolf_plasma_panel_defaults' in installer,'limpa Discover')
check('stage "69d2-wolf-plasma" install_wolf_plasma_profile' in installer,'primeiro login KDE')
for forbidden in ('stage "69d2-wolf-lxqt"','stage "69d3-formato-usb-menu-wolf"','stage "69d4-links-simbolicos-wolf"','verificar-abi-lxqt-24.sh" ||'):
    check(forbidden not in installer,'sem estagio LXQt ativo: '+forbidden)
check('OnlyShowIn=KDE;' in installer,'autostart Package Manager KDE')
check('Session=plasma.desktop' in installer,'SDDM seleciona Wayland')
check('wolf-first-login-plasma' in installer,'helper first-login integrado')
check('wolf-monitors.py "$@"' not in installer, 'KScreen em lugar de XRandR')
check('org.kde.dolphin.desktop' in (project/'tests/wolf-configure-user-defaults.py').read_text(),'Dolphin MIME')
check('KDE/Wayland Target - Openbox Live' in (project/'tests/wolf-customize-iso-profile.sh').read_text(),'Live e destino separados')
preview_ui=(project/'live-gui/preview/app.py').read_text()
check('Minimal — KDE Plasma/Wayland essencial' in preview_ui, 'perfil Minimal correto na GUI')
check('LXQt' not in preview_ui and 'lxqt' not in preview_ui, 'sem referências LXQt no instalador gráfico')
check('Dimensionamento bloqueado' in preview_ui and 'self.erase_root_group.setEnabled(False)' in preview_ui, 'GUI bloqueia sliders em disco inválido')
check('self.update_erase_budget()\n        self.update_profile_space()' in preview_ui, 'orçamento recalculado antes do aviso de espaço')
check(subprocess.run([sys.executable,str(project/'tests/wolf-test-kde-erase-budget.py'),str(project)]).returncode==0, 'limites de disco e preflight canônico em inventários artificiais')
for target in ('install/wolf-install.sh','tests/wolf-customize-iso-profile.sh','tests/wolf-build-iso.sh',
               'preparar_ambiente_wolf_linux.sh','gerar-iso.sh','tools/wolf-first-login-plasma.sh'):
    p=project/target
    check(subprocess.run(['bash','-n',str(p)]).returncode==0,'bash -n '+target)
for target in ('tools/control-center/main.py','tools/control-center/backend.py',
               'tools/control-center/wolf_profile.py','tests/wolf-configure-user-defaults.py'):
    p=project/target
    check(subprocess.run([sys.executable,'-c','import ast,sys;ast.parse(open(sys.argv[1]).read())',str(p)]).returncode==0,
          'python AST '+target)
# Preview1 Fix1: guard direct shell-script execution and archive exec bits.
for target in ('tests/wolf-customize-iso-profile.sh', 'tests/wolf-stage-live-ssh.sh',
               'tests/wolf-stage-live-desktop.sh', 'tests/wolf-build-iso.sh'):
    check(os.access(project/target, os.X_OK), 'permissão de execução: '+target)
check('bash "$PROJECT/tests/wolf-build-iso.sh"' in (project/'gerar-iso.sh').read_text(),
      'gerador invoca build via bash')
check((project/'assets/kde/wolf-linux-kickoff.svg').exists(),'branding Plasma SVG')
check((project/'tests/wolf-reconcile-assets-2.3.0.py').exists(), 'preflight independente de assets no DevKit')
check((project/'tools/experimental/wolf-plasma-multimonitor-0.3.sh').exists(),'painel nativo multi monitor')
check((project/'tools/experimental/wolf-plasma-branding-0.2.sh').exists(),'brand nativo Plasma')
check((project/'VERSION').read_text().strip() == '2.3.1', 'versionamento release')
check('thorium-browser-avx2-bin' in pkg and 'google-chrome' not in pkg, 'Thorium AVX2 na stack AUR, sem Chrome')
check('CHROME_EXECUTABLE=/usr/local/bin/wolf-thorium' in installer, 'Flutter usa wrapper Thorium')
check('thorium-browser-avx2.desktop' in (project/'tests/wolf-configure-user-defaults.py').read_text(), 'MIME Thorium KDE')
check('grep -qE' in installer and '/proc/cpuinfo' in installer, 'CPU AVX2 validada antes de formatar')
check(subprocess.run([sys.executable,str(project/'tests/wolf-test-thorium-2.3.0.py'),str(project)]).returncode==0,
      'regressões Thorium, Flutter e AUR')
print('[OK] Smoke estático KDE 2.3.1 Release aprovado. Testar a ISO gerada antes de distribuir.')
