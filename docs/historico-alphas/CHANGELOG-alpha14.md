# Wolf Linux DevKit 2.0.0-alpha14

## Correção de empacotamento do KDE

- Retira `kwrite` da lista `KDE_PACKAGES`: `kate` já fornece o programa e desktop entry do KWrite no Arch Linux.
- Mantém KWrite como aplicação padrão de textos simples, Markdown, logs e JSON, para proteger contra associações do LibreOffice.
- Smoke test verifica `kate` e recusa a entrada de pacote `kwrite`.
- Preserva todo o restante da alpha13, inclusive KDE/Wayland, SSH, SVG do Kickoff, terminal e demais helpers.
