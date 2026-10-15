# Wolf Linux DevKit 2.0.0-alpha56

## Interface gráfica
- Layout do teclado BR ABNT2 aplicado automaticamente no início, sem retirar o seletor.
- Escolha explícita e obrigatória do perfil Minimal, Test ou Full; sem padrão.
- Particionamento manual: GParted no topo; atualização automática do inventário ao fechar o programa.
- Reutilização: prévia somente leitura dos dotfiles imediatamente em `/home/USUARIO` da partição ext4 selecionada. O mesmo usuário é utilizado na limpeza autorizada pela nova GUI. Backup opcional ainda indisponível neste executor.
- Removidos textos públicos de laboratório e limitação a VM.

## Execução
- Nova GUI: contrato único usado pela Live tanto em ambiente virtual quanto físico; validação privilegiada e revalidação imediata antes de operações reais. Aceita discos SATA, NVMe, eMMC, VirtIO. Discos USB, removíveis, montados ou com volumes gerenciados LVM/RAID/LUKS associados não são aceitos no modo apagar disco.
- Manual/reuso: partições comuns do mesmo disco; não habilita arbitrariamente RAID, LUKS, volumes LVM ou BIOS/GPT. Fluxo físico multidisco antigo segue preservado no instalador clássico.
- Falha Flutter/Android: repetir ou pular sem impedir GRUB/boot; timeouts em fetch/clone/`flutter --version` e arquivo `/var/log/wolf-optional-failures.log` para pendências. Pacotes opcionais AUR/Chaotic com falha também podem ser repetidos ou pulados. Pacotes oficiais e sistema-base mantêm falha fatal.

## Segurança e homologação
- Confirmar duas vezes mostra ações destrutivas e de preservação, mantém a Live como requisito, validação de modo firmware, partições, MAJ:MIN e nova verificação privilegiada antes de gravar.
- Testes automatizados de contratos SATA/NVMe/eMMC/VirtIO, regressões de versões anteriores e staging simulado.
- **Ainda sem instalação real executada nesta versão**, especialmente no hardware físico pela nova interface; testar preferencialmente em mídia/VM descartável antes de dados importantes.
