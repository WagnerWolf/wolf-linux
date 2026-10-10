# Wolf Linux alpha46 — ensaio multidisco no hardware real, SEM ESCRITA

Este modo NÃO comenta/desativa linhas destrutivas do instalador real. Ele é **outro
programa**: verifica o contrato JSON anterior usando `wolf_discovery`, analisa a
sequência de `stage` que o Bash real declara e **somente imprime** o roteiro.
Isso impede que uma função secundária do instalador grave dados sem querer.

## Uso na ISO

1. Inicie a ISO UEFI Live, abra o Wolf Installer > **Partições** > **Reutilizar**;
   detecte todos os discos e confirme raiz, ESP e `/home` em LVM; confirme o plano.
2. Em **Revisão**, rode Validação JSON e Simulação (ambas devem terminar em 0).
3. Clique **Ensaio físico integral — TODAS as etapas descritas, SEM EXECUTAR**.
4. Confira o mapeamento da raiz, EFI, `/home` e PVs, as 25 etapas hipotéticas e
   o resultado `ENSAIO DE PLANO APROVADO`. `código 0` valida **somente o plano**.

Também é possível executar `sudo wolf-install --rehearse-multidisk-physical
<caminho/preview.json>` na Live. O arquivo de plano precisa ser criado
pela GUI; não utilize um JSON elaborado manualmente.

## Máquina física usada como referência

- Raiz **a ser formatada futuramente**: `/dev/nvme1n1p1` (UUID atual ext4).
- EFI **a preservar**: `/dev/nvme0n1p1` FAT32, incluindo carregadores de Windows/GRUB.
- `/home` **a preservar**: `/dev/mapper/vg_monstro-lv_projetos` ext4.
- PVs **a preservar**: `/dev/nvme0n1p2` e `/dev/nvme1n1p6`.
- Partições NTFS e partições não selecionadas: **não tocar**.

As identidades atuais são conferidas no scan; NÃO confiar em nomes nvmeX sem
validar UUID/PARTUUID, tamanho e relacionamentos LVM.

## Resultados possíveis

`0`: contrato revalidado, nenhum alvo montado e roteiro do Bash coberto. **Não**
comprova execução das etapas, disponibilidade de pacotes, GRUB/NVRAM ou reboot
físico. `2`: ensaio recusado. Refaça a detecção, não contorne o bloqueio.

O motor de instalação física multidisco permanece **desabilitado** na alpha46.
O ensaio não exige disco adicional nem remoção dos seus NVMe. Para eventual
instalação destrutiva real, faça e verifique previamente backup externo,
principalmente de `/home` multi-PV e dos dados Windows/EFI. Não é um substituto
para uma recuperação de falhas testada.
