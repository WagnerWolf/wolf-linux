# Wolf Linux 2.0.0-alpha35 — Live Rescue: navegador e volumes (somente leitura)

- Firefox + tradução pt-BR apenas na Live Openbox; acessível via menu e tela inicial da GUI.
- Wolf Mount Manager: inventário de partições, FAT, NTFS, ext4, XFS e Btrfs, volumes lógicos LVM **ativos**. Montagem explícita somente leitura com proteção contra replay do journal ext4/XFS; valida montagem RO no kernel; abre em PCManFM-Qt; desmontagem normal de pontos criados pelo Wolf.
- Nenhuma montagem automática, `fsck`, `vgchange`, partição/formatação/instalação habilitada por esse módulo. LVM2_member é PV, não FS diretamente montável. Volumes criptografados e LVM inativos exigem fluxo de recuperação futuro.
- Consultas LVM do `wolf-live-storage-topology` usam sudo para superar a falta de permissões em `/dev/mapper/control`; seguem usando apenas `--readonly`, sem ativar VGs ou alterar metadados.
- Componentes `firefox firefox-i18n-pt-br gvfs udisks2 udisks2-lvm2 ntfs-3g exfatprogs` entram **somente na ISO**, nunca nas stacks KDE instaladas.
- O executor gráfico permanece restrito a VM QEMU/KVM VirtIO. **Hardware físico NÃO liberado para instalação**.
- Testes estruturais e de simulação de montagens sem direitos root incluídos. Necessários build e testes na live física para homologação da GUI e montagem real.
