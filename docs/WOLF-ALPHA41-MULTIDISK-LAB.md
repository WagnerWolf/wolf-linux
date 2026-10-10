# Wolf Linux alpha41 — Laboratório de dois discos QEMU/KVM

A alpha40 é a referência anterior. A alpha41 acrescenta **um laboratório isolado** que
reproduz a dependência de **EFI em um disco, raiz no outro e `/home` em LVM
com dois PVs**. O laboratório não executa instalação nem altera SSDs físicos.

## Etapa 1 — no Arch hospedeiro (SEM sudo)

Após preparar o projeto e construir a ISO da alpha41:

```bash
cd "$HOME/wolf-linux-alpha41"
./tests/wolf-vm-multidisk.sh create
./tests/wolf-vm-multidisk.sh live
```

O comando `create` gera, numa pasta exclusiva `vm/lab-alpha41-multidisk/`,
dois arquivos qcow2 esparsos: 64 GiB e 96 GiB. Ele **recusa sobrescrever**
qualquer imagem já existente. `live` liga a ISO mais recente; opcionalmente
`WOLF41_ISO=/caminho/arquivo.iso ./tests/wolf-vm-multidisk.sh live`.
O QEMU exporta os discos com seriais `WOLF41EFI` e `WOLF41ROOT`.

Não use `wolf-vm.sh fresh` neste laboratório. Não precisa de loop devices,
`qemu-nbd`, `sudo` nem particionar dispositivos do host.

## Etapa 2 — dentro da ISO Live na VM (destrutiva SOMENTE nos qcow2)

No QTerminal da VM:

```bash
sudo wolf-lab41-particionar --check
sudo wolf-lab41-particionar --apply
```

`--check` examina virtualização, UEFI, seriais, dispositivos e tamanhos **sem
alterar nada**. `--apply` só funciona dentro da Live QEMU/KVM, com os dois
seriais especiais, tamanhos exatos e **discos ainda vazios**. Solicita digitar
`CRIAR-LAB41` antes de usar sgdisk/mkfs/LVM. A segunda execução deve recusar
os discos já particionados — não use `--apply` para reinstalação.

| Dispositivo QEMU | Layout preparado |
|---|---|
| `WOLF41EFI` — 64 GiB | ESP GPT de 1 GiB (FAT32) + PV LVM no restante |
| `WOLF41ROOT` — 96 GiB | raiz ext4 40 GiB + NTFS de teste 8 GiB + PV LVM no restante |
| `vg_monstro/lv_projetos` | LV ext4 com 100% dos extents livres dos dois PVs, usado como `/home` |

Os tamanhos são **reduzidos propositalmente** para o teste; os papéis e a
dependência do LVM reproduzem o hardware físico. A partição NTFS simula a preservação de dados do Windows, mas **não contém Windows instalado**.

O preparo grava `/etc/fstab` dentro da partição raiz do laboratório, contendo
UUIDs reais para `/`, `/boot/efi` e `/home`, além de arquivos-testemunha na
EFI, em `/home/wolf/Documentos` e na partição extra.

## Etapa 3 — detectar, validar e simular pela GUI

Abra **Wolf Installer → Partições → Reutilizar partições existentes** e clique
em **Detectar instalações em TODOS os discos (inclui LVM)**. Confira cada
atribuição, confirme o mapeamento e vá à aba de revisão. Execute as duas
ações **Validar plano JSON** e **Simular etapas do backend Bash**.

O resultado esperado é código `0`, raiz no disco `WOLF41ROOT`, ESP em
`WOLF41EFI`, `/home` no LV e **ambos os PVs listados**. Nenhuma operação de
formatação ocorre nessas duas ações.

## Etapa 4 — comprovar preservação, em modo leitura

```bash
sudo wolf-lab41-verificar
```

A ferramenta monta EFI, `/home` e a partição extra em somente leitura,
mostra três arquivos-testemunha e desmonta esses volumes normalmente.
Esse teste ainda **não comprova uma reinstalação**, apenas valida a base.

## Limites desta alpha41

- **Não** existe `--execute-multidisk-plan` nesta versão.
- Planos multidisco mantêm `execution=disabled` e não são aceitos no executor
  de um disco da VM nem no instalador de hardware real.
- A próxima fase será conectar o **executor multidisco restrito a estes dois
  discos virtuais**, testar reinstalação e confrontar os arquivos-testemunha.
- Nenhuma tentativa deve ser feita nos NVMe reais; especialmente não executar
  `pvcreate`, `vgcreate`, `wipefs` ou `sgdisk` em discos físicos.
