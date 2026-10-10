# Wolf Linux 2.0.0-alpha42 — executor laboratório multidisco

- Integra o contrato multidisco `wolf.install.multidisk.preview.v1` ao motor
  Bash em ação **separada** `--execute-multidisk-lab-vm`, somente VM QEMU/KVM
  Lab41 identificada por dois seriais, tamanho e rótulos de partições.
- Novo preflight sem escrita `--preflight-multidisk-lab-vm` e exportador seguro.
- Revalidação do inventário/UUIDs/fstab/LVM antes da formatação da raiz.
- Reutiliza etapas já testadas (pacstrap, configuração, GRUB), formatando
  exclusivamente `/dev/vdb1`; preserva EFI `/dev/vda1`, NTFS `/dev/vdb2`
  e `/home` no LV multi-PV.
- Nova ação da GUI Live 2.1 na aba Revisão, disponível apenas no laboratório;
  console PTY integrado com confirmações e resultado da instalação.
- Não habilita instalação multidisco em SSDs físicos.
- Testes unitários de segurança, regressões do smoke e staging da ISO.

**Pendente:** execução completa da ISO real e verificação dos arquivos
preservados na VM; testes locais não fazem formatação.
