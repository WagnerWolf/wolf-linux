# Wolf Installer GUI 1.9 — Reutilização multidisco e LVM

## Na mídia Live

1. Abra o **Wolf Installer**, aba **Partições**.
2. Em **Como instalar**, escolha **Reutilizar partições existentes**.
3. Clique em **Detectar instalações em TODOS os discos (inclui LVM)**. O scanner procurará sistemas ext4, lendo seus arquivos `etc/fstab` com montagem temporária somente leitura quando preciso.
4. Se houver mais de uma instalação, escolha a raiz `/` na lista **Instalação encontrada**. A própria raiz é determinada pelo `fstab` encontrado.
5. Confirme as sugestões de **EFI /boot/efi** e **/home**. As listas mostram partições de todos os discos e volumes lógicos reconhecidos; não estão restritas ao disco da raiz.
6. Se modificar um volume em relação ao `fstab`, leia o aviso e marque também **CONFIRMO divergências**. Marque **CONFIRMO as partições**.
7. Confira **Software e usuário**; abra **Revisão**, clique **Validar plano JSON** e **Simular etapas do backend Bash**. Ambos devem produzir um relatório com `EXECUÇÃO: BLOQUEADA`.

O estado apresentado para uma instalação UEFI com EFI no NVMe 1, raiz no NVMe 2 e `/home` no LV de dois PVs deve mostrar os **dois discos físicos do LV**, preservando todos os PVs.

## Revisão CLI

A GUI grava um arquivo privado em `~/.local/state/wolf-linux/live-installer/preview.json`.

```bash
sudo wolf-install --review-multidisk-plan "$HOME/.local/state/wolf-linux/live-installer/preview.json"
sudo wolf-install --simulate-multidisk-plan "$HOME/.local/state/wolf-linux/live-installer/preview.json"
```

O Bash encaminha esses comandos ao validador independente antes de entrar na rotina principal. A validação faz novamente o scan e recusa documentos com UUID, tamanho, MAJ:MIN, hash do `fstab`, dependências LVM ou dispositivos alterados.

**Esses comandos NÃO instalam, não criam partições, não formatam e não executam GRUB.** A opção de instalação VM do contrato antigo continua com suas próprias barreiras e não aceita o novo JSON multidisco.

## Limites e segurança

- O scanner somente descobre roots ext4 montáveis sem journal replay (`ro,noload`) e não modifica os arquivos da instalação; não ativa PVs/VGs/LVs inativos.
- EFI existente deve estar em FAT/vfat e será **preservada**; `/home` existente deve ser ext4 para receber a sugestão da GUI.
- Se `/home` estiver dentro da raiz, formatar a raiz numa instalação futura destruiria esses arquivos; não confundir com preservação dedicada.
- Não misturar firmware BIOS/UEFI; Windows/NTFS não pode ser selecionado como `/home` ou raiz ext4.
- Numa topologia com LVM em dois SSDs, backup de todos os PVs é essencial. Não executar `pvremove`, `vgremove`, `lvremove`, `mkfs`, `wipefs` nem redimensionar volumes reais durante os testes.
