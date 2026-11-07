## Wolf Linux 2.2.0 — Picom integrado à release (02/11/2026)
- Perfil LXQt/Openbox X11: Picom GLX/VSync ativado por padrão no login.
- Wolf-dark: fundo opaco dos painéis preservado ao reaplicar o tema.
- Instalações com /home reutilizada preservam configuração e autostart Picom existentes.
- Teste específico de regressão com configuração, autostart, tema e backups.
- Não altera o kernel, a NVIDIA, o Chrome nem a biblioteca USB personalizada.

## 2.2.0 — Consolidação da integração USB (2026-11-02)

- Menu USB exclusivo do dispositivo, formato --device e migração da ação antiga de pastas.
- Painéis Fix5, tema Qt Fusion e GTK e indicador USB pt_BR consolidados.
- Central Wolf e Package Manager: auditoria, aviso pós atualização e bloqueio de ISO sem biblioteca customizada.
- Compilação `libfm-qt 2.4.0-4.1` validada em hardware pelo usuário; nova ISO pendente.

## 2.2.0 Fix6 — Correções LXQt em validação

- Fix5/QSettings integrado aos painéis do Wolf Control Center.
- Bandeja Wolf de dispositivos USB com textos pt_BR, substituindo menu inglês do Udiskie.
- Formatador USB integrado ao contexto de pastas montadas no PCManFM-Qt, menu e bandeja.
- Wolf-dark restaurável e configuração Breeze-Dark para GTK/XSETTINGS.
- Smoke test ampliado com simulações seguras e regressões LVM.

## 2.2.0 — Fix3 experimental (pendente de validação física)
- Reparação forçada de painéis com diagnóstico XRandR / Qt; sem watcher.
- União recursiva e não destrutiva dos diretórios XDG em português, com status explícito para colisões.
- Tema Wolf-dark com integração Breeze-Dark para GTK/Blueman.
- Formatador próprio USB: seleção de sistema de arquivos, confirmação dupla e chamada ao UDisks2; preservada ferramenta GNOME Disks avançada.
- Inicialização do Udiskie com preferência pt_BR, condicionada à tradução instalada.

## 02/11/2026 — Consolidação de release 2.2.0 / Wolf Package Manager 0.3.7

- Promovida a prévia 0.3.7 após confirmação do usuário em VM: biblioteca USB `2.4.0-4.1`, `IgnorePkg`, comando `wolf-libfm-guard` e auditoria de integrações.
- Identificador de versão da interface e do módulo Python atualizado de `0.3.7-vm-preview` para `0.3.7`; mantida a identidade Wolf Linux `2.2.0`.
- Sem mudanças no instalador de disco, kernels, boot, perfis e lógica de proteção validada.
- O pacote binário personalizado continua externo e obrigatório para gerar a ISO; sem recompilação automática ou transações em hooks.
- A ISO consolidada e a reinstalação em hardware físico não foram executadas neste ambiente.

## Wolf Linux 2.2.0 — 01/11/2026 (release LXQt/X11 homologada em VM)

- Promovida a RC1 Patch 6 após validação de instalação e uso em máquina virtual pelo mantenedor.
- Sem alterações funcionais no instalador, particionamento, gerenciamento de monitores, rede, aplicativos ou pacotes da RC1 Patch 6.
- Atualizados `VERSION`, `os-release` da Live e do sistema instalado, cabeçalhos, gerador ISO, testes e notas da versão.
- PCManFM-Qt padrão; painel/tray e locais corrigidos; kernel Arch oficial `linux` principal + `linux-lts` reserva.
- Instalação física desta versão ainda pendente de homologação.

### 23/10/2026 — Correção do smoke test da versão estável (reempacotamento)

- O teste de promoção estável reconhece os dois layouts: DevKit distribuído, com `gerar-iso-2.1.3.sh` e `branding-assets`; e projeto preparado, com `tests/wolf-build-iso.sh` e `assets`.
- Evita `FileNotFoundError` ao executar o smoke test a partir de `~/wolf-linux`; mantém a verificação efetiva do fallback Powerlevel10k.
- Sem alterações no kernel, particionamento, GRUB, perfis de aplicativos, Package Manager ou lógica de instalação já validada na RC5.

## Wolf Linux 2.1.3 — 23/10/2026 (versão estável)

- Promovida a base 2.1.3-rc5 após confirmação de instalação validada pelo mantenedor.
- Preservado o fluxo CachyOS principal + LTS reserva, fallback seguro Chaotic-AUR, Powerlevel10k opcional e Wolf Package Manager 0.3.4 (atalho no tray).
- Revisados `VERSION`, instalador, `os-release` da Live e do destino, preparador, script de build e documentação. Sem alterações funcionais no particionamento ou na instalação da RC5.

## Wolf Linux 2.1.3-rc5 — 23/10/2026 (fallback Powerlevel10k após Chaotic-AUR indisponível)

- Powerlevel10k é opcional: sem acesso ao Chaotic/AUR, sua ausência não aborta a instalação.
- Perfil Zsh detecta o tema e aplica prompt simples quando ausente; preserva plugins instalados.
- Dependência opcional pendente registrada no log do Wolf Linux.
- Mantém Chaotic/CachyOS -> LTS fallback da RC3, e Package Manager 0.3.4 da RC2.

## Wolf Linux 2.1.3-rc2 — 23/10/2026 (candidata após validação da rc1)

- Wolf Package Manager 0.3.4: adiciona ação «Atualizar sistema (N)» ao menu de contexto da bandeja KDE, disponibilizada após consulta completa com atualizações.
- O atalho reutiliza o fluxo de confirmação, verificação db.lck, pacman -Syu e yay AUR sem elevar privilégios antecipadamente.
- Ação desabilitada em consulta parcial, com zero atualizações ou durante operação em andamento. Testes estáticos/unitários não destrutivos adicionados.
- Mantidos o kernel linux-cachyos principal, linux-lts reserva, GRUB, NVIDIA DKMS e proteções de armazenamento validados na rc1.
- UI da bandeja e ISO ainda aguardam validação prática no Arch/Wayland.

## Wolf Linux 2.1.3-rc1 — 22/10/2026 (código; ISO ainda pendente de build/VM)

- Substitui linux-zen por linux-cachyos (Chaotic-AUR) como principal e
  linux-lts oficial como reserva obrigatória em todos os perfis.
- Configuração Chaotic-AUR obrigatória também em Minimal; o pacstrap inicial
  preserva a possibilidade de instalar LTS antes do Chaotic.
- NVIDIA open DKMS para ambas as árvores de módulos, com validação fail-closed.
- GRUB_DEFAULT=0 + GRUB_TOP_LEVEL CachyOS, mantendo os dois initramfs.
- Testes de regressão e ensaio físico atualizados para os novos estágios.
- Sem alterações nas regras de EFI, /home LVM, dotfiles, Baloo ou UI KDE.

## Wolf Linux 2.1.2 — release (16/10/2026)

- Promovida a 2.1.2-rc1 SmokeFix2 após validação da instalação Basic em VM relatada pelo usuário; nenhuma mudança de armazenamento/GRUB/EFI.
- Wolf Package Manager 0.3.3: controle de retorno de cursor, barra de progresso incremental no terminal Qt, UTF-8/ANSI por blocos, log preservado; 51 testes upstream.
- Kernels e módulos NVIDIA permanecem inalterados aguardando análise da falha de boot Zen. Plasma 6.8.0 multimonitor permanece upstream.

## 2.1.2-rc1 — SmokeFix 2 (16/10/2026)

- Corrige uma falha de execução da etapa 64 (`install_selected_stack_packages`): as funções de coleta podiam terminar com código 1 quando a última stack não estava selecionada. Sob `set -Eeuo pipefail` e o `ERR trap`, o diagnóstico "FALHA NA INSTALAÇÃO" era escrito no stdout da substituição de processo e passava a ser interpretado como nomes de pacotes AUR.
- As três funções de coleta agora retornam sucesso explicitamente (`return 0`) e usam ramificações `if` sem falso erro ao consultar uma stack não selecionada.
- O resolvedor rejeita qualquer nome de pacote incompatível com o formato esperado antes de executar `pacman` ou `yay`, protegendo todos os perfis.
- Novo teste funcional `wolf-test-aur-stdout-2.1.2.py`, integrado ao smoke test; usa um Bash `ERR trap` real com comandos `pacman/yay` simulados e executa perfis Minimal, Basic, Test e Full sem operações de instalação.
- Sem mudanças no particionamento, bootloader, UI Qt ou regras de permissões do /home.

### 2.1.2-rc1 SmokeFix 1 — ShellCheck
- Documentada expansão deliberada de variáveis pelo `/bin/sh` dentro do `arch-chroot`, suprimindo SC2016 somente no teste de escrita do cache.
- Nenhuma alteração na lógica do instalador.

## 2.1.2-rc1 — Basic, ferramentas auxiliares e propriedade do cache
- Adicionado perfil Basic (Daily reduzida) sem stacks Gaming/Development.
- GIMP, OBS Studio e Transmission movidos para Extras, mantendo Test/Full.
- Correção dos nomes invisíveis na lista de ferramentas da sessão Live.
- Criação segura de ~/.cache como usuário; proteção contra diretórios de outros UID, links e teste real de escrita.
- Testes de regressão de perfil, UI, cache, multidisco/LVM e terminal.

### SmokeFix 2 (Live GUI, 2.1.1)
- Corrige importação Qt fatal do QTextCursor e adiciona teste funcional pós-mkarchiso no ambiente da Live.
- Captura erros de inicialização automática em log.

### Correção de empacotamento — smoke test 2.1.1 (2026-10-16)

- Isolado o teste do Wolf Control Center do autostart global já instalado na máquina do mantenedor.
- Adicionados cenários para autostart ausente, autostart global ativo e prioridade da desativação por usuário.
- Comportamento do Control Center e da instalação preservado; sem alterações em particionamento, LVM, EFI, boot ou pacotes.
- Smoke test executado novamente com código de saída 0 no ambiente de validação; compilação da ISO ainda deve ser validada no Arch Linux.

## 2.1.1 — lançamento estável (2026-10-15)

- Promovida a RC2 após instalação física e boot bem-sucedidos com EFI e raiz em NVMe distintos e `/home` LVM multidisco preservado.
- Mantida a correção do terminal PTY para progresso `\r` do pacman.
- Instalado override systemd exclusivo do Baloo (`QT_QPA_PLATFORM=offscreen`) após validação sem novos crashes depois do reboot.
- Wolf Package Manager atualizado de 0.3.1 para 0.3.2, com revisão da consistência da verificação de atualizações.
- Identificação de versão, Live, sistema instalado e documentação padronizadas para 2.1.1.
- Sem alterações funcionais nas rotinas de particionamento, formatação, GRUB e seleção de GPU.

# Changelog — Wolf Linux DevKit

## 2.1.0 — lançamento estável (2026-10-15)

- Promovida a 2.1.0-rc1 validada pelo mantenedor, sem alterações funcionais no instalador, particionamento ou boot.
- Identidade de versão padronizada no DevKit, Live e sistema instalado; documentação oficial atualizada.
- Inclui Wolf Package Manager 0.3.1 em substituição ao Octopi, com autostart na bandeja e integração ao Control Center.

## 2.1.0-rc1 — prévia (2026-10-15)

- Substitui Octopi por Wolf Package Manager 0.3.1.
- Autostart KDE, Control Center, dependências pacman-contrib e yay.
- Teste da ISO/instalação ainda pendente.

## 2.0.0 — lançamento final (2026-10-14)

- Promovida a base alpha59 para a versão 2.0.0 após testes práticos de instalação e inicialização UEFI informados pelo mantenedor.
- Padronização de `VERSION`, versão de reserva do instalador, identidade `/etc/os-release`, identificação da Live e documentação pública.
- Interface gráfica única com teclado primeiro, três modos de armazenamento, escolha obrigatória de perfil, revisão e confirmações por clique, terminal integrado.
- Tratamento de dependências opcionais, prévia de dotfiles e provisão seletiva de Vulkan conforme o hardware foram consolidados na linha alpha56–alpha59.
- Preservadas as proteções de disco, o executor Bash, as verificações de GRUB/EFI e os testes históricos.
- Arquivada documentação de desenvolvimento das versões alpha em `docs/historico-alphas/`.

Nenhuma nova lógica de particionamento, formatação, GPU ou GRUB foi introduzida nesta promoção de versão.

Histórico detalhado: `docs/historico-alphas/CHANGELOG-alpha59.md` e os arquivos de revisões anteriores.

## 2.1.1-rc1 — 2026-10-15

- Compatibilidade de planejamento/executor com UEFI e raiz em discos distintos e /home LVM ext4 preservada; prévia de dotfiles em LVM.
- Candidato de homologação física: não promover até testes reais.

## 2.1.1-rc2 — 2026-10-15

- Corrigida visualização incremental do terminal PTY do instalador gráfico: retornos de cursor sobrescrevem apenas a linha ativa, sem repetir quadros de progresso do pacman.
- Mantidos o log de instalação, entrada interativa, proteções de disco e comportamento do executor da 2.1.1-rc1.
- Acrescentados testes de fragmentação de saída, CRLF, progresso e staging da Live.

### 2.2.0 Fix7 — NTFS / GTK XSETTINGS (experimental)
- Formatador USB Wolf: NTFS disponível com `ntfs-3g`/UDisks2 e rótulos NTFS validados.
- `wolf-gtk-xsettings`: inicia XSETTINGS com o arquivo Wolf explicitamente, sem depender da precedência de `~/.xsettingsd`.
- Control Center / Wolf-dark: agora recarrega o daemon Wolf, inicia o daemon quando ausente, identifica conflitos e expõe diagnóstico do tema efetivamente publicado.
- Fix7 preparado para testes físicos; base 2.2.0 estável preservada.

## Experimental · Integrações Wolf Preview 4 (libfm-qt)
- O Fusion validado no LXQt foi mantido.
- Adicionado preparador de PKGBUILD experimental para libfm-qt **exatamente** 2.4.0-4, com `pkgrel=4.1` e patch do menu de dispositivos.
- Verificação obrigatória da tag Git 2.4.0, arquivo fonte limpo, `git apply --check`, formato da receita oficial, checksum SHA512 e destino novo.
- Nenhuma compilação ou instalação automática; pacote, ABI e integração gráfica ainda NÃO validados.
- Regressão automatizada da preparação usando fonte/repositório Git simulados e receita simulada.
