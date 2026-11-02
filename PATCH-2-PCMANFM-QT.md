# Wolf Linux 2.2.0-rc1 — Patch 2 (PCManFM-Qt)

- Base: Patch 1 (incluindo correção da identidade Wolf Linux e diagnóstico Chrome).
- Adicionados GVfs/MTP e UDisks2 LVM2 à base LXQt para montagem de volumes no explorador.
- Removido o pacote Dolphin do manifesto LXQt e também do manifesto KDE histórico; mantidos Kate, Konsole, Okular, Spectacle e Gwenview.
- PCManFM-Qt (`pcmanfm-qt.desktop`) é o gerenciador de arquivos para pastas no LXQt, em `mimeapps.list`, `lxqt-mimeapps.list` e `lxqt/session.conf`.
- Atalhos Super+E (Openbox) e Ctrl+Alt+E (LXQt); quicklaunch do painel agora usa PCManFM-Qt.
- Wolf Control Center (auditoria e reaplicação MIME) e verificador pós-pacstrap alinhados.
- Ação 'Abrir pasta no Visual Studio Code' feita para PCManFM-Qt em `~/.local/share/file-manager/actions/wolf-open-vscode.desktop`, somente quando o VS Code estiver instalado. Não usa serviço KIO. Somente a ação personalizada gerada pelo Wolf é removida quando reconhecida, após backup.
- Reinstalação com /home preservada: configurações são arquivadas pelo configurador antes da atualização; ação Wolf KIO legada reconhecida é retirada com backup, sem apagar configurações genéricas do usuário.
- Na sessão LXQt em uso, configure a migração em uma sessão encerrada/TTY: `python3 /usr/local/lib/wolf-linux/lxqt/configurar.py --telas 2 --wallpaper /usr/share/backgrounds/wolf-linux/wallpaper.png`. Não reiniciar PCManFM nem painel no meio da sessão.
- Smoke estático não substitui boot e instalação reais. Não foi gerada ISO neste ambiente.
