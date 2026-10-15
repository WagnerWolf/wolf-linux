# Wolf Linux 2.0.0-alpha37 — Chromium, Bluetooth e Wolf Rescue 0.1

- Alteração da Live: Firefox sai da ISO; Chromium, BlueZ, BlueZ-utils, Blueman e rfkill entram na ISO (sem interferir nos pacotes do KDE instalado).
- Openbox com entrada Bluetooth e Wolf Rescue; bandeja ampliada para ícones Wi-Fi e Bluetooth.
- Chromium é iniciado sem root e sem flags que desabilitem sandbox.
- Wolf Rescue 0.1: relatórios de armazenamento/boot em modo somente leitura, com GUI para visualizar e copiar texto.
- `efibootmgr -v` somente leitura em UEFI; `pvs/vgs/lvs --readonly`; sem montagem, chroot ou operações de reparo.
- Diagnóstico físico permite confirmar inventário dos dois NVMe e de vg_monstro; não assume automaticamente que lv_projetos é /home.
- Instalação gráfica em SSD real, EFI multidisco e LVM ainda bloqueada, até validação específica.
- Nenhuma modificação no backend destrutivo e nas stacks KDE já homologadas.
- Wolf Rescue permite visualizar explicitamente um `etc/fstab` selecionado de uma raiz já montada, sem montar ou modificar nada. Guia em `docs/WOLF-HARDWARE-PREFLIGHT.md`.
