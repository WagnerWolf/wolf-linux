# Wolf Linux DevKit 2.0.0-alpha17 — acabamento final

- Preparador instala/verifica `archiso` antes de inspecionar `releng`; valida perfil ANTES de remover projeto anterior.
- `--skip-deps` falha com diagnóstico claro quando o perfil `releng` não existe.
- Kate é o editor padrão para texto simples, Markdown, JSON, XML, logs e código-fonte; nenhum pacote `kwrite` separado.
- Gwenview instalado em todos os perfis KDE, com `kimageformats` e `qt6-imageformats`; associações MIME explícitas para PNG, JPEG, WebP, GIF, SVG, BMP, TIFF e formatos adicionais.
- Zsh autosuggestions: `fg=250` ao final do `.zshrc`, conforme validado no Konsole físico.
- Wolf Control Center 0.1.1: páginas roláveis, botões em coluna, diagnósticos Octopi/Zsh mais completos, opção de desativar autostart do Octopi.
- Não altera as políticas aprovadas de Plasma, Multimonitor, primeiro login, Gamepad ou GRUB.
