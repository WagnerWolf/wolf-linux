# Wolf Linux DevKit 2.0.0-alpha19 — Live GUI experimental

- Base instalada preservada a partir da alpha18, sem mudanças no motor de instalação.
- Ambiente live separado: Xorg + Openbox, QTerminal, PCManFM-Qt, GParted, PySide6 e wallpaper Wolf.
- Usuário efêmero `wolf` (sessão gráfica não-root), criado antes do autologin tty1.
- Demonstração Wolf Live Installer 0.1 com diagnóstico e atalhos de manutenção.
- Nenhuma opção gráfica de instalação ou reparação destrutiva habilitada nesta etapa.
- Fallback a terminal se o Xorg falhar ou usando `wolf.nogui=1`.
- Testes de integridade de staging, sintaxe e repetição.
- Compatibilidade NVIDIA deve ser comprovada separadamente no boot físico; nenhuma promessa de suporte universal Nouveau.
