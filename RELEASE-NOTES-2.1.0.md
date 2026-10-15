# Wolf Linux 2.1.0 — Lançamento estável

**Data:** 15 de outubro de 2026  
**Base:** Wolf Linux DevKit 2.0.0 estável e 2.1.0-rc1 validada pelo mantenedor.

## O que há de novo

- **Wolf Package Manager 0.3.1** substitui o Octopi como gerenciador gráfico padrão.
- Pesquisa de pacotes em repositórios e AUR com `yay`; busca adicional por comandos usando o índice de arquivos do `pacman`.
- Pesquisa paralela por origem com cache temporário, seleção múltipla e instalação por etapas.
- Atualizações manuais em sequência: repositórios via `pacman`, depois pacotes AUR via `yay`; terminal PTY integrado, diálogo de senha e diagnóstico de transações.
- Ícone do lobo na bandeja KDE; inicialização minimizada, verificação periódica de atualizações (padrão: 2 horas, configurável). A verificação não instala nada automaticamente.
- Disponível nos perfis **Minimal, Test e Full**, instalado para todas as contas em `/usr/local/lib/wolf-linux/package-manager` e acionado por `wolf-package-manager`.
- Integração com o Wolf Control Center, substituindo os controles do Octopi.

## Instalador

O instalador gráfico continua oferecendo **Apagar disco inteiro**, **Particionamento manual** e **Reutilizar partições existentes**, em BIOS/Legacy e UEFI. A seleção de teclado, o perfil obrigatório, as duas confirmações e o terminal integrado permanecem os mesmos do lançamento 2.0.0. Não foram introduzidas mudanças funcionais nas rotinas de particionamento, formatação, GRUB ou detecção de GPU nesta promoção.

## Validação

O mantenedor confirmou funcionamento da prévia 2.1.0-rc1. Esta promoção ajusta a identificação, documentação e testes da versão para **2.1.0**. A ISO final deve ser gerada a partir deste DevKit e verificada antes da reinstalação física planejada.

## Antes de reinstalar

- Faça cópia externa dos dados insubstituíveis e de chaves/credenciais necessários.
- Revise o dispositivo de destino e os pontos de montagem antes de confirmar operações irreversíveis.
- No perfil Full, reserve espaço suficiente para Flutter, SDKs, cache de pacotes e futuras atualizações.
- O gerenciador de pacotes consulta novas versões; não inicia atualizações automaticamente.

A versão 2.0.0 permanece como referência de recuperação. Histórico da prévia em `docs/historico-releases/RELEASE-NOTES-2.1.0-rc1.md`.
