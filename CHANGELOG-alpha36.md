# Wolf Linux 2.0.0-alpha36 — Arquivos, dispositivos e autenticação na Live

- **PCManFM-Qt como gerenciador único de dispositivos.** Removido o Wolf Mount Manager da GUI, dos menus e do staging. Dispositivos são apresentados pela integração GVfs/UDisks2. O usuário da Live pode solicitar a montagem na barra lateral do explorador e acessar os arquivos, inclusive com escrita quando permitida pelo volume.
- **Sem PCManFM executado como root.** Uma regra Polkit limitada à Live autoriza exclusivamente as ações UDisks2 `filesystem-mount` e `filesystem-mount-system` na sessão local ativa do usuário temporário `wolf`. Essa regra não concede permissões para formatar, modificar partições ou administrar LVM.
- **Relógio e login.** Habilitado `systemd-timesyncd` na Live; ferramenta `wolf-live-time-status` e atalho para verificar sincronização de hora, importante em códigos TOTP. Firefox pt-BR mantido. Bluetooth não foi adicionado como solução para passkeys, pois o Firefox Linux pode não oferecer autenticação por telefone.
- **Diagnóstico físico validado pelo usuário na alpha35:** EFI em NVMe0, raiz ext4 em NVMe1, VG `vg_monstro` com PVs em dois SSDs e LV `lv_projetos` de ~1,13TiB. Não presumir `/home` sem conferir fstab da instalação; manter instalação gráfica física bloqueada.
- **Compatibilidade:** instalação GUI continua restrita a VMs VirtIO, sem alteração no motor de instalação.

Testes: smoke completo, regressões alpha35/36 e staging simulado duas vezes. Boot real e montagem via PCManFM-Qt ainda precisam ser validados no equipamento.
