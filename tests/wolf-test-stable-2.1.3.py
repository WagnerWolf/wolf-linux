#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).resolve().parents[1]
v=(r/'VERSION').read_text().strip()
assert v=='2.1.3', v
for path, expected in (
 ('install/wolf-install.sh', 'WOLF_VERSION="2.1.3"'),
 ('install/wolf-install.sh', 'VERSION_ID="2.1.3"'),
 ('tests/wolf-customize-iso-profile.sh', 'VERSION_ID="2.1.3"'),
 ('preparar_ambiente_wolf_linux.sh','RELEASE-NOTES-2.1.3.md'),
):
    assert expected in (r/path).read_text(),(path,expected)
assert (r/'RELEASE-NOTES-2.1.3.md').is_file()
assert not (r/'gerar-iso-2.1.3-rc5.sh').exists()
# Dois layouts legítimos:
# 1. DevKit distribuído: contém o script de preparação/geração e branding-assets.
# 2. Projeto preparado pelo Archiso: contém iso-profile e assets, MAS NÃO
#    contém o gerador de alto nível nem branding-assets (que foi copiado a assets).
branding = r/'branding-assets/zsh/zshrc'
profile = r/'assets/zsh/zshrc'
assert profile.is_file(), 'Perfil Zsh efetivamente instalado ausente'
if (r/'branding-assets').is_dir():
    wrapper = r/'gerar-iso-2.1.3.sh'
    assert wrapper.is_file(), 'Script gerar ISO ausente no DevKit de distribuição'
    assert 'wolf-linux-2.1.3' in wrapper.read_text(), 'Script de geração aponta para outro projeto'
    assert branding.is_file() and profile.read_bytes() == branding.read_bytes(), 'Arquivos Zsh divergentes'
    layout='DevKit distribuído'
else:
    assert (r/'tests/wolf-build-iso.sh').is_file(), 'Gerador do projeto preparado ausente'
    assert 'mkarchiso' in (r/'tests/wolf-build-iso.sh').read_text(), 'Gerador Archiso inválido'
    assert 'cp -a "$SELF_DIR/branding-assets/." "$PROJECT/assets/"' in (r/'preparar_ambiente_wolf_linux.sh').read_text(), 'Origem dos assets não está documentada no preparador'
    layout='projeto preparado'
assert 'if [[ -r /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]]; then' in profile.read_text(), 'Fallback Zsh ausente'
print(f'[OK] Promoção 2.1.3: versão/instalador/Live/build/notas e Zsh consistentes ({layout})')
