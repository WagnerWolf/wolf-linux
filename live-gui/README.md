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
