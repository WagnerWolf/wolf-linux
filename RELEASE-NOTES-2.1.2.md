# Wolf Linux 2.1.2 — Release (16/10/2026)

Base homologada em VM: 2.1.2-rc1 SmokeFix2, instalação Basic bem-sucedida informada pelo usuário.

- Novo perfil Basic (LibreOffice, Chrome, PDF e multimídia) sem gaming/dev; perfis Minimal, Test e Full preservados.
- Corrigida a visualização dos nomes das ferramentas auxiliares na Live.
- Preparação de cache do usuário no fallback yay: evita ~/.cache criado como root e não faz chown recursivo do home.
- Corrigida contaminação da lista de pacotes AUR por mensagens do tratamento de erro na etapa 64-resolver-stacks.
- Wolf Package Manager 0.3.3 corrige barras de progresso PTY (CR/ANSI) em seu terminal integrado.
- Mantidos os overrides específicos do Baloo, instalador multidisco/LVM e mecanismos de boot do 2.1.1.

**Kernel:** sem mudanças nesta release. Linux LTS permanece a alternativa de recuperação; falha de boot do Zen relatada em 16/10 ainda requer diagnóstico. Não é atribuída conclusivamente ao kernel ou DKMS. Não adicionar CachyOS ou remover LTS sem investigação.

Validação: testes unitários e smoke test do DevKit neste ambiente; Qt real e ISO gerada devem ser conferidos em Arch/VM. A falha esporádica de task manager multi-monitor com Plasma 6.8.0 depende de correção do Plasma; não foi introduzido workaround global.
