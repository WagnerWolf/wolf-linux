#!/usr/bin/env python3
"""Non-destructive regression: optional Powerlevel10k must not block installation."""
from pathlib import Path
import re
import subprocess

root=Path(__file__).resolve().parents[1]
installer=(root/'install/wolf-install.sh').read_text()
# O preparador copia branding-assets -> assets. No projeto compilável,
# branding-assets não existe; validamos sempre assets (destino efetivo).
profile=(root/'assets/zsh/zshrc').read_text()
source=root/'branding-assets/zsh/zshrc'
if source.is_file():
    assert source.read_text() == profile, 'Zsh divergiu entre branding-assets e assets'
preparer=(root/'preparar_ambiente_wolf_linux.sh').read_text()
assert 'cp -a "$SELF_DIR/branding-assets/." "$PROJECT/assets/"' in preparer
assert 'zsh-theme-powerlevel10k' in (root/'package-profiles/packages.conf').read_text()
func=installer.split('install_wolf_kde_personal_defaults() {',1)[1].split('install_terminal_defaults() {',1)[0]
assert 'if [[ ! -f /mnt/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then' in func
assert 'Powerlevel10k indisponível; Zsh utilizará prompt de contingência.' in func
assert 'wolf-optional-failures.log' in func
assert not re.search(r'die[^\n]*Powerlevel10k|Powerlevel10k[^\n]*die', func)
assert 'if [[ -r /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then' in profile
assert '    source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme' in profile
assert 'PROMPT=' in profile and 'RPROMPT=' in profile
assert profile.count('[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh')==1
assert profile.index('[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh') < profile.index('else\n    # Prompt legível no Konsole')
legacy=installer.split('install_oh_my_zsh_and_profile() {',1)[1].split('install_wolf_kde_personal_defaults() {',1)[0]
assert 'die "Não localizei powerlevel10k.zsh-theme' not in legacy
assert 'if [[ -n "$p10k_theme" && -r "$p10k_theme" ]]; then' in legacy
assert re.fullmatch(r'2\.1\.3(?:-rc[1-9]\d*)?', (root/'VERSION').read_text().strip())
# Tests that install user defaults still copies guarded .zshrc
result=subprocess.run(['python3',str(root/'tests/wolf-test-user-defaults.py')],capture_output=True,text=True,timeout=30)
assert result.returncode == 0, result.stderr
print('[OK] Powerlevel10k ausente não gera die; ~/.zshrc usa fallback e mantém Zsh/plug-ins.')
