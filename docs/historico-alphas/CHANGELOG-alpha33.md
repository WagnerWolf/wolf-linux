# Wolf Linux DevKit 2.0.0-alpha33

## Melhorias
- Instalação automática /home integrada ou em partição dedicada (UEFI/BIOS), tamanhos de raiz e home configuráveis em GiB. Zero representa o espaço restante; caso ambas tenham tamanhos fixos, o saldo permanecerá não particionado.
- ESP nova sempre FAT32/1 GiB em UEFI. BIOS/MBR sem partição EFI; sinalização visual em vermelho.
- Reutilização da home em BIOS/MBR: corrigida checagem residual Bash que exigia UEFI indevidamente.
- Validador JSON v4 com campos erase_sizes (`root_gib`, `home_gib`), exportação 19 campos, dupla verificação de tamanho/layout e rejeição de incompatibilidades.
- Novo teste alpha33 com dispositivos fictícios, validação canônica e comandos sgdisk/parted integralmente simulados; sem acesso real a discos.

## Limites
- Execução experimental exclusivamente em QEMU/KVM com disco VirtIO descartável; ainda sem teste real nesta revisão.
- BIOS/GPT com bios_grub, multidiscos e LVM no destino continuam sem suporte da GUI. Preservar a alpha32/31 como versões já testadas.
