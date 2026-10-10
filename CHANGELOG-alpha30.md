# Wolf Linux DevKit 2.0.0-alpha30

## Correções

- Manual UEFI da GUI: formatação da raiz ext4 obrigatória e opções **independentes** para formatar (FAT32) ou preservar EFI, e formatar (ext4) ou preservar `/home` separada.
- O tipo GPT de EFI System é aplicado pelo Bash à partição escolhida; nenhuma flag ESP precisa ser configurada manualmente no GParted. Exige GPT e ESP >=512 MiB.
- Preview JSON continua `wolf.install.preview.v2`, `execution=disabled`; o executor separado passa a exportar 16 campos e revalida as flags antes da preparação do disco.
- Preflight recusa preservação de EFI sem FAT e preservação de `/home` sem ext4; permite inicializar filesystem vazio/outro tipo quando a formatação for expressamente selecionada.
- Avisos explícitos para partições com filesystem existente, aconselhando modo Reutilizar se os dados precisarem ser preservados (modo ainda não executável na GUI).
- Minimal sem stacks opcionais pula as etapas 63 (Chaotic-AUR) e 64 (resolver/AUR) integralmente; demais perfis preservam a prioridade dos repositórios.
- Novo botão de desmontagem assistida de tentativas anteriores e pergunta quando detecta partição montada. Restringe-se a `/mnt`, `/mnt/boot/efi`, `/mnt/home` e ao disco VirtIO escolhido, confirma e não força desmontagem; checkpoints removidos depois.
- Novo `Wolf Live GUI 1.0`, mantendo modo apagar disco, revisão, simulação, conclusão/reinício e sistema KDE da alpha29.

## Validação

- Testes estruturais e unitários em ambiente de desenvolvimento, inclusive simulação de desmontagem com executáveis falsos; sem operações de disco reais.
- Aguardando montagem da ISO real e testes destrutivos somente em VM descartável, especialmente manual com ESP/home para formatar e Minimal.
