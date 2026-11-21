# Wolf Linux 2.3.1 Release — KDE Plasma / Wayland

**Versão:** 2.3.1 (release estável, sem Preview ou RC).  
**Base:** Wolf Linux 2.3.0 Stable — Refinos 3, aprovada em máquina virtual pelo usuário.  
**Ambiente instalado:** KDE Plasma / Wayland, SDDM (tela de login X11), Dolphin.  
**Live:** Openbox/X11 com Wolf Installer gráfico.

## Alterações em relação à 2.3.0

- **Wolf Package Manager 1.0.0**: interface Wolf, atualização oficial pelo Pacman, verificação de integridade e etapa AUR via **yay** com confirmação própria; sem bloqueio legado de `libfm-qt` no KDE.
- **Wolf Subtitle Downloader**: integração com menu de contexto do Dolphin para vídeos, busca e download de legendas PT-BR, login OpenSubtitles.com pelo chaveiro Secret Service. O ambiente isolado Python/Subliminal é oferecido no primeiro uso do usuário, não é pré-executado no build.
- Preservados os refinamentos já testados: NVIDIA para dois monitores, mouse plano, atalhos de áreas virtuais desativados, Thorium AVX2, VS Code no Dolphin, formatação de USB no widget do Plasma e Tux no TTY.
- Mantido o **Wolf Sem Suspensão** como utilitário *opcional*: só modifica energia/bloqueio quando o usuário escolhe executar.

## Gerar a ISO

No Arch Linux, **como usuário normal**, dentro do DevKit extraído:

```bash
./preparar_ambiente_wolf_linux.sh
./gerar-iso.sh
```

Também é possível chamar somente `./gerar-iso.sh`: ele prepara o projeto se ainda não existir.

- Projeto padrão: `~/wolf-linux-2.3.1`
- Saída padrão: `~/wolf-linux-2.3.1/out/`
- Para retomar apenas um staging 2.3.1 interrompido: `./preparar_ambiente_wolf_linux.sh --resume --skip-deps`.
- Para usar outro projeto, informe `--project CAMINHO` nos dois scripts.
- **Não use `--resume` para reutilizar um projeto 2.3.0:** o instalador, a identidade e os testes foram atualizados para 2.3.1; o preparador verifica a versão e rejeita projetos incompatíveis.

## Validação

O usuário confirmou funcionamento do Refinos 3 em VM; o Package Manager 1.0.0 e o Subtitle Downloader já haviam sido aprovados em instalação física. A mudança de versão foi conferida em testes estáticos e staging simulado. **A ISO 2.3.1 produzida deste DevKit não foi construída ou testada aqui.**

Antes de instalar em hardware, confira o dispositivo de destino, ESP/UUIDs e as opções do Wolf Installer. O instalador exige AVX2 nos perfis que incluem Thorium. Consulte `RELEASE-NOTES-2.3.1.md` para os testes sugeridos e o escopo completo.

O único gerador público de ISO na raiz é `gerar-iso.sh`. Os documentos anteriores permanecem apenas como histórico.
