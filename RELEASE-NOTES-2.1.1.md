# Wolf Linux 2.1.1 — Notas de lançamento

**Data:** 15 de outubro de 2026 · **Estado:** versão estável do DevKit.

## Destaques

- Fluxos de instalação Apagar disco, Manual e Reutilizar partições mantidos.
- Suporte a raiz e ESP em discos diferentes e `/home` ext4 em LVM com múltiplos PVs preservados. Homologado em hardware real pelo mantenedor na linha RC1/RC2.
- Terminal integrado exibe progresso do `pacman` corretamente, inclusive `\r`.
- Baloo: override systemd user global para executar extrator Qt em modo offscreen, isolado ao serviço `kde-baloo.service`, confirmado sem novos crashes após reboot.
- Wolf Package Manager 0.3.2 inclui melhoria de consistência em consultas de atualização.

## Compatibilidade e segurança

O modo de reutilização preserva a EFI e o LVM segundo o plano de instalação;
se a limpeza de dotfiles for marcada, os diretórios ocultos do usuário serão
removidos conforme a prévia. Faça backup dos dados relevantes.

A proteção do Baloo não modifica a configuração global do Qt/Wayland.
Não foram alteradas as rotinas homologadas de particionamento ou boot.

## Build e homologação

```bash
./preparar_ambiente_wolf_linux.sh
bash tests/wolf-smoke-test.sh
bash tests/wolf-build-iso.sh
```

A geração final da ISO precisa de Arch Linux, `archiso` e permissões de build.
O pacote do DevKit **não** é uma ISO inicializável.
