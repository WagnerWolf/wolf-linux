# Wolf Linux DevKit 2.0.0-alpha58

- Interface: teclado inicial sem botão Revisar no rodapé, aviso amarelo comprimido removido.
- Instalador clássico retirado dos atalhos e do staging da Live (código legado guardado no DevKit).
- Estimativa informativa de espaço por perfil/stack, alerta quando a raiz é menor que a referência.
- Vulkan: instalar o provedor apropriado para a GPU **antes** das stacks de jogos, evitando seleção automática de NVIDIA em VirtIO.
- UEFI: fallback GRUB criado em ESP nova ou quando ainda não existe, sem sobrescrever fallback de ESP preservada; validação exata do executável EFI WolfLinux e da montagem da ESP; saída detalhada para diagnóstico de BootOrder.

**Importante:** As mudanças UEFI não provam a causa do problema relatado. Revalidar boot pela VM e recolher efibootmgr/arquivos EFI caso persista. Não utilizar a nova rota física de instalação com dados importantes até essa validação.
- Diagnóstico de boot UEFI somente leitura na Live: `sudo wolf-boot-diagnose /dev/ESP`.
