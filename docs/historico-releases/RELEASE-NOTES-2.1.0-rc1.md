# Wolf Linux 2.1.0-rc1 — Prévia de integração do Package Manager

- Inclui **Wolf Package Manager 0.3.1** com consulta dos repositórios/AUR, busca de comandos, atualização ordenada, terminal integrado, tray e autostart KDE.
- Substitui o Octopi na stack Extras e no Wolf Control Center.
- Pacman-contrib/checkupdates e util-linux/script são dependências da base; o instalador garante yay no sistema ou registra ausência opcional.
- Instalado para todas as contas em `/usr/local/lib/wolf-linux/package-manager`, com launcher `/usr/local/bin/wolf-package-manager`.
- O monitor do tray **não instala atualizações sem aprovação explícita** do usuário.
- Não foram alteradas as operações de particionamento, montagem e GRUB da base 2.0.0.
- É uma **release candidate ainda sem homologação de ISO/instalação física**. Testar em VM antes de promover a versão final.
