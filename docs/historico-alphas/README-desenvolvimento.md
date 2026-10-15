# Wolf Linux DevKit 2.0.0-alpha59 — correção da validação Vulkan

A alpha58 introduziu a etapa `63b-vulkan` no instalador, mas o catálogo do ensaio físico não a reconhecia. A alpha59 corrige o contrato estrito e mantém o bloqueio a etapas desconhecidas. Atualiza ainda as listas de versões aceitas pelos testes de regressão. **Não altera o executor de formatação ou boot**. Consulte `CHANGELOG-alpha59.md`.

Para validar: `bash tests/wolf-smoke-test.sh`. As notas das versões anteriores abaixo são históricas e podem descrever limitações posteriormente superadas.

---

# Alpha56 — atualização da interface

Consulte `CHANGELOG-alpha57.md` para a correção do smoke test e `CHANGELOG-alpha56.md` para detalhes das funcionalidades e limitações.

O instalador abre com o teclado ABNT2 aplicado, porém selecionável, e exige escolha explícita do perfil.
A nova interface aceita instalações físicas simples, mantendo verificações de segurança; o modo especializado multidisco/LVM do instalador clássico continua separado.

# Wolf Linux DevKit 2.0.0-alpha55 — interface com PTY integrado

A nova interface Live começa pelo **layout do teclado** (seleção e teste). Nenhuma modalidade de disco é pré-selecionada. Após escolher Apagar disco / Manual / Reutilizar, revisar o plano e aceitar **duas confirmações por clique**, o instalador Bash é executado **dentro da própria janela** pelo mesmo motor PTY do instalador clássico. Há área de logs, envio de respostas e indicação do código real de saída. O launcher da ISO agora permite `--execute-gui-plan-vm-click` (era a causa do erro “Opção desconhecida”).

**Nesta revisão, a nova interface executa somente na Live de VM QEMU/KVM/VirtualBox com disco VirtIO descartável.** As restrições de partições simples, mesmo disco e reutilização com `/home` separada da alpha53 permanecem; o instalador físico clássico homologado não foi alterado. Operações são destrutivas de verdade na VM. A limpeza de dotfiles é incluída nas duas confirmações e permanece protegida por prévia, comparação de listas e checagem da montagem pelo Bash.

Teste: `bash tests/wolf-test-alpha55.py` (ou `python3 tests/wolf-test-alpha55.py`) e `bash tests/wolf-build-iso.sh`. A sintaxe, o contrato de lançamento e a simulação interativa PTY passaram, mas a instalação real ainda precisa ser executada e homologada na VM.

---

# Wolf Linux DevKit 2.0.0-alpha54 — Correções da GUI na Live

Pré-validação de discos agora é executada como leitura privilegiada pelo comando Bash restrito a preflight; interface continua com usuário sem privilégios. Barra lateral maior e sem rolagem horizontal, etiquetas com fundo transparente. Consulte CHANGELOG-alpha54.md.

# Wolf Linux DevKit 2.0.0-alpha53 — Novo instalador integrado para homologação VM

A interface Live principal agora apresenta **Apagar disco inteiro**, **Particionamento manual** e **Reutilizar partições** ligados ao executor Bash para **execução REAL apenas em máquinas virtuais descartáveis QEMU/KVM/VirtualBox com disco VirtIO**. A seleção de teclado altera o teclado Live e define o layout do sistema instalado; usuário, hostname e perfil Minimal/Test/Full estão na barra lateral. O botão de revisão foi simplificado para **Confirmar**, mantendo dois diálogos de consentimento por clique. O Bash mantém suas verificações independentes antes de qualquer formatação.

**Não execute em hardware físico pela nova interface nesta etapa.** As modalidades manuais ainda aceitam apenas partições de um mesmo disco VirtIO (UEFI/GPT, BIOS/MBR) e requerem GParted para criar/redimensionar partições. O reaproveitamento exige `/home` separada e preservada. O backup de dotfiles neste executor VM não está disponível; a limpeza, quando ativada, ainda exige sua própria confirmação `LIMPAR`. O instalador clássico para hardware real/LVM continua disponível e não foi substituído.

Gerar ISO: `bash tests/wolf-build-iso.sh`. Testar os três modos somente em VM descartável. Consulte `CHANGELOG-alpha53.md`.

---

## Alpha52 — Interface Live integrada

A sessão Live inicia o novo planejador responsivo. A visualização dos modos **Apagar disco inteiro**, **Particionamento manual** e **Reutilizar partições** é somente leitura. Os dois diálogos de confirmação na interface nova **não executam** ações destrutivas nesta versão. O instalador clássico (alpha51 homologada) permanece disponível pelo botão lateral, pelo menu Openbox e pelo comando `wolf-live-installer-classic`, com validações próprias.

Para gerar a ISO no Arch Linux preparado: `bash tests/wolf-build-iso.sh` (após preparar o ambiente/perfil Archiso conforme as instruções existentes abaixo). Para testar a nova GUI na ISO, inicialize em uma VM e verifique layout e navegação nas resoluções 1024×768 e 1280×800 antes de testar instalações reais pelo instalador clássico.

## Wolf Linux DevKit 2.0.0-alpha51 — correção do smoke test para usuário comum

A **instalação física Full da alpha48 está homologada**; a rotina nova de limpeza da alpha50 ainda requer teste físico controlado. O executor continua exigindo Live UEFI, topologia multidisco detectada e revalidação da raiz/EFI/LVM.

Na aba **Partições**, após detectar `/home`, marque **Remover arquivos e pastas ocultos da raiz do usuário**. Abre-se uma **prévia somente leitura** com todas as entradas imediatamente dentro de `/home/USUARIO` cujos nomes começam por ponto (`.bashrc`, `.config`, `.local`, `.steam`, `.ssh` etc.). **Não há seleção uma a uma**. Um checkbox separado permite ativar backup, **desmarcado por padrão**. Depois, o terminal apresenta novamente a lista e exige digitar `LIMPAR` antes da formatação da raiz.

**Atenção:** essa opção apaga `.local` por completo e pode eliminar jogos da Steam, chaves SSH, perfis de navegadores e outras informações escondidas. Os arquivos e diretórios **visíveis** da pasta pessoal e a partição `/home` (incluindo o LVM) são preservados. Se **não marcar** a limpeza, a pasta pessoal fica integralmente intacta. Se pedir backup, ele será criado no próprio volume `/home/.wolf-linux-backups/` e consumirá espaço proporcional aos dados copiados.

**Não use a nova rotina com dados insubstituíveis sem backup independente.** Os testes automatizados verificam prévia, backups, proteção contra alterações e bloqueio de montagens, mas não substituem uma homologação real da limpeza. A restauração dos modos Apagar disco e Particionamento manual está reservada para o futuro refinamento da interface. Consulte `CHANGELOG-alpha50.md` e `CHANGELOG-alpha51.md`.

---


## Wolf Linux DevKit 2.0.0-alpha48 — instalação física multidisco protegida (PTY corrigido)

**Correção alpha48:** a Live agora autoriza `--execute-multidisk-physical`
no PTY integrado, após preflight e confirmações, sem liberar outros modos
arbitrários. A alpha47 tinha um bloqueio residual no PTY que impedia a GUI
de iniciar esse executor mesmo com plano válido. A correção não substitui a
validação em hardware real nem altera os procedimentos de partição do Bash.

Nesta revisão o executor **real em hardware** foi liberado **somente para o contrato
UEFI com raiz ext4 num NVMe, EFI FAT32 noutro NVMe, e /home ext4 em um LV LVM
com dois PVs**. A descoberta semiautomática usa UUID, PARTUUID, tipo GPT,
identidades e conteúdo atual do `fstab`. Os nomes `/dev/nvmeXnY` podem mudar.

A execução em **hardware real apaga a raiz**. EFI, /home LVM, PVs e demais
partições são preservados pelo plano; o GRUB escreve em `EFI/WolfLinux`, com
`--no-nvram` e sem instalar o fallback EFI. Não há garantia de boot antes de
um teste físico real. O modo não exige backup geral, mas recomenda um e exige
reconhecimento explícito da perda de todos os arquivos locais na raiz.

**Não utilizar o `--install` genérico nesse cenário**. Na Live alpha48, abra
Wolf Installer > Reutilizar > Detectar todos os discos > confirmar cada papel >
Revisão, execute validar/simular/ensaio e em seguida o botão de instalação
física protegida. O GUI pede a raiz exata; o Bash solicita duas confirmações.

Pré-teste CLI de leitura (sem escrever):

```bash
sudo wolf-install --preflight-multidisk-physical \
  /home/wolf/.local/state/wolf-linux/live-installer/preview.json
```

Executar instalação somente por decisão explícita do operador, após validar
volume de destino e conexão à internet. O `--execute-multidisk-physical` é
restrito ao perfil da Live e não aceita opções que alterem o plano.
O perfil Minimal é recomendado para a primeira instalação física, seguido das
stacks opcionais após o boot. Nunca executar `fsck` automaticamente nos PVs ou
volumes preservados.

---

> **alpha46:** ensaio físico integral somente leitura (`--rehearse-multidisk-physical`); executor físico continua bloqueado. Veja `docs/WOLF-ALPHA46-ENSAIO-FISICO.md`.

## Alpha34 — Dimensionamento seguro do particionamento automático (experimental VM)

- Em **Apagar TODO o disco**, selecione tamanhos de `/` e `/home` com barra e campo numérico sincronizados. O limite de cada campo vem da **capacidade real detectada do disco** pelo `lsblk`; ao trocar disco, firmware BIOS/UEFI ou modo de `/home`, os limites são recalculados.
- Em UEFI, reserva-se automaticamente 1 GiB para ESP FAT32; em BIOS/MBR não há ESP. A interface também reserva 1 GiB de folga técnica/alinhamento. `/home` separada exige raiz de pelo menos 20 GiB e `/home` de pelo menos 10 GiB.
- **0 = restante do disco**; no modo `/home` separada a raiz tem mínimo 20 GiB (portanto não aparece a descrição ambígua "restante"). Se os dois tamanhos forem fixos, pode sobrar espaço não particionado.
- A verificação do contrato JSON e o preflight independente Bash continuam obrigatórios: os controles gráficos não substituem a validação ao executar.
- **Primeira rodada em hardware físico: apenas boot da Live, diagnóstico e planejamento/simulação de leitura.** A execução pela GUI permanece **bloqueada** para `/dev/sdX`, `/dev/nvmeXnY`, LVM e topologia multidisco. Não usar o instalador Bash legado no armazenamento com dados apenas para contornar a restrição.
- EFI em um SSD, `/` em outro e `/home` em LVM ainda exigem implementação/homologação específica; os dispositivos podem ser identificados sem escrita pela ferramenta `wolf-live-storage-topology`.

## Alpha33 — Auto-particionamento configurável e BIOS reuse (experimental VM)

- Modo **Apagar disco**: `/home` integrada ou partição ext4 dedicada; raiz `/` em GiB (0 = restante); partição `/home` em GiB (0 = restante). **Escolher os dois tamanhos fixos pode deixar espaço não alocado**.
- UEFI: ESP FAT32 de **1 GiB fixo**. BIOS/MBR: **sem EFI**, aviso explícito em vermelho no instalador.
- Reutilização BIOS/MBR: elimina validação Bash residual que exigia UEFI; continua exigindo `/home` dedicada preservada, raiz formatada e ausência de EFI.
- Contrato JSON `wolf.install.preview.v4`, 19 campos exportados, com revalidação de layout e tamanhos antes de escrever no disco.
- **Somente execução em VM VirtIO**. Teste real de instalação alpha33 ainda pendente. Não habilita SSDs físicos, LVM ou UEFI/raiz em discos diferentes.

## alpha32 — BIOS/Legacy em VM, console integrado e diagnóstico multidisco/LVM

A Live GUI 1.2 implementa uma aba **Instalação** que utiliza um PTY para exibir a saída do Bash sem abrir outro terminal, solicitar entradas e senhas e informar sucesso somente com código de saída zero. O log fica em `~/.local/state/wolf-linux/live-installer/` com permissões privadas.

Em VM QEMU/KVM VirtIO, a GUI aceita **BIOS/MBR sem EFI** para apagar disco, particionamento manual e reutilização com `/home` dedicada. BIOS/GPT com `bios_grub` continua bloqueado no manual/reutilizar; UEFI/GPT e os caminhos aprovados da alpha31 permanecem. O diagnóstico `wolf-live-storage-topology` identifica múltiplos discos e LVM sem qualquer alteração.

**NÃO é versão liberada para hardware físico.** O caso EFI em um SSD + raiz em outro + `/home` dentro de LVM exige contrato próprio com escolha independente de discos, PV/VG/LV, detecção e validação antes de qualquer operação destrutiva. Ver [CHANGELOG-alpha32.md](CHANGELOG-alpha32.md).

## alpha31 — piloto de reutilização de EFI e /home em VM UEFI

A GUI 1.1 permite reinstalar o sistema **formatando exclusivamente a raiz /**, preservando as partições EFI (FAT32) e `/home` (ext4, dedicada). Opcionalmente permite remover arquivos e pastas ocultos diretamente em cada diretório de usuário da home, mostrando uma prévia e exigindo `LIMPAR` antes da formatação. Arquivos ocultos podem conter credenciais e dados importantes. Faça backup.

**Use uma CÓPIA da VM alpha30 desligada.** O sistema deve ter `/home` em partição separada para preservá-la. Reutilização de `/home` integrada à raiz é proibida neste piloto. Somente QEMU/KVM + VirtIO + UEFI; instalação em hardware físico continua bloqueada.

Detalhes: [CHANGELOG-alpha31.md](CHANGELOG-alpha31.md) e [docs/WOLF-GUI-PLAN-CONTRACT.md](docs/WOLF-GUI-PLAN-CONTRACT.md).

## alpha29 — piloto de particionamento manual em VM UEFI

- **Instalação manual gráfica experimental:** após preparar as partições no GParted, escolha raiz `/` (formatada em ext4), EFI FAT32 com flag GPT `esp` (preservada), e `/home` opcional (preservada). Somente em VM QEMU/KVM com disco VirtIO e boot UEFI. Não usar em hardware real.
- **Apagar disco inteiro** agora funciona mesmo com partições preexistentes, se não estiverem montadas ou em uso. `/home` fica dentro de `/` e nenhuma partição `/home` separada é criada.
- Confirmação curta `APAGAR` na GUI e no terminal; o resumo mostra os dispositivos e a extensão da perda de dados.
- `Minimal` não deve gerar chamada AUR vazia: o resolvedor filtra entradas em branco e há autoteste específico. O erro informado anteriormente ainda exige validação em instalação real.
- **Reutilizar partições existentes** continua no planejamento/simulação. Primeiro validar a preservação dos dados no modo manual.
- Instruções e limitações completas: [CHANGELOG-alpha29.md](CHANGELOG-alpha29.md).

## alpha28 — conclusão gráfica após instalar com sucesso

- Após a instalação real no QTerminal, pressione Enter para fechar o terminal. Somente se o instalador Bash terminou com código zero, a GUI exibe **Wolf Linux instalado com sucesso** e oferece **Reiniciar agora** ou **Continuar na Live**.
- A janela principal é fechada depois da decisão; a reinicialização nunca é automática e requer clique explícito.
- Em falhas o terminal informa o erro e a GUI NÃO exibe sucesso. O resultado é transmitido por um marcador privado da execução, não pelo fechamento do QTerminal.
- A mídia ISO deverá ser ejetada ou o disco instalado selecionado no boot após reiniciar.
- Motor Bash, partições, pacotes e desktops não foram alterados nesta revisão.
- A instalação completa da alpha27 foi validada pelo usuário; o encerramento gráfico da alpha28 ainda requer teste na VM.

## Alpha24 — simulação guiada e seleção explícita de /home

- Wolf Installer GUI 0.5.1. Inclui confirmação explícita para intenções de formatação, aviso persistente de perda de dados, limpeza da seleção anterior de `/home` e quebra de linhas na revisão. `/home` pode ficar como diretório dentro de `/` (padrão, sem partição dedicada) ou em partição própria.
- Novos controles de GParted e explicações dos modos **reutilizar** e **manual**. O manual Bash ainda exige preparar/montar `/mnt` externamente.
- Contrato JSON `wolf.install.preview.v2`, `execution=disabled`, verificado contra `lsblk` novo.
- `sudo wolf-install --simulate-gui-plan /caminho/preview.json`: simulação declarativa; relata bloqueios reais do backend, não chama a rotina `main` e não executa particionamento, mounts, formatadores nem pacman.
- A GUI pode validar ou simular o mesmo documento JSON. Não executa a instalação. GParted é uma ferramenta separada e *pode* escrever alterações se confirmado pelo operador.
- Alpha18 estável e alpha22 aprovada não são modificadas.

## Alpha23 — Contrato de pré-planejamento GUI ⇄ Bash (somente leitura)

- A interface gera um documento JSON versionado com disco, partições, flags de intenção de formatação, teclado, identidade e stacks.
- O botão **Validar plano JSON no backend** encaminha a escolha ao Bash via `wolf-install --review-gui-plan`, com verificação independente do inventário atual.
- O arquivo é privado no usuário Live e **não autoriza instalação ou formatação**.
- A linha alpha18 permanece congelada; desenvolva em diretório separado.
- Detalhes: `docs/WOLF-GUI-PLAN-CONTRACT.md`.

## alpha22 — layout brasileiro ThinkPad na Live

- Nova opção **Português (Brasil) — ThinkPad (IBM/Lenovo)** no seletor de teclado inicial.
- Usa a variante XKB oficial `br(thinkpad)` (`setxkbmap -model abnt2 -layout br -variant thinkpad`), para tratar o posicionamento de `/` e `?` em ThinkPads brasileiros.
- **ABNT2 continua sendo a seleção padrão**, sem alterações para outros teclados.
- O mesmo layout pode ser escolhido novamente por *Alterar layout do teclado* na GUI.
- Mantida a política de pré-planejamento somente de leitura; nenhuma operação de instalação destrutiva pela GUI.

## alpha21 — usabilidade da Live gráfica

- Seletor inicial do teclado Xorg (`xorg-setxkbmap`), com ABNT2 por padrão e campo de teste; aparece antes da janela principal do instalador.
- Resumo de pré-planejamento atualizado automaticamente após mudanças; botão redundante removido.
- GParted renomeado para **GParted — Particionador**.
- Wi-Fi gráfico via NetworkManager (`nm-applet` e `stalonetray`), com ícone na bandeja superior direita e editor de conexões para configuração avançada.
- NetworkManager ativo na Live para evitar conflito com o serviço iwd independente. Nenhuma dessas dependências entra na instalação KDE.
- A interface ainda não executa instalação, formatação ou reparação destrutiva.

## alpha20 — pré-planejamento gráfico e identidade da Live

- Wolf Live GUI 0.2 exibe inventário real de discos, partições, perfis, stacks e um pré-plano não executável.
- O botão de planejamento Bash abre `wolf-install --plan-only` em um terminal para confirmação independente; escolhas da GUI não são transmitidas ao backend nesta versão.
- Branding de entradas de boot (GRUB/Syslinux/loader), identidade do login e splash Syslinux.
- Não executa formatação ou instalação pela interface gráfica.

# Wolf Linux DevKit 2.0.0-alpha29

Baseline **KDE Plasma / Wayland** com preparação limpa, helpers completos porém
**Branding/MultiMonitor automáticos uma vez no primeiro login**, demais helpers manuais,
validação guiada e VM persistente fácil de retomar.

## Fluxo recomendado

Preserve a baseline estável e prepare uma árvore separada:

```bash
chmod +x preparar_ambiente_wolf_linux.sh
./preparar_ambiente_wolf_linux.sh --project "$HOME/wolf-linux-alpha29"
```

O preparador parte de `/usr/share/archiso/configs/releng`, recria
`~/wolf-linux`, customiza a ISO, faz staging do SSH live e roda o smoke test.

## Build

```bash
cd ~/wolf-linux-alpha29
./tests/wolf-build-iso.sh
```

A ISO live oferece:

```bash
wolf-enable-ssh-live
wolf-ssh
```

## VM: comandos seguros

Use o novo gerenciador para evitar apagar a instalação sem querer:

```bash
./tests/wolf-vm.sh status
./tests/wolf-vm.sh fresh uefi      # APAGA/recria o disco e boota a ISO
./tests/wolf-vm.sh live uefi       # preserva o disco, ISO conectada
./tests/wolf-vm.sh installed uefi  # SOMENTE o sistema já instalado
./tests/wolf-vm.sh ssh
```

`wolf-run-arch-test.sh` continua sendo um atalho para teste **fresh**. Para
retomar uma VM instalada use `wolf-vm.sh installed`.

## Presets

```bash
wolf-install --full
wolf-install --test
wolf-install --minimal
wolf-install --list-stacks
```

Pacotes seguem a prioridade:

1. repositórios oficiais Arch;
2. Chaotic-AUR;
3. AUR direto somente como fallback.

## Helpers

Após a instalação:

```bash
wolf-helper list
wolf-helper validate
```

Branding e MultiMonitor são aplicados apenas no **primeiro login KDE** do usuário criado
pelo instalador, nesta ordem, com registro em
`~/.local/state/wolf-linux/first-login-plasma/setup.log`.
Após sucesso, o lançador por usuário é removido e um marcador `completed` é criado.
Se o Plasma ainda não estiver pronto, haverá nova tentativa no próximo login.
Gamepad e GRUB Manager permanecem manuais. Não são criados serviços, timers ou
watchers Wolf permanentes.

### Stable

- `wolf-grub-manager-0.3.sh`
- `wolf-gamepad-setup-0.3.sh`

### Experimental

- `wolf-plasma-branding-0.2.sh`
- `wolf-plasma-multimonitor-0.3.sh`

O Branding 0.2 também pode ser executado manualmente para reconfigurar:

- Breeze Dark;
- Papirus-Dark;
- wallpaper Wolf Linux;
- ícone dedicado do Kickoff, sem a margem/texto da arte do Plymouth;
- backup + `restore`.

O MultiMonitor 0.3 é **one-shot**. Não existe daemon/polling Wolf permanente;
hotplug continua sob responsabilidade do Plasma/KScreen.

## Validação guiada

`wolf-helper validate` executa uma sequência manual:

1. baseline KDE/Wayland;
2. branding;
3. MultiMonitor;
4. gamepad;
5. GRUB Manager.

Entre etapas o script pausa e pede `PASS`, `FAIL`, `SKIP` ou rollback quando
suportado. O relatório fica em:

```text
~/.local/state/wolf-linux/helper-validation/
```

Na VM, Gamepad e multimonitor físico podem ser pulados; no hardware real o
mesmo script serve para concluir a validação.

## Política 2.0

- desktop único: KDE Plasma;
- sessão preferida: Wayland;
- XWayland para compatibilidade;
- helpers presentes, mas sem execução automática;
- sem polling periódico Wolf quando a plataforma já oferece mecanismo nativo;
- UEFI e BIOS/Legacy suportados;
- `full` para instalação pessoal completa e `test` para ciclos rápidos em VM.


### Atualização alpha11: ícone Kickoff SVG personalizado

A versão é lida do arquivo `VERSION` no DevKit e propagada para
`~/wolf-linux/VERSION`, `/root/wolf-linux/VERSION` na live e
`/etc/wolf-linux-live-build`. A etapa 7 compara o conteúdo byte a byte e
mostra o valor encontrado/esperado se houver divergência.

O ícone específico do Kickoff **não** é o logo genérico do sistema:
`branding-assets/kde/wolf-linux-kickoff.svg` (SVG original fornecido pelo usuário). O instalador
o transporta para `/usr/share/icons/hicolor/scalable/apps/wolf-linux-kickoff.svg`
e o helper `wolf-plasma-branding-0.2.sh` o aplica *manualmente* no Plasma.
O arquivo principal é `wolf-linux-kickoff.svg`. O PNG anterior, rejeitado na alpha10,
foi retirado do pacote para evitar confusão. A nova arte foi integrada sem alterações.
Na alpha12, o SVG foi substituído pela segunda arte `newwolf-linux-kickoff.svg`
fornecida pelo usuário, preservada byte a byte. Como esse SVG incorpora uma imagem
PNG raster embutida, a vetorização real fica para revisão futura; não é necessário
alterar o arquivo para testar sua aparência no Plasma.

**Atenção:** o preparador recria o diretório `~/wolf-linux` quando
confirmado ou com `--force`. Antes de reconstruir, faça backup das
imagens em `~/wolf-linux/vm/` que desejar preservar.


### Alpha12: Plasma sem Discover, Kickoff preservado

- O `plasma-meta` foi substituído pelo conjunto de dependências explícitas
  (menos `discover`), porque o meta puxa Discover obrigatoriamente.
- O estágio `69c2-painel-sem-discover` confirma a ausência do pacote e elimina
  os URLs do Discover dos launchers do layout padrão do Plasma; sem autostart Wolf.
- O helper MultiMonitor 0.3.1 **não modifica o ícone dos Kickoffs existentes**;
  painéis novos herdam o ícone atual do usuário, ou usam o SVG Wolf como fallback.
- A alpha11 passou na VM segundo a validação do usuário; a alpha12 precisa ser
  testada na VM com `pacman -Q discover` e os dois helpers.


### Alpha13 — Preferências pessoais KDE + Zsh/Konsole

Preferências aplicadas **uma vez na instalação** (sem watchers/autostart):

- KWin Alt+Tab: apenas janelas do monitor sob o mouse (`MultiScreenMode=1`);
- KWin posicionamento de novas janelas `UnderMouse`;
- mouse com perfil libinput *flat*, sem aceleração (confirmar dispositivos no hardware);
- Dolphin exclusivo para `inode/directory`;
- KWrite para arquivos de texto, logs, Markdown e JSON; Okular para PDF;
- stack Daily: MPC-QT para vídeos, Audacious para áudio, LibreOffice só Office, Chrome para web;
- stack Development: menu de contexto do Dolphin *Abrir pasta no Visual Studio Code*;
- Konsole estilo XFCE de referência: fundo preto, texto branco, MesloLGS 11, 120x30, histórico de 10 mil linhas;
- stack Daily: `.zshrc`, `.p10k.zsh`, Fastfetch originais fornecidos pelo usuário; Oh My Zsh + P10k;
- Gaming: sem MangoHud, Gamescope ou GOverlay.

Ajustes do Plasma são gravados antes do primeiro login do usuário, sem reinício
ou mudança permanente da configuração de um sistema já instalado.
O MultiMonitor continua como helper manual, não aplica políticas de hotplug extras.

Validação pós-instalação:

```bash
kreadconfig6 --file kwinrc --group TabBox --key MultiScreenMode
kreadconfig6 --file kwinrc --group Windows --key Placement
kreadconfig6 --file kcminputrc --group Libinput --group Defaults --key PointerAccelerationProfile
xdg-mime query default inode/directory
xdg-mime query default video/mp4
xdg-mime query default text/plain
echo "$SHELL"
```

### Alpha14 — Correção de disponibilidade do pacote KWrite

- Retirado `kwrite` de `KDE_PACKAGES`: no Arch o pacote `kate` já entrega
  `/usr/bin/kwrite` e `org.kde.kwrite.desktop`.
- `kwrited` e ferramentas `kwriteconfig6` do Plasma não foram alteradas.
- As associações de texto simples continuam apontando para KWrite, que
  vem com Kate, impedindo que LibreOffice assuma o padrão.
- Smoke test agora falha se o manifesto voltar a declarar `kwrite`
  como pacote separado.
- Nenhum outro componente do instalador foi modificado.


## Alpha16 — Wolf Control Center 0.1

A central gráfica usa PySide6 do repositório oficial e reúne MultiMonitor, Gamepad e GRUB Manager.
Também exibe o estado do Octopi Notifier e do Zsh Autosuggestions. Os helpers GRUB e Gamepad
continuam interativos no Konsole; reconciliação de monitores exige confirmação.

Para testar na instalação física atual, sem alterar o sistema instalado:

```bash
sudo pacman -S --needed pyside6
cd tools/control-center
./install-local.sh
~/.local/bin/wolf-control-center
```

Para desfazer a instalação local, execute `tools/control-center/uninstall-local.sh`.
O instalador da alpha16 integra a central durante uma instalação futura.

## Alpha17 — consolidação para instalação final

- O `preparar_ambiente_wolf_linux.sh` instala/verifica o pacote Archiso **antes** de testar `/usr/share/archiso/configs/releng`.
- Kate (`org.kde.kate.desktop`) é agora o editor padrão de arquivos de texto, inclusive Markdown/logs/JSON; KWrite não é instalado separadamente.
- Zsh autosuggestions utiliza `fg=250` ao final do `.zshrc`, validado em hardware real.
- Wolf Control Center 0.1.1 com páginas roláveis, botões visíveis e gestão do autostart do Octopi; continua sob demanda, sem watchers.
- O preparador pode destruir `~/wolf-linux` **somente após confirmação**; preserve imagens de VM antes de reconstruir.

### Alpha17 — aplicativos padrão e preparação limpa

O KDE base instala **Kate** como editor padrão de texto (incluindo Markdown e
logs), **Gwenview** como visualizador padrão de imagens (PNG/JPEG/WebP/GIF/SVG/
BMP/TIFF etc.), Dolphin como gerenciador de diretórios e Okular para PDFs.
O perfil Daily mantém MPC-QT para vídeo e Audacious para áudio.

O preparador instala/valida o pacote `archiso` **antes** de exigir que
`/usr/share/archiso/configs/releng` exista. Ao usar `--skip-deps`, você deve
instalar archiso manualmente. Falhas de dependências não apagam o projeto atual.

O .zshrc aplica `typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=250'` ao final,
conforme validado no Konsole físico. O Wolf Control Center 0.1.1 inclui
acompanhamento do Octopi Notifier e diagnóstico do carregamento do Zsh.


## Hotfix alpha18 — reconciliação MultiMonitor

- Com uma tela ativa, um painel já existente impede a criação de um segundo painel, mesmo que `panel.screen` ainda esteja indefinido no primeiro login.
- Em várias telas, painéis com associação de tela transitória bloqueiam alterações e produzem erro verificável, em vez de duplicar painéis.
- `apply` respeita a política desativada após restore **com aviso e código não-zero**, não silenciosamente.
- `reconcile` é sempre uma ação manual, com backup antes de alterações, e não reativa o autostart.
- Wolf Control Center 0.1.2 usa `reconcile` para o botão *Reconciliar painéis*.
- Nenhum painel é apagado automaticamente. O usuário pode restaurar o último backup pelo Control Center.


## Alpha19 — Wolf Live GUI (experimental)

Consulte `docs/WOLF-LIVE-GUI.md`: Openbox/Xorg exclusivo da live, preview PySide6 não destrutivo.
A baseline instalada continua KDE/Wayland da alpha18.


### Alpha26 — execução gráfica piloto **somente** em VM descartável
A aba de revisão pode iniciar o backend Bash com `--execute-gui-plan-vm`
somente após validação. Apenas disco VirtIO vazio, modo apagar disco, /home
na raiz, VM QEMU/KVM. Confirmação digitada no terminal antes de apagar.
Não usar com instalações/discos existentes; outros modos da GUI ainda simulam.


## Alpha35 — Live com Firefox e Wolf Mount Manager

A ISO Openbox passa a incluir Firefox (pt-BR) e uma ferramenta própria para **montar partições em leitura apenas** e abri-las no PCManFM-Qt. Ambas estão no menu e nos atalhos da primeira aba do instalador; não entram no sistema KDE instalado.

Os volumes ext2/3/4, NTFS, exFAT, FAT32, XFS e Btrfs podem ser selecionados. Volumes lógicos LVM **já ativos** e com sistema de arquivos são listados; os volumes físicos `LVM2_member` não são montados diretamente. O botão Mount utiliza um backend privilegiado somente na Live, sem usar `fsck` ou `vgchange`. `ext4` usa `ro,noload` e XFS usa `ro,norecovery` para evitar replay de journal. Não há auto-mount e a desmontagem nunca é forçada.

A ferramenta Wolf Storage Topology passa a consultar PVs, VGs e LVs com permissões apropriadas, apenas para diagnóstico. **Não tente instalar a GUI no hardware com EFI/raiz em SSDs separados ou /home em LVM**: a execução segue bloqueada nesses cenários.


## Alpha36 — Dispositivos no PCManFM-Qt e sincronização de hora

A Live utiliza GVfs/UDisks2 para montar dispositivos por clique no PCManFM-Qt **sem executar o explorador como root**. Descontinuado o Wolf Mount Manager de somente leitura. Montagens poderão oferecer escrita conforme filesystem/política, sob responsabilidade do operador, sem automontagem. O Firefox permanece na Live, que habilita systemd-timesyncd e oferece diagnóstico de data/hora/NTP para problemas de verificação em duas etapas. O instalador físico e cenários LVM multidisco continuam bloqueados.

**Nota de segurança:** o PCManFM-Qt deve executar como usuário normal da Live; montagens UDisks2 podem permitir escrita. Não editar volumes de Windows hibernado, sistema instalado ativo ou partições de boot sem backup.


## Alpha37 — Navegador Chromium, Bluetooth e Wolf Rescue 0.1

Substitui Firefox por Chromium **somente na Live**, com BlueZ + Blueman
para gerenciar Bluetooth em Openbox. O PCManFM-Qt mantém montagem de volumes
via UDisks2. O novo Wolf Rescue é diagnóstico read-only (EFI/BIOS, discos,
LVM e entradas UEFI), sem comandos de reparação automática. A instalação GUI
permanece exclusiva de VM nesta versão. Instalar em dois NVMe com EFI em um,
raiz em outro e LV multi-PV exige planejamento e homologação específica.

## Alpha38 — Wolf Rescue 0.2 e interface responsiva

- Wolf Rescue com visual escuro consistente e mapa de volumes por UUID (`fstab` + `lsblk`), inclusive EFI em disco diferente da raiz e LVM com PVs em múltiplos SSDs.
- Wolf Installer GUI 1.8 ajusta largura da janela, botões e abas para evitar rolagem horizontal.
- **Importante:** `Wolf Rescue` continua somente leitura. O instalador gráfico em hardware físico continua BLOQUEADO. O mapa é diagnóstico, não um plano de instalação autorizado.

Leia `CHANGELOG-alpha38.md` e `docs/WOLF-HARDWARE-PREFLIGHT.md` antes de testar a Live em hardware real.

## Alpha39 — Detecção multidisco e LVM para planejamento

Na Live, **Partições → Reutilizar → Detectar instalações em TODOS os discos** procura instalações existentes, cruza os UUIDs do `fstab` com o inventário atual e sugere raiz `/`, EFI e `/home` mesmo em SSDs distintos e LVM com múltiplos PVs. As sugestões podem ser corrigidas com confirmação. **Revisão e simulação são somente de leitura; hardware físico continua bloqueado para instalação.** Ver `docs/WOLF-MULTIDISK-REUSE-PREVIEW.md` e `CHANGELOG-alpha39.md`.


### alpha40 — Correção do encaminhamento multidisco na Live

Na alpha39 o wrapper `wolf-install` não reconhecia duas opções de revisão multidisco. Na alpha40, os comandos `--review-multidisk-plan` e `--simulate-multidisk-plan` são encaminhados ao Bash **sem** adicionar `--install`, e os modos permanecem estritamente não destrutivos. Consulte `CHANGELOG-alpha40.md`.

### alpha41 — Laboratório UEFI com dois discos e LVM

Foi adicionado um laboratório exclusivo de VM QEMU/KVM com discos qcow2
independentes (64 GiB e 96 GiB), para testar **EFI em um disco, raiz no outro,
e `/home` no LV distribuído por dois PVs**. Instruções completas em
`docs/WOLF-ALPHA41-MULTIDISK-LAB.md`.

```bash
./tests/wolf-vm-multidisk.sh create
./tests/wolf-vm-multidisk.sh live
# Já dentro da ISO Live no QEMU:
sudo wolf-lab41-particionar --check
sudo wolf-lab41-particionar --apply
```

O executor multidisco destrutivo **ainda não está habilitado**. O propósito da
alpha41 é estabelecer e validar a base de testes controlados antes desse passo.


## Alpha43 — transição controlada para hardware físico

O fluxo multidisco/LVM foi validado na VM alpha42. Na alpha43, a reinstalação com `/home` preservada verifica o UID histórico e realiza prova de escrita; conflitos são bloqueados. A Live inclui `wolf-physical-preflight` para inventário somente leitura. A execução física destrutiva permanece bloqueada. Veja `CHANGELOG-alpha43.md`.


### Correção alpha44 (testes como usuário comum)

A alpha44 corrige o teste `tests/wolf-test-alpha43.py` para não presumir que um diretório temporário pertence a root. O motor de instalação da alpha43 permanece inalterado, exceto pelo número de versão. Veja `CHANGELOG-alpha44.md`.


### Alpha45 — detecção segura de recuperação pendente no ext4

O scanner multidisco consulta `tune2fs -l` **sem escrita** em raízes ext4
ainda não montadas. Ao encontrar `needs_recovery` ou `orphan_present`,
identifica a partição e explica o bloqueio na aba Partições, em vez de
mostrar apenas “0 instalações”. Não recupera journal, não executa fsck
automaticamente e não habilita a instalação física. Falhas de montagem
`ro,noload` também são mostradas, preservando as verificações de UUID
e `fstab`.

Para o piloto físico, primeiro rode `wolf-physical-preflight` e
`sudo python3 /usr/local/share/wolf-linux-live/gui/wolf_discovery.py scan`
na Live; a verificação de disco descartável ainda é necessária antes de
qualquer execução real em NVMe com Windows/LVM.
Veja `CHANGELOG-alpha45.md`.


## Alpha53 — integração GUI→instalador VM

A nova interface executa os três modos SOMENTE em VMs QEMU/KVM/VirtualBox iniciadas pela Live e discos VirtIO. Confira `CHANGELOG-alpha53.md`. O instalador clássico permanece disponível para hardware real/LVM.

## Alpha58 — observações de homologação

O instalador da Live é único. Espaços dos perfis são estimativas, não garantias.
A etapa UEFI agora valida o loader exato e preserva o fallback EFI existente.
Antes de instalar em hardware físico com dados, confirme inicialização em VM.

### Diagnóstico se a instalação não abrir o GRUB
Inicie novamente pela ISO em modo UEFI e rode `sudo wolf-boot-diagnose`, identificando a ESP em `lsblk`. Em seguida, execute `sudo wolf-boot-diagnose /dev/SUA_ESP`. Esse utilitário não formata nem modifica partições. Envie a saída, especialmente a linha BootOrder e o caminho da entrada WolfLinux. A presença de arquivos EFI, isoladamente, não comprova que o firmware os consegue carregar.
