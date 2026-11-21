# Wolf Linux 2.3.0 — Refinos 3: Package Manager 1.0.0 e Subtitle Downloader

Base: Wolf Linux 2.3.0 Stable — Refinos 2 (suspensão opcional).
O restante do KDE, NVIDIA, atalhos, Thorium, VS Code, USB e SDDM permanece inalterado.

## Novos componentes

- **Wolf Package Manager 1.0.0**, instalado globalmente em `/usr/local/lib/wolf-linux/package-manager`.
  Preserva os ícones, autostart no Plasma e interface Wolf. Atualização oficial com pacman,
  verificações de integridade e etapa AUR separada com confirmação, usando **yay**.
  No KDE, não depende mais de `libfm-qt` personalizada.
- **Wolf Subtitle Downloader 0.3-preview3**, com dois menus específicos para vídeos no Dolphin:
  "Buscar legendas..." e "Baixar melhor legenda PT-BR". Busca Podnapisi/OpenSubtitles.com,
  conserva as credenciais no Secret Service do usuário. Não há credenciais na ISO.

## Dependências do Subtitle Downloader

O aplicativo e os menus do Dolphin estarão presentes desde o primeiro login em todos os perfis.
No primeiro uso por uma conta nova, aparece uma confirmação para **preparar o ambiente
Python isolado** (`~/.local/share/wolf-subtitle-downloader/.venv`) e baixar `subliminal==2.8.0`
do PyPI. **O primeiro uso exige internet**, como no instalador que foi aprovado na máquina
anterior. Essa instalação ocorre como usuário comum, nunca como root, e as credenciais são
preservadas. Depois da preparação, abra novamente a ação desejada no Dolphin.
Alternativamente: `wolf-subtitle-downloader-setup` pelo Konsole.

Um `/home` que já contenha a instalação aprovada continuará usando-a.

## Preparar a ISO

```bash
./preparar_ambiente_wolf_linux.sh
./gerar-iso.sh
```

Novo projeto independente: `~/wolf-linux-2.3.0-refinos3-aplicativos`.
Não reutilize a pasta de build dos Refinos 2; os fontes do instalador mudaram.

## Validação

Testes estáticos e mocks não substituem a compilação Archiso e o teste de instalação limpa.
Verifique o Package Manager 1.0.0, o autostart, os menus do Dolphin, o acesso ao chaveiro
e a instalação inicial das dependências de legendas com internet na nova máquina.
