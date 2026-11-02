# Wolf Linux 2.2.0-rc1 — Patch 1 (candidato de teste)

- Corrigida falha determinística na etapa `61-identidade-wolf`: o arquivo anunciava 2.2 RC1, mas era verificado contra 2.1. Agora valida `PRETTY_NAME`, `VERSION_ID` e `ID`.
- Textos KDE antigos substituídos por LXQt na seleção de perfis, estimativas de espaço, ajuda do instalador e ensaio físico. Nomes KDE mantidos quando se referem a aplicativos/bibliotecas realmente usados.
- `wolf-chrome-diagnose`: diagnóstico local de versão, sessão, logs, coredumps e relatórios Crashpad, sem alterar flags ou dados do perfil Chrome.
- Ampliado teste de regressão para identidade e interface.

## Escopo

O patch ainda **não foi testado em instalação real**, apenas em verificações estáticas. A versão base e o nome do gerador de ISO foram preservados, pois isto é um patch da RC1, não uma nova RC oficial.
