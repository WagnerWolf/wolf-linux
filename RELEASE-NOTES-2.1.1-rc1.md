# Wolf Linux DevKit 2.1.1-rc1 — Multidisco e /home LVM

Base: **Wolf Linux 2.1.0**. Esta é uma **versão candidata**, não homologada em instalação física.

## Mudanças
- Os modos Manual/Reutilizar não exigem que raiz, EFI e /home estejam no mesmo disco.
- Aceita uma partição física ext4 para raiz, ESP física FAT32 em outro disco e /home ext4 como LV LVM que pode usar múltiplos PVs.
- O plano canônico confere identidade de raiz/EFI/LV, MAJ:MIN, UUID, discos ancestrais e PVs antes de executar; revalida antes de `mkfs`.
- A prévia de dotfiles faz mount **ro,noload,nosuid,nodev,noexec** do LV ext4 selecionado; a limpeza é opcional e exige revisão e dupla confirmação.
- `sgdisk` ajusta o tipo ESP no disco físico da EFI, nunca no disco raiz por suposição.
- Nenhum PV é formatado; formato de LV LVM bloqueado; Windows/NTFS fora do plano não são modificados.
- Apagar disco inteiro com LVM compartilhado segue bloqueado, pois pode destruir LVs estendidos por outros discos.

## Limitações deliberadas
- Raiz deve ser partição física regular (não suporta raiz LVM/LUKS/RAID neste executor).
- /home pode ser partição ext4 ou LV LVM ext4 **preservado**; formatar o LV é proibido.
- Volume lógico precisa estar ativo na Live (se `lsblk` não mostrar o LV, NÃO prossiga).
- Não foi realizado ensaio de escrita em hardware real. Faça backup dos arquivos indispensáveis e confira as operações antes do consentimento.
- O modo BIOS continua exigindo uma tabela MBR para o disco de boot; GPT BIOS com bios_grub segue fora do suporte.

## Validações
- Regressão in-memory cobre raízes e ESP cruzadas, /home LVM multi-PV, PV alterado/ausente, tentativa de formatar LV, tentativa de selecionar PV.
- O conjunto de testes legado pode incluir testes que dependem de recursos indisponíveis neste ambiente.
