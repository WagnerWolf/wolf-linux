# Wolf Linux DevKit 2.0.0-alpha53 — Integração inicial na VM

- Nova interface: botão **Confirmar**; seletor de teclado da Live, teste de digitação e configuração no sistema-alvo.
- Barra lateral: nome do usuário, hostname e perfil Minimal/Test/Full.
- Três fluxos ligados ao contrato independente `wolf_plan` e ao Bash: Apagar disco, Manual e Reutilizar.
- Antes dos diálogos: preflight contra o inventário real, firmware, identidade MAJ:MIN, montagens, tabela GPT/MBR e disco VirtIO.
- Duas confirmações por clique; novo modo Bash explícito `--execute-gui-plan-vm-click`, disponível somente em VM validada, dispensa digitar APAGAR. Sem mudança no executor físico homologado.
- Limpeza de dotfiles em VM continua exigindo sua confirmação específica `LIMPAR` e exige /home separada. Backup de dotfiles na VM ainda não está implementado, por isso a caixa correspondente está desabilitada.
- Instalação real pela nova interface SOMENTE dentro da ISO Live de VM QEMU/KVM/VirtualBox com disco `/dev/vdX`. Para hardware físico e LVM multidisco, utilizar o instalador clássico homologado.
- O modo Manual VM ainda não cria/redimensiona partições: utilizar GParted e atualizar o inventário. Exige partições comuns de um único disco, UEFI/GPT ou BIOS/MBR.
- O modo Reutilizar VM também exige /home separada no mesmo disco. Não habilitar máquinas físicas até homologação dedicada.
- Em disco BIOS, usar partição raiz com capacidade suficiente e MBR/DOS; tabelas GPT BIOS continuam bloqueadas neste piloto.
- Segurança: nenhum ID de partição ou UUID do hardware do autor é usado como destino na nova interface; o Bash revalida novamente.
