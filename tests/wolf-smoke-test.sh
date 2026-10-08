#!/usr/bin/env bash
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
INSTALLER="$PROJECT/install/wolf-install.sh"
PACKAGES="$PROJECT/package-profiles/packages.conf"
CUSTOMIZER="$PROJECT/tests/wolf-customize-iso-profile.sh"
STAGE_SSH="$PROJECT/tests/wolf-stage-live-ssh.sh"
ERRORS=0

ok(){ printf '[OK] %s\n' "$*"; }
err(){ printf '[ERRO] %s\n' "$*" >&2; ERRORS=1; }
check_shell(){
    local f="$1"
    printf '\n>> %s\n' "$f"
    bash -n "$f" && ok 'bash -n' || err "bash -n falhou: $f"
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$f" && ok shellcheck || err "shellcheck falhou: $f"
    else
        printf '[AVISO] shellcheck não instalado neste ambiente.\n'
    fi
}

printf '%s\n' '======================================================'
printf '%s\n' '    WOLF LINUX 2.0 KDE BASELINE - SMOKE TEST'
printf '%s\n' '======================================================'

for f in "$INSTALLER" "$CUSTOMIZER" "$STAGE_SSH" "$PROJECT/tests/wolf-build-iso.sh" "$PROJECT/tests/wolf-test-iso.sh" "$PROJECT/tests/wolf-vm.sh" "$PROJECT/tests/wolf-enable-ssh-live.sh" "$PROJECT/tests/wolf-vm-ssh.sh" "$PROJECT/tools/wolf-helper-manager-0.2.sh" "$PROJECT/tools/wolf-validate-helpers-0.1.sh"; do
    [[ -f "$f" ]] || { err "Arquivo ausente: $f"; continue; }
    check_shell "$f"
done

while IFS= read -r -d '' f; do check_shell "$f"; done < <(find "$PROJECT/tools/stable" "$PROJECT/tools/experimental" -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null)

[[ -f "$PACKAGES" ]] || err "Manifesto ausente: $PACKAGES"

printf '\n>> Validando preparação limpa do projeto...\n'
PREPARER="$PROJECT/preparar_ambiente_wolf_linux.sh"
if [[ -f "$PREPARER" ]]; then
    check_shell "$PREPARER"
    grep -Fq '/usr/share/archiso/configs/releng' "$PREPARER" || err 'Preparador não parte do releng oficial'
    grep -Fq 'wolf-stage-live-ssh.sh' "$PREPARER" || err 'Preparador não executa o staging SSH'
    grep -Fq 'wolf-enable-ssh-live' "$PREPARER" || err 'Preparador não valida o SSH live no airootfs'
    grep -Fq 'rm -rf -- "$PROJECT"' "$PREPARER" || err 'Preparador não suporta reconstrução realmente limpa'
    ok 'Preparador clean-room presente e validado'
else
    err 'preparar_ambiente_wolf_linux.sh ausente na raiz do projeto'
fi

printf '\n>> Validando arquitetura KDE-only...\n'
grep -Fq 'DESKTOP="plasma"' "$INSTALLER" || err 'DESKTOP não está fixado em plasma'
grep -Fq 'KDE Plasma / Wayland' "$INSTALLER" || err 'Instalador não declara KDE/Wayland'
main_block="$(sed -n '/^main() {/,/^}/p' "$INSTALLER")"
if grep -Eq 'xfce|cinnamon|mate|install_wolf_multimonitor_all_desktops|install_wolf_desktop_branding|install_wolf_desktop_keybindings' <<< "$main_block"; then
    err 'main ainda chama automação de desktop legado'
fi
ok 'KDE/Wayland é a única baseline ativa'

printf '\n>> Validando stacks opcionais...\n'
for token in 'daily' 'gaming' 'development' 'android' 'containers' 'extras' '--preset full' '--preset test' '--preset minimal'; do
    grep -Fq -- "$token" "$INSTALLER" || err "Stack/preset ausente: $token"
done
grep -Fq 'heroic-games-launcher-bin' "$PACKAGES" || err 'Heroic ausente'
grep -Fq 'discord' "$PACKAGES" || err 'Discord ausente'
grep -Fq 'lutris' "$PACKAGES" || err 'Lutris ausente'
grep -Fq 'docker-compose' "$PACKAGES" || err 'Docker Compose ausente'
if grep -Eq '^[[:space:]]+(gamescope|goverlay|mangohud|lib32-mangohud)([[:space:]]|$)' "$PACKAGES"; then
    err 'Gaming ainda inclui MangoHud, Gamescope ou GOverlay.'
fi
ok 'Stacks declarativas presentes'

printf '\n>> Validando resolução de pacotes Arch -> Chaotic -> AUR...\n'
grep -Fq 'install_selected_stack_packages' "$INSTALLER" || err 'Resolver unificado de stacks ausente'
grep -Fq 'pacman -Si "$pkg"' "$INSTALLER" || err 'Resolver não consulta pacman antes do AUR'
grep -Fq 'PACKAGE_RESOLUTION_LOG' "$INSTALLER" || err 'Log de resolução de pacotes ausente'
grep -Fq '/mnt/var/log/wolf-linux/package-resolution.log' "$INSTALLER" || err 'Log persistente de resolução ausente'
grep -Fq 'AUR fallback' "$INSTALLER" || err 'Fallback AUR não está explícito'
grep -Fq 'stage "64-resolver-stacks" install_selected_stack_packages' "$INSTALLER" || err 'Fluxo ainda não usa o resolver unificado'
if grep -Fq 'stage "64-stacks-oficiais"' "$INSTALLER" || grep -Fq 'stage "66-stacks-terceiros"' "$INSTALLER"; then
    err 'Fluxo antigo de stacks em lote ainda está ativo'
fi
ok 'Arch/Chaotic são priorizados; AUR é fallback por pacote'

printf '\n>> Validando SSH de diagnóstico na VM live...\n'
grep -Fq 'wolf-enable-ssh-live' "$CUSTOMIZER" || err 'Comando SSH live não é transportado para a ISO'
grep -Fq 'openssh' "$CUSTOMIZER" || err 'openssh ausente dos pacotes live'
grep -Fq 'ssh-keygen -A' "$PROJECT/tests/wolf-enable-ssh-live.sh" || err 'Helper SSH não garante host keys'
grep -Fq 'hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22' "$PROJECT/tests/wolf-test-iso.sh" || err 'QEMU não expõe guest:22 no host'
grep -Fq 'install -Dm0755' "$CUSTOMIZER" || err 'SSH live não é instalado diretamente em /usr/local/bin'
grep -Fq 'wolf-ssh' "$CUSTOMIZER" || err 'Alias wolf-ssh ausente'
grep -Fq 'wolf-stage-live-ssh.sh' "$PROJECT/tests/wolf-build-iso.sh" || err 'Build não faz staging SSH explícito'
grep -Fq 'wolf-linux-live-build' "$CUSTOMIZER" || err 'Marcador de versão da live ausente'
grep -Fq 'VERSION_FILE="$PROJECT/VERSION"' "$CUSTOMIZER" || err 'Customizador não lê a versão do projeto'
grep -Fq 'DEVKIT_VERSION="$(< "$SELF_DIR/VERSION")"' "$PREPARER" || err 'Preparador não lê VERSION como fonte única' 
grep -Fq 'unsquashfs -ll' "$PROJECT/tests/wolf-build-iso.sh" || err 'Build não valida SSH dentro do squashfs final'
grep -Fq 'install -m 0755' "$STAGE_SSH" || err 'Stager SSH não instala helper diretamente'
ok 'SSH live disponível manualmente para diagnóstico'

printf '\n>> Validando BIOS/UEFI...\n'
grep -Fq 'BOOT_MODE="UEFI"' "$INSTALLER" || err 'Detecção UEFI ausente'
grep -Fq 'BOOT_MODE="BIOS"' "$INSTALLER" || err 'Detecção BIOS ausente'
grep -Fq -- '--target=x86_64-efi' "$INSTALLER" || err 'grub-install UEFI ausente'
grep -Fq -- '--target=i386-pc' "$INSTALLER" || err 'grub-install BIOS ausente'
grep -Fq 'Disco onde instalar o GRUB BIOS' "$INSTALLER" || err 'Modo BIOS manual/reuso não solicita disco de boot'
ok 'Caminhos UEFI e BIOS presentes'

printf '\n>> Validando Wayland/Plasma...\n'
grep -Fq 'plasma-workspace' "$PACKAGES" || err 'plasma-workspace ausente'
grep -Fq 'plasma-desktop' "$PACKAGES" || err 'plasma-desktop ausente'
grep -Fq 'kwin' "$PACKAGES" || err 'kwin ausente'
if grep -Eq '^[[:space:]]+(plasma-meta|discover|plasma-discover)([[:space:]]|$)' "$PACKAGES"; then
    err 'Manifesto KDE puxa Discover ou plasma-meta'
fi
# Uma dependência do meta traria o Discover de volta; não aceitar.
grep -Fq 'stage "69c2-painel-sem-discover" install_wolf_plasma_panel_defaults' "$INSTALLER" || err 'Etapa de limpeza Discover ausente'
grep -Fq 'wolf-prune-discover-launchers.py' "$INSTALLER" || err 'Limpador de atalhos Discover ausente'
[[ -f "$PROJECT/tests/wolf-prune-discover-launchers.py" ]] || err 'Limpador de atalhos Discover não está no projeto' 
grep -Fq 'xdg-desktop-portal-kde' "$PACKAGES" || err 'Portal KDE ausente'
grep -Fq 'xorg-xwayland' "$PACKAGES" || err 'XWayland ausente'
if grep -Fq 'plasma-x11-session' "$PACKAGES"; then err 'plasma-x11-session não deve fazer parte da baseline'; fi
if grep -Eq 'CINNAMON_PACKAGES|XFCE_PACKAGES|MATE_PACKAGES' "$PACKAGES"; then err 'Manifesto ainda contém stacks de desktops abandonados'; fi
ok 'Plasma/Wayland limpo'

printf '\n>> Validando política de helpers...\n'
grep -Fq 'install_wolf_helper_bundle' "$INSTALLER" || err 'Bundle de helpers não é instalado'
grep -Fq 'Branding/MultiMonitor one-shot no primeiro login' "$INSTALLER" || err 'Resumo nao anuncia o primeiro login'
if grep -Eq 'install_wolf_multimonitor_all_desktops|install_wolf_desktop_branding|install_wolf_desktop_keybindings|install_xfce_defaults|install_mate_' <<< "$main_block"; then err 'main ativa automação legada de desktop'; fi
if grep -R -Eq 'Exec=.*wolf-(plasma|xfce|cinnamon|mate)' "$PROJECT"/tools 2>/dev/null; then err 'Helper contém autostart embutido inesperado'; fi
FIRST_LOGIN="$PROJECT/tools/wolf-first-login-plasma.sh"
[[ -f "$FIRST_LOGIN" ]] || err 'Script de primeiro login ausente'
bash -n "$FIRST_LOGIN" || err 'Script de primeiro login invalido'
grep -Fq '"$BRANDING" apply' "$FIRST_LOGIN" || err 'Branding nao integrado ao primeiro login'
grep -Fq '"$MULTIMONITOR" apply' "$FIRST_LOGIN" || err 'MultiMonitor nao integrado ao primeiro login'
grep -Fq 'rm -f -- "$AUTOSTART"' "$FIRST_LOGIN" || err 'Autostart nao e removido apos sucesso'
grep -Fq 'wolf-first-login-plasma.sh' "$INSTALLER" || err 'Instalador nao copia runner do primeiro login'
grep -Fq 'wolf-first-login-plasma.desktop' "$PROJECT/tests/wolf-configure-user-defaults.py" || err 'Perfil de usuario nao instala autostart unico'
bash "$PROJECT/tests/wolf-test-first-login.sh" || err 'Teste one-shot do primeiro login falhou'
ok 'Branding e MultiMonitor one-shot; outros helpers continuam manuais'

printf '
>> Validando sequência guiada de helpers...
'
grep -Fq 'wolf-helper validate' "$INSTALLER" || err 'Resumo pós-instalação não anuncia validação guiada'
grep -Fq 'wolf-validate-helpers-0.1.sh' "$INSTALLER" || err 'Instalador não instala validador guiado'
grep -Fq 'wolf-plasma-branding-0.2.sh' "$PROJECT/tools/wolf-validate-helpers-0.1.sh" || err 'Validador não testa branding 0.2'
grep -Fq 'wolf-plasma-multimonitor-0.3.sh' "$PROJECT/tools/wolf-validate-helpers-0.1.sh" || err 'Validador não testa multimonitor 0.3'
grep -Fq 'wolf-gamepad-setup-0.3.sh' "$PROJECT/tools/wolf-validate-helpers-0.1.sh" || err 'Validador não inclui gamepad'
grep -Fq 'wolf-grub-manager-0.3.sh' "$PROJECT/tools/wolf-validate-helpers-0.1.sh" || err 'Validador não inclui GRUB Manager'
grep -Fq 'PASS' "$PROJECT/tools/wolf-validate-helpers-0.1.sh" || err 'Validador não registra PASS'
grep -Fq 'SKIP' "$PROJECT/tools/wolf-validate-helpers-0.1.sh" || err 'Validador não registra SKIP'
grep -Fq 'rollback' "$PROJECT/tools/wolf-validate-helpers-0.1.sh" || err 'Validador não oferece rollback'
ok 'Validação guiada manual presente'

printf '
>> Validando branding Plasma 0.2...
'
[[ -f "$PROJECT/assets/kde/wolf-linux-kickoff.svg" ]] || err 'Ícone SVG dedicado do Kickoff ausente em assets/kde'
grep -Fq 'BreezeDark' "$PROJECT/tools/experimental/wolf-plasma-branding-0.2.sh" || err 'Branding não aplica Breeze Dark'
grep -Fq 'Papirus-Dark' "$PROJECT/tools/experimental/wolf-plasma-branding-0.2.sh" || err 'Branding não aplica Papirus-Dark'
grep -Fq 'plasma-apply-wallpaperimage' "$PROJECT/tools/experimental/wolf-plasma-branding-0.2.sh" || err 'Branding não aplica wallpaper Plasma'
grep -Fq 'wolf-linux-kickoff.svg' "$INSTALLER" || err 'Instalador não instala ícone SVG dedicado do Kickoff'
ok 'Branding Plasma 0.2 completo presente'

printf '\n>> Validando isolamento MultiMonitor / Kickoff...\n'
MULTIMONITOR="$PROJECT/tools/experimental/wolf-plasma-multimonitor-0.3.sh"
if grep -Fq 'makeKickoffWolf' "$MULTIMONITOR" || grep -Fq 'writeConfig("icon", "wolf-linux")' "$MULTIMONITOR"; then
    err 'MultiMonitor ainda altera ícones Kickoff existentes'
fi
grep -Fq 'findExistingKickoffIcon' "$MULTIMONITOR" || err 'MultiMonitor não preserva ícone existente'
grep -Fq 'kickoff.writeConfig("icon", newPanelKickoffIcon)' "$MULTIMONITOR" || err 'Novo painel não herda o Kickoff existente'
ok 'MultiMonitor preserva Kickoff existente'

printf '\n>> Validando limpeza Discover nos layouts Plasma...\n'
python - "$PROJECT/tests/wolf-prune-discover-launchers.py" <<'PYCODE' || err 'Script Python do painel inválido'
import ast
from pathlib import Path
import runpy
import sys
path = Path(sys.argv[1])
ast.parse(path.read_text(encoding='utf-8'))
prune = runpy.run_path(str(path))['prune_layout']
samples = {
    'var launcherUrls = ["applications:org.kde.dolphin.desktop", "applications:org.kde.discover.desktop", "applications:org.kde.konsole.desktop"];':
        'var launcherUrls = ["applications:org.kde.dolphin.desktop", "applications:org.kde.konsole.desktop"];',
    'task.writeConfig("launchers", ["applications:org.kde.discover.desktop", "applications:org.kde.dolphin.desktop"]);':
        'task.writeConfig("launchers", ["applications:org.kde.dolphin.desktop"]);',
}
for before, after in samples.items():
    assert prune(before) == after, 'Pruner não removeu Discover corretamente'
PYCODE
ok 'Limpador Discover presente e com sintaxe válida' 

printf '
>> Validando gerenciamento seguro da VM...
'
grep -Fq -- '--installed' "$PROJECT/tests/wolf-test-iso.sh" || err 'wolf-test-iso não possui modo --installed'
grep -Fq 'installed|start)' "$PROJECT/tests/wolf-vm.sh" || err 'wolf-vm não possui start/installed'
grep -Fq 'fresh)' "$PROJECT/tests/wolf-vm.sh" || err 'wolf-vm não possui fresh explícito'
grep -Fq 'INSTALLED_ONLY' "$PROJECT/tests/wolf-test-iso.sh" || err 'Modo instalado não está separado da ISO'
grep -Fq 'CONFIRM_FRESH' "$PROJECT/tests/wolf-run-arch-test.sh" || err 'wolf-run-arch-test ainda pode apagar VM sem confirmação explícita'
ok 'VM pode iniciar disco instalado sem --fresh'


printf '\n>> Validando perfil pessoal KDE alpha13...\n'
DEFAULTS="$PROJECT/tests/wolf-configure-user-defaults.py"
[[ -f "$DEFAULTS" ]] || err 'Gerador one-shot de preferencias ausente'
python -m py_compile "$DEFAULTS" || err 'Gerador Python invalido'
python "$PROJECT/tests/wolf-test-user-defaults.py" || err "Testes de preferências KDE falharam"
grep -Fq 'stage "69c3-preferencias-kde" install_wolf_kde_personal_defaults' "$INSTALLER" || err 'Perfil pessoal nao chamado no fluxo principal'
grep -Fq 'wolf-configure-user-defaults.py' "$CUSTOMIZER" || err 'Gerador nao transportado para live'
for rel in zsh/zshrc zsh/p10k.zsh zsh/fastfetch.jsonc zsh/fastfetch-wolf-linux.txt zsh/fastfetch-wolf-linux-ascii.txt kde/wolf-open-vscode.desktop; do
    [[ -f "$PROJECT/assets/$rel" ]] || err "Asset perfil alpha13 ausente: $rel"
done
# O pacote kate já contém o binário/desktop entry do KWrite no Arch.
# Rejeite apenas a entrada de pacote kwrite, preservando kwrited.
grep -Eq '^[[:space:]]+dolphin[[:space:]]+konsole[[:space:]]+kate([[:space:]]|$)' "$PACKAGES" || err 'Kate não declarado no manifesto KDE'
if grep -Eq '^[[:space:]]+kwrite([[:space:]]|$)|[[:space:]]kwrite[[:space:]]' "$PACKAGES"; then
    err 'kwrite não deve constar como pacote separado: já é fornecido por kate'
fi
grep -Fq 'org.kde.kwrite.desktop' "$DEFAULTS" || err 'Associação MIME KWrite deve continuar disponível via kate'
grep -Fq 'mpc-qt' "$PACKAGES" || err 'MPC-QT nao declarado'
if grep -Fq 'smplayer' "$PACKAGES"; then err 'SMPlayer reintroduzido ao projeto'; fi
ok 'KWin, mouse, MIME, Dolphin, Zsh, Konsole e assets alpha13 declarados'

printf '\n>> Validando ausência de polling agressivo nos helpers ativos...\n'
if grep -R -nE 'while[[:space:]]+(:|true).*sleep|sleep[[:space:]]+[0-9]+.*xrandr|xrandr.*sleep[[:space:]]+[0-9]+' "$PROJECT/tools" --include='*.sh' 2>/dev/null; then
    err 'Padrão de polling agressivo encontrado em tools/'
else
    ok 'Nenhum polling agressivo óbvio em tools/'
fi

printf '\n>> Validando perfil ISO...\n'
if [[ -d "$PROJECT/iso-profile" ]]; then
    WOLF_PROJECT="$PROJECT" "$CUSTOMIZER" || err 'Customização do perfil ISO falhou'
    [[ -x "$PROJECT/iso-profile/airootfs/usr/local/bin/wolf-enable-ssh-live" ]] || err 'wolf-enable-ssh-live ausente do airootfs após customização'
    [[ -L "$PROJECT/iso-profile/airootfs/usr/local/bin/wolf-ssh" ]] || err 'wolf-ssh ausente do airootfs após customização'
    v="$(< "$PROJECT/VERSION")"
    printf 'Wolf Linux %s KDE/Wayland Clean Baseline\n' "$v" | cmp -s - "$PROJECT/iso-profile/airootfs/etc/wolf-linux-live-build" || err 'Versão inconsistente na live'
    cmp -s "$PROJECT/VERSION" "$PROJECT/iso-profile/airootfs/root/wolf-linux/VERSION" || err 'VERSION não foi integrado à live'
    cmp -s "$PROJECT/assets/kde/wolf-linux-kickoff.svg" "$PROJECT/iso-profile/airootfs/root/wolf-linux/assets/kde/wolf-linux-kickoff.svg" || err 'Ícone SVG do Kickoff divergente no staging da ISO'
    cmp -s "$PROJECT/tests/wolf-prune-discover-launchers.py" "$PROJECT/iso-profile/airootfs/root/wolf-linux/tests/wolf-prune-discover-launchers.py" || err 'Limpador Discover ausente ou divergente no staging da ISO' 
else
    printf '[AVISO] iso-profile não existe; pulando validação de customização real.\n'
fi

printf '\n>> Validando SSH live e pós-build SquashFS sem falso negativo...\n'
BUILD_ISO="$PROJECT/tests/wolf-build-iso.sh"
if grep -Eq 'unsquashfs .*\|[[:space:]]*grep[[:space:]]+-[^[:space:]]*q' "$BUILD_ISO"; then
    err 'wolf-build-iso.sh ainda usa grep -q após unsquashfs sob pipefail.'
else
    ok 'validação SquashFS deixa unsquashfs concluir normalmente'
fi

if (( ERRORS )); then
    printf '\n[ERRO] Há itens a corrigir antes do teste em VM.\n'
    exit 1
fi
printf '\n[OK] Testes rápidos concluídos.\n'
