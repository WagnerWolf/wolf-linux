# Wolf Live GUI 1.0 (alpha30) — Manual UEFI e Minimal sem AUR

- Na VM QEMU/KVM UEFI, selecione as partições no GParted e atribua os papéis na GUI.
- **Raiz `/`:** obrigatória, formatada em ext4. Tamanho mínimo do piloto: 20 GiB.
- **EFI `/boot/efi`:** obrigatória, mínimo 512 MiB. Marque `Formatar EFI` para criar FAT32 novo ou desmarque para preservar FAT32 existente. O backend aplica o **tipo GPT ESP** à partição indicada, sem precisar marcar flags no GParted.
- **`/home` dedicada:** opcional. Marque `Formatar /home` para ext4 novo; desmarque para preservar ext4 existente. Sem partição dedicada, `/home` fica dentro da raiz formatada.
- Marcar formatação de EFI ou `/home` com filesystem existente provoca aviso de perda de dados e recomendação de reutilização; a escolha explícita manual permanece possível.
- **Minimal:** sem stacks opcionais, pula completamente as etapas de instalação Chaotic-AUR e resolução AUR. Outros presets mantêm Arch > Chaotic > AUR.
- **Recuperação de tentativa falha:** botão na guia inicial e diálogo ao detectar volumes montados. O assistente mostra os volumes sob `/mnt`, exige `DESMONTAR` e usa apenas `umount` normal (sem `-f` ou `-l`). Recusa montagens fora da lista e de outro disco; limpa checkpoints somente após confirmação, preserva logs.
- **Limites:** exclusivamente VM VirtIO UEFI; partições de um único disco GPT; reutilização de partições para instalação ainda bloqueada. Use uma VM descartável. Não validado nesta revisão com instalação real no QEMU.

---

# Wolf Live GUI 0.9 (alpha29) — instalação manual VM UEFI

Nova opção **Avançado/manual** em VM: crie GPT + ESP FAT32 (flag `esp`), raiz ext4 e `/home` ext4 opcional com o GParted. Depois atribua essas funções na GUI. A raiz `/` será formatada; ESP e `/home` separada serão PRESERVADAS. O instalador usa o backend Bash existente para montagem/instalação, com confirmação `APAGAR`. O modo **Apagar disco inteiro** aceita partições já existentes; ele cria `/home` dentro de `/`. O modo **Reutilizar** NÃO executa instalações nesta revisão.

O plano JSON continua sem permissão de execução; um comando separado `--execute-gui-plan-vm` valida modo, dispositivos e uso atual do disco antes de qualquer alteração. Sem suporte manual BIOS nem hardware real. Teste somente em VM descartável.

# Wolf Live GUI 0.9 (alpha28) — tela de conclusão

A execução VM usa `wolf-live-execute-vm-plan preview.json RESULTADO.status`, fornecido pela interface. O arquivo privado começa vazio e registra `success` apenas se o Bash retornar 0. Após Enter no QTerminal, a GUI apresenta o diálogo de conclusão, permite **Reiniciar agora** ou **Continuar na Live** e fecha a janela antiga. Com erros, o resultado é `failed N` e nenhum sucesso é exibido. Reinicialização apenas com confirmação, na Wolf Live. O motor Bash e a seleção dos discos são os mesmos da alpha27.

# Wolf Live GUI 0.7 (alpha27)

O Openbox/Xorg e a GUI PySide6 pertencem **somente à live**.
O sistema instalado continua KDE Plasma/Wayland, exatamente como na alpha18.

## Primeiro boot
- `wolf` é um usuário temporário criado em RAM antes do getty de tty1.
- O tty1 entra automaticamente e executa Xorg/Openbox (sem display manager).
- Se Xorg falhar, o login mantém terminal e permite `sudo wolf-install`.
- Para iniciar sem gráficos adicione `wolf.nogui=1` à linha de boot (editor GRUB/bootloader).
- Terminais secundários: `Ctrl+Alt+F2`; login/senha precisam ser tratados conforme o ambiente Archiso.
- Clique direito no desktop abre menu Openbox; `Ctrl+Alt+T` abre QTerminal.

## Segurança e escopo
- O instalador visual planeja discos, perfis e usuário. O piloto da alpha27 executa
  instalação apenas em VM QEMU/KVM com disco VirtIO vazio e confirmação explícita.
- GParted é explicitamente privilegiado: só realiza alterações após escolhas e confirmações próprias.
- A live é um sistema de recuperação físico; o usuário temporário possui sudo sem senha, como
  o terminal root da mídia Archiso. Não habilite serviços de rede remotos desnecessariamente.
- O `--plan-only` tradicional permanece independente. No piloto VM, o Bash recebe
  o plano validado sem repetir seleção de disco, perfil ou usuário, mas pede a
  senha e confirmação final em terminal. O JSON por si só não autoriza alterações.
- Nesta fase, reparação GRUB/chroot guiada é apenas uma proposta; não executada.
- Não há garantia de aceleração ou suporte completo de todas as placas NVIDIA.

## Testar
- Preparar e compilar ISO normalmente; iniciar na VM via tests/wolf-vm.sh live uefi.
- Verificar tela Openbox, wallpaper, janela Wolf, QTerminal, PCManFM-Qt, GParted, internet, tty CLI.
- `sudo wolf-install --help` no terminal deve continuar funcionando.
- No hospedeiro `./tests/wolf-test-live-desktop.sh` testa staging sem bootar a ISO.

## Identidade do boot
- Os menus GRUB, Syslinux e loader são tematizados durante a preparação. IDs `archiso` e parâmetros técnicos permanecem intactos.
- Splash Wolf substitui a imagem Syslinux preexistente.

## Alpha21: teclado e rede

A primeira janela Qt seleciona o layout para a sessão Xorg (`setxkbmap`), com ABNT2 pré-selecionado. O Wi-Fi é controlado pelo NetworkManager: clique no ícone da rede no canto superior direito, que abre a lista de redes e os diálogos de senha via `nm-applet`. O botão Redes Wi-Fi da GUI também abre o editor para conexões avançadas. Nenhuma senha Wi-Fi é capturada, armazenada ou passada na linha de comando pelo Wolf Installer.

## Alpha22: ThinkPad brasileiro

Opção **Português (Brasil) — ThinkPad (IBM/Lenovo)** com variante XKB `br(thinkpad)`, aplicada apenas à sessão gráfica Live. ABNT2 segue como padrão.

## Alpha23: pré-plano JSON sem execução

A aba de revisão agora gera um JSON versionado, salva em diretório privado e oferece validação pelo backend CLI `--review-gui-plan`. A validação utiliza `lsblk` atualizado para impedir aceitar um disco removido/trocado. Este comando não executa a instalação, não monta e não formata. O modo `--plan-only` tradicional continua independente.

## Alpha24: /home e simulação Bash

A opção `/home dentro da raiz /` deixa a partição home desmarcada no JSON e utiliza `home_layout=in-root`. Em `home_layout=separate`, é necessário selecionar a partição correspondente; a validação apontará a ausência.

O modo **reutilizar** corresponde ao backend Bash `reuse-manual`, que formata raiz ext4, preserva EFI e não formata /home. Opções divergentes são sinalizadas como bloqueios na simulação. Em **manual**, o motor Bash atual pressupõe a montagem de `/mnt` preparada no terminal; a GUI oferece GParted e o inventário, mas não realiza essas montagens.

O botão **Simular etapas do backend Bash** utiliza `wolf-install --simulate-gui-plan`, que nunca entra no fluxo de instalação. O documento é `wolf.install.preview.v2`, com `execution=disabled`. Esta etapa NÃO habilita execução real.


## Ajustes de segurança e acessibilidade da alpha25

- O `/home` *dentro da raiz* apaga a seleção de partição `/home` e a marcação de formatação associada (não só ignora no plano).
- As caixas de intenção de formatação da raiz, EFI e `/home` começam **desmarcadas**, exigem uma partição definida e solicitam confirmação de perda de dados ao serem marcadas. Recusar a confirmação desfaz a marcação.
- Trocar a partição selecionada ou voltar ao modo de apagar o disco desmarca consentimentos prévios de formatação, evitando herança silenciosa.
- A aba **Revisar pré-plano** quebra linhas do resumo e do texto informativo sem impor rolagem horizontal.
- A simulação sinaliza que a reutilização pelo Bash **exige formatação ext4 da raiz**; manter a caixa desmarcada NÃO significa que a instalação não irá formatar a raiz.
- O contrato JSON continua `wolf.install.preview.v2`, com `execution=disabled`. Na alpha25 nenhuma operação executável havia sido adicionada.


## GUI 0.7 / Wolf alpha27 — piloto de instalação REAL em VM

O JSON mantém `wolf.install.preview.v2` e `execution=disabled`: não carrega
permissão de escrita. A execução é uma ação adicional, intencional e interativa.

- `sudo wolf-install --preflight-gui-plan-vm preview.json`: somente validação.
- `sudo wolf-install --execute-gui-plan-vm preview.json`: execução SOMENTE
  detectando QEMU/KVM, em disco VirtIO novo `/dev/vd[a-z]`, sem partições nem
  assinaturas, não removível, com 32 GiB ou mais e sem montagens.
- Confirmação final: o operador digita **APAGAR /dev/vdX** no terminal.
- A senha do usuário continua a ser solicitada pelo Bash de forma interativa,
  sem ser gravada no JSON ou no log.
- O engine revalida o disco antes de executar `wipefs` e verifica a ausência
  de checkpoints anteriores e de montagem em `/mnt`.
- Não habilita execução de reuso de partições, Windows, ESP existente, /home
  separado, manual, disco USB, SCSI/SATA, NVMe ou instalação em hardware real.
- Validar inicialmente com VM recém-criada e disco virtual de uso descartável.
- Os comandos tradicionais `wolf-install --vm-install` e `--install` continuam
  disponíveis de modo independente. Não os utilizar no piloto GUI.

## Alpha32: integração BIOS e console de instalação

- **Instalação em VM**: apagar disco inteiro em UEFI/GPT ou BIOS/MBR; manual e reutilização em UEFI/GPT ou BIOS/MBR.
- BIOS/MBR dispensa completamente a ESP e instala GRUB i386-pc no disco VirtIO. BIOS/GPT com `bios_grub` ainda NÃO é suportado no manual/reutilizar.
- **Aba Instalação**: pseudoterminal (PTY), com interações no próprio Wolf Installer; saída contínua, entradas e senhas (entrada oculta por padrão), arquivo de log 0600. Sucesso mostrado exclusivamente quando Bash retorna código 0. Falhas deixam saída e logs disponíveis. Não é emulador xterm completo: sequências ANSI são filtradas.
- **Diagnóstico da topologia**: `wolf-live-storage-topology` lista SSDs, partições e LVM em modo leitura. Não ativa VGs, não monta nem altera dados.
- Hardware físico e casos multidisco (EFI num SSD, `/` em outro, `/home` em LV) **não são suportados para execução GUI**. Estão registrados como requisito futuro de segurança.


## Alpha36: arquivos via PCManFM-Qt, diagnóstico de horário

- Removido Wolf Mount Manager do menu e da ISO. Partições são exibidas em **Dispositivos** no PCManFM-Qt. O usuário `wolf` usa GVfs/UDisks2 e Polkit para montar **por clique**, sem executar a GUI como root.
- Montagens podem permitir leitura e escrita se o filesystem estiver íntegro e permitir acesso. Não há automontagem. Para arquivos críticos (EFI, Windows, LVM multidisco) prefira copiar antes de editar; partições do Ventoy e volumes em uso não devem ser remontados/alterados.
- A autorização da Live cobre apenas montagem de arquivos (UDisk2 `filesystem-mount` e `filesystem-mount-system`) por usuário `wolf` com sessão local ativa; não autoriza partição/formatação.
- Firefox mantido. `systemd-timesyncd` ativo na Live e atalho **Conferir hora / NTP**. Código de verificação TOTP requer hora sincronizada; mudar timezone não corrige desvio do relógio. Suporte a passkeys de celular no Firefox Linux não é garantido por Bluetooth.
- A instalação em hardware físico, LVM multidisco e o Wolf Rescue continuam **não implementados/não liberados**.

## Alpha37 — Chromium, Bluetooth e Wolf Rescue (somente leitura)
- Chromium no lugar do Firefox **somente na ISO Live**; iniciar como usuário normal, sandbox mantido. O suporte efetivo a passkeys híbridas deve ser testado no hardware e não é garantido por Bluetooth.
- BlueZ, blueman-applet/manager, rfkill e bluetooth.service na Live; sem inclusão em stacks KDE.
- Wolf Rescue 0.1: relatório apenas diagnóstico de EFI/BIOS, discos, LVM, entradas UEFI, mountpoints e serviços. **Não executa chroot, fsck, mkfs, grub-install, mount nem reparação**.
- A execução de instalação gráfica continua **exclusiva de VM**, especialmente porque o LV vg_monstro/lv_projetos depende de PVs em dois NVMe. Atribuir /home exige verificar fstab, não inferir pelo nome do LV.

## Alpha38 — refinamento visual e mapa de armazenamento

- Wolf Rescue 0.2 usa tema Qt Fusion escuro com contraste e duas abas: relatório e mapa de volumes.
- Escolha um arquivo `etc/fstab` já acessível no PCManFM-Qt; os UUIDs são verificados contra o inventário atual via `lsblk -J`.
- Os PVs de um mesmo LV em discos diferentes são agregados e os riscos do multidisco são sinalizados.
- O Wolf Installer GUI 1.8 ajusta-se à resolução disponível, sem barra horizontal nas páginas.
- O mapa, o diagnóstico e o instalador não liberam a instalação física nem escrevem em partições.
