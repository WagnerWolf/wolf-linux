# Wolf Linux 2.3.1 — Release

**Data da promoção:** 20/11/2026  
**Canal:** Release estável  
**Base técnica:** Wolf Linux 2.3.0 Stable / Refinos 3

## Destaques

- Wolf Package Manager **1.0.0**: interface Wolf; `pacman -Syu` e auditoria pós-atualização; atualização AUR pelo `yay`, mediante confirmação separada. Removida a dependência incorreta da libfm-qt customizada na instalação KDE.
- Wolf Subtitle Downloader no KDE/Dolphin: menu para vídeo local, busca OpenSubtitles.com/Podnapisi e credenciais do Secret Service, com ambiente Python isolado configurável após instalação.
- Preservado Thorium AVX2, proteção NVIDIA `opportunistic_flip_sync=0` no perfil relevante, mouse sem aceleração, uma única área de trabalho virtual e atalhos de troca de desktop liberados; o SDDM continua usando X11.
- Utilitário para desativar suspensão e ajustar a tela de bloqueio continua **opcional**.

## Motivo da promoção

O usuário confirmou a validação da revisão anterior na VM e aprovou fisicamente os dois aplicativos. Esta revisão formaliza a versão 2.3.1 em `VERSION`, instalador, Live e comandos de build. Não há uma etapa Preview/RC adicional.

## Homologação e limites

- Pacote de origem: sintaxe, verificações estáticas, staging do Package Manager e Subtitle Downloader, coerência de versão e integridade do ZIP.
- A nova ISO desta revisão **ainda não foi gerada nem validada em uma instalação limpa**. A promoção reflete a homologação pelo usuário da base funcional em VM, não uma execução real de mkarchiso neste ambiente.

## Construção

```bash
./preparar_ambiente_wolf_linux.sh
./gerar-iso.sh
```

Projeto default: `~/wolf-linux-2.3.1`. A versão 2.3.0 continua arquivada e não será sobrescrita.
