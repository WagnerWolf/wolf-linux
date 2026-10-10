# Wolf Linux alpha42 — executor LAB41 em QEMU/KVM

A alpha42 acrescenta um **executor experimental para os dois discos VirtIO do
laboratório alpha41**, sem habilitar instalação em hardware físico.

## Pré-requisito: manter o laboratório criado na alpha41

O usuário já validou na alpha41 a detecção e o plano do laboratório:
- `/dev/vda1`: ESP FAT32 do disco **WOLF41EFI**, 64 GiB
- `/dev/vdb1`: raiz ext4 do disco **WOLF41ROOT**, 96 GiB
- `/dev/vdb2`: partição NTFS com arquivo-testemunha
- `/dev/vda2` + `/dev/vdb3`: PVs do `vg_monstro`
- `/dev/mapper/vg_monstro-lv_projetos`: `/home` ext4, LV com dois PVs

**O executor formata SOMENTE `/dev/vdb1`**. EFI, NTFS e `/home` LVM são
preservados, inclusive todos os PVs. Nenhum comando de recriação de GPT,
`wipefs`, `pvcreate`, `vgcreate` ou `lvcreate` é executado por esse caminho.

Não execute `wolf-lab41-particionar --apply` outra vez nos qcow2 já preparados.

## Host: gerar a ISO alpha42 e iniciar os DOIS discos existentes

```bash
cd wolf-linux-devkit-2.0.0-alpha42
./preparar_ambiente_wolf_linux.sh --project "$HOME/wolf-linux-alpha42"
cd "$HOME/wolf-linux-alpha42"
./tests/wolf-build-iso.sh
```

Seus discos de laboratório estão, normalmente, no projeto alpha41. **Desligue
completamente a VM antes de copiá-los** para o projeto alpha42; não execute duas
VMs sobre os mesmos arquivos qcow2. Recomendamos copiar como arquivos diferentes
(`cp --reflink=auto -a`) e deixar o laboratório original intacto:

```bash
mkdir -p "$HOME/wolf-linux-alpha42/vm/lab-alpha41-multidisk"
cp --reflink=auto -a \
  "$HOME/wolf-linux-alpha41/vm/lab-alpha41-multidisk/wolf41-efi-lvm.qcow2" \
  "$HOME/wolf-linux-alpha41/vm/lab-alpha41-multidisk/wolf41-root-lvm.qcow2" \
  "$HOME/wolf-linux-alpha42/vm/lab-alpha41-multidisk/"
```

As variáveis OVMF serão criadas no novo projeto. Em seguida:

```bash
./tests/wolf-vm-multidisk.sh live
```

## Na Live da VM

1. Execute `sudo wolf-lab41-verificar` para conferir os três testemunhos
   (EFI, `/home`, NTFS) antes da instalação.
2. No Wolf Installer escolha **Reutilizar partições existentes** e **Detectar
   instalações em TODOS os discos**; confira `/`, EFI e `/home`.
3. Confirme atribuições, escolha inicialmente **Minimal** para a primeira
   instalação, revise e simule; ambas as ações devem terminar em código 0.
4. Para diagnóstico adicional, execute a verificação não destrutiva:

```bash
sudo wolf-install --preflight-multidisk-lab-vm \
  /home/wolf/.local/state/wolf-linux/live-installer/preview.json
```

5. Na aba **Revisão**, clique em **Laboratório alpha42 — reinstalar somente a
   raiz da VM multidisco**. A GUI pede confirmação; depois o Bash exige
   **`FORMATAR /dev/vdb1`**, seguido da senha do usuário a instalar.
6. Ao terminar, desligue a VM e inicie pelo disco:

```bash
./tests/wolf-vm-multidisk.sh installed
```

7. Confira `findmnt /`, `findmnt /home`, `findmnt /boot/efi`, `cat /etc/fstab`
   e os arquivos testemunha. Para testar os três testemunhos pelo helper, volte
   à Live, certifique-se de que estão desmontados e execute
   `sudo wolf-lab41-verificar`.

## Limites e proteção

- **SOMENTE QEMU/KVM, firmware UEFI, Live Archiso, discos VirtIO com seriais
  `WOLF41EFI` e `WOLF41ROOT`, tamanhos exatos 64/96 GiB, nomes de partição do
  laboratório, `/home` no LV de dois PVs, UUIDs/fstab revalidados.**
- Qualquer disco montado, divergência de serial/partição/fstab, ou checkpoint
  de instalação interrompida causa bloqueio. Não há desmontagem forçada.
- O documento JSON mantém `execution=disabled`. Somente o comando separado
  `--execute-multidisk-lab-vm` inicia uma instalação, após dupla confirmação.
- A EFI pode receber arquivos **WolfLinux** e uma entrada UEFI do GRUB, mas
  não é formatada e seu fallback `EFI/BOOT/BOOTX64.EFI` não é recriado nesse modo.
- Não foram executadas instalações reais neste ambiente de desenvolvimento;
  o primeiro teste executável deve ocorrer exclusivamente nos qcow2 de teste.
- **Não execute isso no computador físico.** Não existe executor multidisco
  físico habilitado nesta revisão.
