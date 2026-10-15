# Wolf Linux DevKit 2.0.0-alpha32

## Mudanças

- Wolf Installer GUI 1.2: aba **Instalação** ocupa página própria, não uma pequena caixa inferior.
- O processo Bash é executado por PTY em sessão isolada, com saída, entrada interativa e senha em modo oculto por padrão; código de saída do próprio processo determina sucesso/falha. Log por execução com modo 0600, scroll visual limitado. A GUI impede fechar janela durante instalação ativa.
- O caminho de execução continua `--execute-gui-plan-vm`, protegido por verificação de VM QEMU/KVM, disco VirtIO, revalidação de identidade, confirmacões independentes e **sem habilitar hardware físico**.
- Em BIOS/Legacy + MBR, o manual e a reutilização de /home dedicada dispensam totalmente EFI. O backend já instala GRUB i386-pc em disco no BIOS. O manual BIOS exige MBR/DOS; BIOS+GPT com bios_grub não está habilitado para manual/reutilizar.
- Nova ferramenta `wolf-live-storage-topology` consulta lsblk/blkid/pvs/vgs/lvs com comandos de leitura, sem montar volumes ou ativar VGs; pacote lvm2 incluído só na ISO Live.

## Requisito obrigatório futuro: hardware multidisco + LVM

O ambiente físico alvo pode usar **EFI num SSD, raiz / em outro SSD e /home dentro de LVM**. O executor atual limita todos os papéis ao mesmo disco VirtIO e **NÃO deve ser usado nesse hardware**. Antes da liberação, implementar contrato multi-device (identificadores estáveis e revalidação), seleção por papel em discos distintos, mapeamento PV/VG/LV, preservação de home/LVs, GRUB e NVRAM, simulação/read-only e testes com VM de dois discos e LVM. Não ativar volumes inadvertidamente.

## Testes

- Testes unitários de pré-planos BIOS e UEFI, preservação EFI, BIOS sem ESP, barreiras de VM, conversão em 17 campos, terminal PTY simulado com confirmação e senha sem eco.
- Smoke test e staging Archiso simulado; ainda falta gerar ISO real, usar a GUI PySide6 na live da VM e validar boot BIOS/MBR e o fluxo terminal até o fim.
- Não foram realizados mounts, mkfs, grub-install ou instalação reais neste ambiente.
