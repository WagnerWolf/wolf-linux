# Wolf Linux DevKit 2.0.0-alpha15

- Mantém a alpha14 aprovada na VM e a seleção de pacotes (Kate/KWrite resolvidos).
- Integra um autostart **somente do usuário instalado**, que aplica Branding 0.2 e MultiMonitor 0.3.1 na primeira sessão KDE Plasma pronta.
- Uma execução com sucesso gera log e marcador, remove o próprio atalho e não fica residente.
- Se a sessão não ficar pronta ou um helper falhar, registra erro e tenta novamente no próximo login.
- Gamepad e GRUB Manager continuam manuais; não há watcher permanente.
- Não altera layout de disco, arquitetura BIOS/UEFI ou política Arch → Chaotic-AUR → AUR.
