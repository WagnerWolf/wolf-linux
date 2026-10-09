# Wolf Linux DevKit 2.0.0-alpha20 — Wolf Live GUI 0.2

- Mantém a alpha18/19 independentes.
- Troca títulos visíveis de GRUB, Syslinux e systemd-boot/loader por Wolf Linux sem modificar os parâmetros do Archiso.
- Substitui o splash do Syslinux existente pelo arquivo oficial Wolf.
- Personaliza /etc/os-release, /etc/issue e /etc/motd da live.
- GUI mostra discos e partições reais via lsblk em leitura, escolha de estratégia, stacks e pré-plano.
- Oferece opção separada para abrir wolf-install --plan-only em terminal; o backend continua perguntando por armazenamento e usuário.
- **Não** habilita formatação/instalação pela GUI. A seleção do disco na GUI não é passada ao backend.
- GParted permanece uma ferramenta de uso separado, com modificações próprias e confirmação explícita.
