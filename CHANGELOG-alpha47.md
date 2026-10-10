# Wolf Linux 2.0.0-alpha47 — primeira execução física controlada

- Novo executor físico dedicado `--execute-multidisk-physical`: exige Live Archiso, UEFI, hardware físico, dois NVMe diferentes, dois PVs para o LV /home e correspondência exata por UUID/PARTUUID e fstab.
- Preflight `--preflight-multidisk-physical` somente leitura, usando o JSON desabilitado (`execution=disabled`) da descoberta.
- Executor revalida identidades novamente imediatamente antes de `mkfs.ext4`; nunca altera GPT, reformata ESP/home ou remove PVs.
- Duas confirmações em terminal (reconhecimento da perda sem backup geral e raiz exata); GUI também exige confirmação própria.
- GRUB UEFI com `--no-nvram` e ID `WolfLinux`, sem fallback e sem alterar BootOrder.
- Reaproveita o backend alpha42 aprovado em VM, incluindo permissões de /home e todas as etapas de pacstrap/fstab/serviços, sem refazer o motor.
- Novos testes de contrato e regressões ajustadas (alpha43, alpha45, alpha46); smoke e staging simulado passaram.
- Não testado em instalação real física nesta entrega; recomenda-se Minimal no primeiro boot físico.
