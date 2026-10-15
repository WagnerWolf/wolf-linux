# Wolf Live GUI 0.1 (alpha19)

O Openbox/Xorg e a GUI PySide6 pertencem **somente à live**.
O sistema instalado continua KDE Plasma/Wayland, exatamente como na alpha18.

## Primeiro boot
- `wolf` é um usuário temporário criado em RAM antes do getty de tty1.
- O tty1 entra automaticamente e executa Xorg/Openbox (sem display manager).
- Se Xorg falhar, o login mantém terminal e permite `sudo wolf-install`.
- Para iniciar sem gráficos adicione `wolf.nogui=1` à linha de boot (editor GRUB/bootloader).
- Terminais secundários: `Ctrl+Alt+F2`; login/senha precisam ser tratados conforme o ambiente Archiso.
- Clique direito no desktop abre menu Openbox; `Ctrl+Alt+T` abre QTerminal.

## Segurança e escopo
- O instalador visual é **somente demonstração**: não particiona nem instala.
- GParted é explicitamente privilegiado: só realiza alterações após escolhas e confirmações próprias.
- A live é um sistema de recuperação físico; o usuário temporário possui sudo sem senha, como
  o terminal root da mídia Archiso. Não habilite serviços de rede remotos desnecessariamente.
- O instalador CLI foi preservado para uso e diagnóstico, não integrado ainda com a GUI.
- Nesta fase, reparação GRUB/chroot guiada é apenas uma proposta; não executada.
- Não há garantia de aceleração ou suporte completo de todas as placas NVIDIA.

## Testar
- Preparar e compilar ISO normalmente; iniciar na VM via tests/wolf-vm.sh live uefi.
- Verificar tela Openbox, wallpaper, janela Wolf, QTerminal, PCManFM-Qt, GParted, internet, tty CLI.
- `sudo wolf-install --help` no terminal deve continuar funcionando.
- No hospedeiro `./tests/wolf-test-live-desktop.sh` testa staging sem bootar a ISO.

## Alpha38 — Ajustes de usabilidade

O Wolf Installer GUI 1.8 passou a dimensionar a janela à área de trabalho, usar botões menores e limitar rolagem à vertical. O Wolf Rescue 0.2 possui tema escuro e mapa `/`, EFI e `/home` a partir do `fstab` escolhido, sem modificações em disco. A execução física continua bloqueada.
