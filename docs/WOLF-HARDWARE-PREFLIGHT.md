# Wolf Linux — Homologação em hardware físico (alpha37)

## Estado

- Instalação GUI validada na VM para UEFI/BIOS: apagar, manual e reutilizar /home dedicada.
- Instalação gráfica física continua **BLOQUEADA** nesta revisão.
- Alpha37 entrega Chromium + Bluetooth e Wolf Rescue 0.1 SOMENTE DIAGNÓSTICO.
- O plano físico deve suportar EFI e raiz em discos distintos; LVM multidisco não é partição ext4 comum.

## Topologia real informada pelo diagnóstico

- Pendrive Ventoy: `/dev/sda` na sessão observada. Nomes podem mudar entre boots!
- NVMe ~931,5 GiB: EFI FAT32 de 1 GiB (`nvme0n1p1`); PV LVM (`nvme0n1p2`).
- NVMe ~465,8 GiB: partição Linux ext4 de ~100 GiB (`nvme1n1p1`); NTFS do Windows; outro PV LVM (`nvme1n1p6`).
- Grupo LVM `vg_monstro`, com **2 PVs em discos distintos**, e LV linear `lv_projetos` de ~1,13 TiB, filesystem ext4.
- NÃO assumir que `lv_projetos` corresponde a `/home`; confirmar `/etc/fstab` e UUID da instalação.

## Passos somente de leitura na Live

1. Abrir **Wolf Rescue** pelo menu Openbox ou pela aba Bem-vindo.
2. Conferir inventário de discos, UUID, VG/LV, NVRAM UEFI. Copiar relatório.
3. Pelo PCManFM-Qt, montar a partição raiz antiga quando apropriado; identificar `etc/fstab` e selecioná-lo no Wolf Rescue (Leitura de fstab).
4. Comparar UUID de `/`, `/home`, `/boot/efi`, sem supor pontos de montagem pelo nome.
5. Fazer backup externo testado ANTES de qualquer proposta de reparo ou formatação.

## Requisitos para o executor físico (versão futura)

- Dispositivos por WWN/serial/PARTUUID/UUID, revalidados após a confirmação e antes de toda escrita.
- Proteger rigidamente mídia Live, NTFS/Windows, discos montados, swap, LV ativo e partições não selecionadas.
- Seleção de EFI/raiz/volumes em discos diferentes sem implicitamente formatar o disco da EFI.
- Seleção do LV por UUID/PATH com exame do mapa de PVs (pode usar múltiplos SSDs).
- Não executar `pvremove`, `vgremove`, `lvremove`, nem recriar VG/LV numa instalação de reaproveitamento.
- Exibir impacto sobre o conjunto de discos subjacentes, preservar outras entradas UEFI.
- Homologar em VM com dois discos e LVM, incluindo falha interrompida, reboot e preservação comprovada.
- Só então experimentar em mídia física DEDICADA e descartável antes dos SSDs de trabalho.

## Wolf Rescue 0.1 não executa reparos

Esta primeira versão NÃO oferece grub-install, efibootmgr -c/-b, mkinitcpio, fsck,
chroot nem operações de montagem/reconfiguração automatizadas. Serviços de recuperação
serão adicionados após protocolos específicos de backup/rollback e validação em VM.

## Alpha38: auditoria de discos físicos e visualização da Live

O Wolf Rescue 0.2 possui uma aba **Mapa de volumes**. Após abrir, usando o PCManFM-Qt, a raiz antiga e selecionar o arquivo `etc/fstab`, correlaciona UUIDs do fstab com dispositivos do `lsblk`. Se existir `/home` em LVM espalhado por mais de um PV, a tela lista ambos. Dados ausentes ou inconclusivos bloqueiam conclusões; não alteram os discos.

Cenário observado no diagnóstico de referência do usuário (confirmado por UUID, não pelos comentários do fstab):
- `/`: partição ext4 no segundo NVMe.
- `/boot/efi`: partição VFAT no primeiro NVMe.
- `/home`: um LV ext4 que utiliza dois PVs no mesmo grupo de volumes.
- Existem bootloaders UEFI para WolfLinux, GRUB e Windows; preservar entradas existentes é obrigatório.

**Não é permitido habilitar instalação gráfica física em alpha38.** Primeiro homologar backup, volumes multi-PV e seleção multidisco num ambiente descartável.
