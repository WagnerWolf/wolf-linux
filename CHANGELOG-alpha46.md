# 2.0.0-alpha46 — ensaio físico integral, sem escrita

- Roteiro físico UEFI multidisco/LVM (25 etapas), extraído de `main()` do instalador e
  recusando mudanças de etapas que não tenham representação no relatório.
- Novo `wolf-install --rehearse-multidisk-physical <preview.json>`: valida JSON
  contra inventário atual, UUIDs, PARTUUIDs, tamanho, fstab, EFI e LVM; requer
  Live, root, ESP em disco distinto da raiz e `/home` com PVs nos dois discos.
- Recusa divergências manuais de fstab e volumes-alvo montados, sem execução de
  `mkfs`, `pacstrap`, `arch-chroot`, gravação de `fstab`, GRUB ou NVRAM.
- GUI ganhou botão **Ensaio físico integral** na aba Revisão; abre QTerminal para
  acompanhar as etapas, não pede senha nem faz formatação.
- Teste da alpha46 com fixture dos dois NVMe reais: rejeição de alterações e
  cobertura estrutural de 25 etapas; regressões anteriores preservadas.
- Sem alteração do executor de instalação já validado na VM. Instalação em
  hardware físico permanece BLOQUEADA; êxito em simulação não homologa boot.
