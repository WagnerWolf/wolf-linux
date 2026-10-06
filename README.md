# Wolf Linux 1.0

<p align="center">
  <img src="wolf-linux-logo.png" alt="Wolf Linux" width="360">
</p>

**Wolf Linux** é um projeto pessoal baseado em **Arch Linux**, criado para automatizar uma instalação completa, reproduzível e personalizada para uso diário, desenvolvimento, jogos e multimídia.

A distribuição usa o Arch Linux como base, `linux-zen` como kernel padrão, PipeWire como stack de áudio, SDDM como display manager e oferece escolha entre **MATE**, **Cinnamon** e **KDE Plasma** no momento da instalação.

A versão 1.0 foi desenvolvida e validada em máquinas virtuais UEFI/BIOS e em hardware real, com especial atenção a detecção de GPU, preservação de `/home`, dual boot, múltiplos monitores, Bluetooth, NVIDIA e identidade visual própria.

> **Aviso:** o instalador pode formatar discos e partições. Sempre confira o plano exibido antes de confirmar uma instalação real.

---

## Principais características

### Base do sistema

- Arch Linux rolling release.
- Kernel `linux-zen` + headers.
- Microcode AMD ou Intel selecionado automaticamente.
- GRUB com suporte a UEFI e BIOS/Legacy.
- `os-prober` para sistemas preservados, incluindo Windows.
- `multilib` habilitado por padrão.
- Chaotic-AUR configurado pelo instalador, com fallback para AUR via `yay`.
- NetworkManager + suporte a OpenVPN e IWD.
- SDDM nos três ambientes gráficos.
- `sudo` com grupo `wheel` e feedback de senha por asteriscos (`pwfeedback`).
- Conta `root` bloqueada após a instalação.

### Ambientes gráficos

O instalador pergunta qual ambiente deve ser instalado:

1. **MATE**
2. **Cinnamon**
3. **KDE Plasma**

O MATE é o ambiente mais personalizado do projeto e inclui:

- painel inferior estilo Windows;
- Brisk Menu;
- Materia Dark;
- bordas Wolf-Sunrise-Dark;
- Papirus Dark;
- cursor Breeze Dark;
- notificações Coco;
- wallpaper Wolf Linux;
- integração do Caja com VS Code;
- integração do Caja com formatação de mídias removíveis;
- bandeja de dispositivos removíveis com `udiskie`;
- barreiras inteligentes entre monitores;
- mouse sem aceleração no X11/libinput.


### Wolf MultiMonitor (Cinnamon)

O perfil Cinnamon inclui o **Wolf MultiMonitor**, validado em hardware real com duas telas.

Na sessão X11 ele mantém uma experiência independente por monitor:

- painel inferior em cada monitor ativo;
- CinnVIIStarkMenu em cada painel;
- Grouped Window List mostrando somente as janelas da própria tela;
- relógio nos painéis criados automaticamente;
- Alt+Tab limitado ao monitor ativo;
- detecção de novos monitores durante a sessão por XRandR.

O watcher é aditivo e conservador: ao desconectar uma tela, o Wolf Linux **não apaga** o painel associado, preservando personalizações para quando ela voltar. Ao conectar uma tela nova, o painel que estiver faltando é criado automaticamente.

Comandos disponíveis no sistema instalado:

```bash
wolf-cinnamon-multimonitor status
wolf-cinnamon-multimonitor enable
wolf-cinnamon-multimonitor disable
wolf-cinnamon-multimonitor restore
```

`restore` restaura o último backup e desativa o gerenciamento automático para que a configuração restaurada não seja reaplicada imediatamente.

### Áudio e Bluetooth

- PipeWire.
- PipeWire Pulse.
- PipeWire ALSA.
- WirePlumber.
- RTKit.
- BlueZ / BlueZ Utils.
- Blueman no MATE/Cinnamon.
- `pavucontrol`.

O uso de PipeWire foi escolhido também pensando em headsets Bluetooth e troca entre perfis A2DP/HFP.

### Vídeo e Vulkan

O instalador detecta automaticamente o perfil gráfico.

Perfis atualmente previstos:

- QEMU/VirtIO;
- AMD;
- Intel;
- NVIDIA moderna;
- NVIDIA legacy/Nouveau.

Para NVIDIA moderna com `linux-zen`, o Wolf Linux utiliza `nvidia-open-dkms` e instala também:

- `nvidia-utils`;
- `lib32-nvidia-utils`;
- `nvidia-settings`;
- Vulkan 64/32-bit;
- VA-API NVIDIA.

Para placas antigas incompatíveis com os drivers NVIDIA atuais, o instalador pode optar pelo Nouveau.

### Gaming

Incluído por padrão:

- Steam;
- Lutris;
- Wine;
- Wine Mono / Gecko;
- Winetricks;
- Protontricks;
- ProtonUp-Qt;
- GameMode;
- Vulkan 64/32-bit;
- VKD3D.

Não são instalados deliberadamente:

- Bottles;
- Gamescope;
- MangoHUD.

### Desenvolvimento

Inclui entre outros:

- Git;
- GCC/base-devel;
- CMake;
- Ninja;
- Clang;
- Python;
- OpenJDK 17 e 21;
- Android Studio;
- Android SDK / Build Tools / Platform Tools;
- Android Udev;
- VS Code;
- Insomnia;
- Flutter Stable instalado em `/opt/flutter`.

O Android Emulator é pensado para utilizar KVM diretamente; VirtualBox e Genymotion não fazem parte da instalação padrão.

### Internet

- Google Chrome;
- AB Download Manager;
- JDownloader 2;
- Transmission Qt.

### Escritório e multimídia

- LibreOffice Fresh + tradução pt-BR;
- leitor PDF nativo do ambiente;
- SMPlayer + MPV;
- Audacious;
- FFmpeg;
- GIMP;
- OBS Studio.

### Miniaturas e previews

O sistema instala suporte adicional de miniaturas para vários formatos, incluindo:

- vídeo e áudio;
- WebP;
- HEIF/AVIF;
- RAW de câmeras;
- WMF/APM;
- EPUB/MOBI;
- documentos ODF;
- PDF;
- executáveis/ícones do Windows/Wine.

### Terminal e shell

- Zsh como shell do usuário.
- Oh My Zsh.
- Powerlevel10k.
- zsh-autosuggestions.
- zsh-completions.
- zsh-history-substring-search.
- zsh-syntax-highlighting.
- Meslo Nerd Font.
- Fastfetch automático ao abrir o terminal.
- arte própria Wolf Linux no Fastfetch.

O terminal gráfico abre com largura ampliada para acomodar melhor o Fastfetch e o Powerlevel10k.

Nos TTYs (`Ctrl+Alt+F2`, `F3` etc.) é utilizado um perfil separado:

- Terminus `ter-v16n`;
- logo ASCII simplificada;
- Fastfetch reduzido;
- prompt Zsh simples;
- sem Powerlevel10k/Nerd Font.

### Identidade visual

O Wolf Linux possui identidade própria em:

- GRUB;
- Plymouth;
- SDDM;
- wallpaper;
- Fastfetch;
- tema MATE.

O tema SDDM utiliza o framework do projeto **sddm-astronaut-theme**, com configuração e arte Wolf Linux.

Consulte [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md) para créditos e licenças de componentes visuais de terceiros.

---

# Estrutura do projeto

Após preparar o ambiente, o projeto principal fica por padrão em:

```text
~/wolf-linux/
```

Estrutura relevante:

```text
wolf-linux/
├── install/
│   └── wolf-install.sh
├── package-profiles/
│   └── packages.conf
├── assets/
│   ├── grub/
│   ├── plymouth/
│   ├── sddm/
│   ├── wallpapers/
│   └── zsh/
├── iso-profile/
├── tests/
├── vm/
├── work/
└── out/
```

### Diretórios

| Caminho | Função |
|---|---|
| `install/` | instalador principal |
| `package-profiles/` | manifesto de pacotes |
| `assets/` | branding e configurações visuais |
| `iso-profile/` | perfil ArchISO baseado no `releng` |
| `tests/` | build, smoke test, VM, SSH e utilitários |
| `vm/` | discos QCOW2 e NVRAM das VMs |
| `work/` | diretório temporário do `mkarchiso` |
| `out/` | ISOs geradas |

---

# Preparando o ambiente de desenvolvimento

O host de build deve ser um sistema Arch Linux ou derivado com acesso aos repositórios do Arch.

O DevKit instala automaticamente as ferramentas principais:

- `archiso`;
- `qemu-desktop`;
- `edk2-ovmf`;
- `shellcheck`;
- `git`;
- `python`.

Extraia o DevKit e execute:

```bash
chmod +x preparar_ambiente_wolf_linux.sh
./preparar_ambiente_wolf_linux.sh
```

O script cria `~/wolf-linux`, copia o perfil `releng` do ArchISO, instala os scripts, manifesto e assets e personaliza o perfil da ISO.

Se já existir uma logo do Plymouth validada em:

```text
~/wolf-linux/assets/plymouth/logo.png
```

ela é preservada pelo preparador.

---

# Atualizando um projeto existente para 1.0

Se `~/wolf-linux` já existe e contém seus assets validados, prefira:

```bash
chmod +x wolf-upgrade-project-to-1.0.sh
./wolf-upgrade-project-to-1.0.sh
```

Esse script atualiza o instalador, manifesto e scripts de teste **sem sobrescrever `assets/`**.

Ao final ele também executa o smoke test.

---

# Testes rápidos

Antes de gerar uma ISO:

```bash
cd ~/wolf-linux
./tests/wolf-smoke-test.sh
```

O smoke test verifica, entre outras coisas:

- sintaxe Bash com `bash -n`;
- `shellcheck` quando disponível;
- manifesto de pacotes;
- estrutura do perfil ArchISO;
- teclado `br-abnt2` na ISO live;
- Terminus `ter-v16n` no console live;
- identidade `Wolf Linux Live`;
- permissões executáveis do `wolf-install` dentro da ISO.

Resultado esperado:

```text
[OK] Testes rápidos concluídos.
```

---

# Dry-run do instalador

Antes de qualquer instalação real, o instalador pode ser executado no sistema atual sem alterar discos:

```bash
cd ~/wolf-linux
./install/wolf-install.sh --dry-run
```

O dry-run faz a detecção de:

- modo UEFI/BIOS;
- CPU;
- GPUs;
- perfil gráfico;
- teclado;
- conectividade;
- desktop escolhido;
- hostname e usuário;
- instalação Linux existente;
- layout de discos, LVM, `/home` e ESP.

No final ele mostra o **PLANO WOLF LINUX** e encerra sem formatar, montar ou instalar nada.

Também existe:

```bash
./install/wolf-install.sh --plan-only
```

---

# Gerando a ISO

Execute:

```bash
cd ~/wolf-linux
./tests/wolf-build-iso.sh
```

O script:

1. executa novamente a customização do perfil;
2. limpa `~/wolf-linux/work`;
3. executa `mkarchiso`;
4. grava a ISO em `~/wolf-linux/out/`.

A ISO é identificada como **Wolf Linux Live/Installer** e inicia com teclado BR-ABNT2.

---

# Testando a ISO em QEMU/KVM

## UEFI

```bash
cd ~/wolf-linux
./tests/wolf-run-arch-test.sh uefi
```

## BIOS/Legacy

```bash
./tests/wolf-run-arch-test.sh bios
```

Quando o caminho da ISO não é informado, o script usa automaticamente a ISO mais recente em:

```text
~/wolf-linux/out/
```

Cada execução via `wolf-run-arch-test.sh` utiliza `--fresh`, recriando o disco da VM para garantir um teste limpo.

Configuração padrão da VM:

- QEMU/KVM;
- chipset Q35;
- CPU host;
- 4 vCPUs;
- 8 GiB RAM;
- disco QCOW2 de 80 GiB;
- VirtIO VGA;
- VirtIO Network;
- áudio HDA;
- OVMF em UEFI;
- boot tradicional em BIOS.

### Critério recomendado para validação final

Faça uma instalação completa em UEFI e outra em BIOS:

1. iniciar a ISO;
2. executar `wolf-install`;
3. concluir toda a instalação;
4. reiniciar a VM;
5. confirmar o boot pelo disco instalado;
6. entrar no SDDM;
7. iniciar a sessão gráfica;
8. conferir tema, painel, áudio e aplicações principais.

---

# SSH na VM live

A VM redireciona:

```text
127.0.0.1:2222 -> guest:22
```

Dentro da ISO live, como root:

```bash
/root/wolf-linux/tests/wolf-enable-ssh-live.sh
```

Defina uma senha temporária para `root`.

No host:

```bash
~/wolf-linux/tests/wolf-vm-ssh.sh
```

ou:

```bash
ssh -p 2222 root@127.0.0.1
```

A senha é apenas da sessão live e desaparece ao reiniciar a VM.

---

# Instalando o Wolf Linux

Na ISO live:

```bash
wolf-install
```

Sem argumentos, o wrapper detecta o ambiente:

- QEMU/KVM → usa `--vm-install`;
- hardware físico → usa `--install`.

Também é possível chamar explicitamente:

```bash
wolf-install --dry-run
wolf-install --vm-install
wolf-install --install
```

## Proteções do instalador

O instalador possui travas deliberadas:

- `--vm-install` é recusado fora de QEMU/KVM;
- `--install` é recusado dentro de QEMU/KVM;
- instalação real precisa ser executada como root;
- o plano completo é mostrado antes das operações destrutivas;
- para prosseguir é necessário digitar exatamente:

```text
INSTALAR-WOLF
```

---

# Armazenamento

O instalador tenta detectar automaticamente uma instalação Linux existente.

Quando encontra uma estrutura reconhecível, pode propor algo como:

```text
/          /dev/...          SERÁ FORMATADO
/boot/efi  /dev/...          SERÁ PRESERVADO
/home      /dev/mapper/...   SERÁ PRESERVADO
```

Outras partições fora desse plano, como Windows ou Recovery, não são alteradas no modo de reutilização.

Caso a detecção automática não seja aceita, existem três modos:

```text
1) Apagar um disco e instalar automaticamente
2) Escolher/reutilizar partições existentes manualmente
3) Configuração manual/avançada
```

## Apagar disco inteiro

No modo `erase`:

### UEFI

O instalador cria:

- ESP de 1 GiB;
- partição raiz usando o restante do disco.

### BIOS

Cria uma tabela MBR/MS-DOS e uma partição ext4 bootável ocupando o disco.

**Todo o disco selecionado é apagado nesse modo.**

## Preservando `/home`

Quando `/home` está em uma partição ou LV separado, o instalador pode preservá-lo.

Ele pergunta separadamente se deve remover apenas os arquivos e diretórios ocultos diretamente dentro de:

```text
/home/USUARIO/
```

Exemplos removíveis:

```text
.config
.cache
.local
.mozilla
.zshrc
.p10k.zsh
```

Arquivos e pastas visíveis, como `Documentos`, `Downloads`, `Projetos` e `Imagens`, são preservados.

A própria partição/LV `/home` **não é formatada** nesse fluxo.

---

# Fluxo de instalação

As principais etapas são registradas como checkpoints:

```text
10-preparar-disco
20-formatar-montar
22-limpar-home
25-repositorios-live
27-validar-pacotes
30-pacstrap
40-fstab
50-multilib
55-completar-pacotes-base
60-sistema-base
61-identidade-wolf
62-usuario-sudo
63-chaotic-aur
64-apps-oficiais
65-yay
66-apps-terceiros
66b-octopi-notifier
67-servicos
67b-tema-mate
68-estilo-base
68a-mate-session
68b-flutter
68c-zsh
68d-terminal
68e-mate-layout
68f-desktop-extras
69-video
69b-validar-video
69c-gaming
69d-branding
70-bootloader
72-validar-boot
80-finalizar
```

Em caso de falha, o instalador exibe:

- etapa;
- código de saída;
- linha;
- último comando;
- mounts ativos;
- checkpoints concluídos;
- caminho do log.

Log padrão:

```text
/tmp/wolf-linux-installer/wolf-install.log
```

---

# Chaotic-AUR e falhas temporárias de mirror

O instalador valida os pacotes de bootstrap antes de instalá-los.

Ele também detecta respostas inválidas como:

```text
mirror unhealthy
```

mesmo quando o servidor responde HTTP 200.

Quando o mirror está indisponível, o instalador pergunta:

```text
Tentar novamente agora? [S/n]
```

Portanto não é necessário reiniciar toda a instalação apenas por uma falha temporária do Chaotic-AUR.

---

# Tema escuro em aplicações GNOME

No MATE, além do tema GTK, o Wolf Linux configura:

```text
org.gnome.desktop.interface color-scheme = prefer-dark
```

com:

- `xdg-desktop-portal`;
- `xdg-desktop-portal-gtk`.

O valor esperado no portal é `uint32 1`:

```bash
gdbus call --session \
  --dest org.freedesktop.portal.Desktop \
  --object-path /org/freedesktop/portal/desktop \
  --method org.freedesktop.portal.Settings.Read \
  org.freedesktop.appearance \
  color-scheme
```

Resposta esperada:

```text
(<<uint32 1>>,)
```

Isso permite que aplicações como GNOME Disks respeitem o modo escuro mesmo dentro da sessão MATE.

---

# Múltiplos monitores no MATE

## Barreiras de borda

No MATE/X11 o Wolf Linux cria pequenas barreiras nas divisas entre monitores:

- 36 px no canto superior;
- 36 px no canto inferior;
- região central livre para passagem normal.

Isso facilita atingir rapidamente os cantos para fechar janelas ou acionar elementos no canto inferior sem o ponteiro escapar imediatamente para o outro monitor.

---

# Mouse sem aceleração

Essa configuração é específica para o perfil MATE/X11 do Wolf Linux.

Arquivo persistente:

```text
/etc/X11/xorg.conf.d/50-wolf-mouse-no-accel.conf
```

Configuração esperada:

```text
Option "AccelProfile" "flat"
Option "AccelSpeed" "0"
```

Touchpads são excluídos dessa regra.

Além do arquivo Xorg, existe um reforço no autostart do MATE para impedir que uma preferência antiga devolva o mouse ao perfil adaptativo.

## Como confirmar que a aceleração está realmente desativada

Liste os dispositivos:

```bash
xinput list --short
```

Identifique o ID do mouse e execute, por exemplo:

```bash
xinput list-props ID_DO_MOUSE | grep -E \
  'libinput Accel Profile Enabled|libinput Accel Speed'
```

No Wolf Linux, o resultado efetivo esperado é equivalente a:

```text
libinput Accel Profile Enabled (...): 0, 1  (ou 0, 1, 0 em dispositivos com 3 perfis)
libinput Accel Speed (...): 0.000000
```

O ponto mais importante é o **perfil flat**. `AccelSpeed=0` sozinho não significa necessariamente ausência de aceleração; o perfil flat é o que remove a curva adaptativa de aceleração.

Também é possível verificar a configuração persistente:

```bash
cat /etc/X11/xorg.conf.d/50-wolf-mouse-no-accel.conf
```

Se quiser verificar todos os dispositivos que expõem propriedades de aceleração:

```bash
for id in $(xinput list --id-only); do
    props="$(xinput list-props "$id" 2>/dev/null || true)"
    if grep -q 'libinput Accel Profile Enabled' <<<"$props"; then
        echo "============================================================"
        xinput list --name-only "$id" 2>/dev/null || echo "ID $id"
        grep -E \
          'libinput Accel Profile Enabled|libinput Accel Speed' \
          <<<"$props"
    fi
done
```

---

# Mídias removíveis

## Bandeja

O Wolf Linux usa `udiskie` em modo smart tray:

```text
udiskie --smart-tray --no-automount --no-notify --file-manager=/usr/bin/caja
```

O automount permanece sob responsabilidade do Caja/GVfs, evitando dois automounters concorrentes.

A bandeja permite montar, desmontar e ejetar/remover mídias com segurança.

## Formatar pendrive pelo Caja

Quando o usuário está na raiz de um filesystem montado em dispositivo removível/USB/MMC, o Caja oferece:

```text
Formatar mídia removível…
```

A ação abre o GNOME Disks para o dispositivo detectado. A formatação continua exigindo confirmação gráfica; o plugin não executa uma formatação destrutiva silenciosa.

---

# Bluetooth

Dispositivos pareados podem ser marcados como **Trusted** pelo BlueZ.

Para verificar:

```bash
bluetoothctl devices
bluetoothctl info XX:XX:XX:XX:XX:XX
```

Para headsets que não reconectam automaticamente, confira também a opção de conexão automática no Blueman.

---

# Aplicativos padrão e integração do desktop

No perfil MATE, o Wolf Linux configura defaults e integrações para o fluxo de uso diário, incluindo:

- Audacious para áudio;
- SMPlayer para vídeo;
- leitor PDF do ambiente;
- abertura de pasta no VS Code via menu de contexto do Caja;
- miniaturas adicionais;
- GNOME Keyring / libsecret para aplicações como VS Code;
- Octopi + Octopi Notifier após login.

---

# Checklist de validação da ISO 1.0

Antes de publicar uma nova ISO, recomenda-se validar:

- [ ] `wolf-smoke-test.sh` passa sem erros;
- [ ] ISO é gerada com `wolf-build-iso.sh`;
- [ ] ISO inicia em UEFI;
- [ ] instalação completa UEFI termina sem erros;
- [ ] sistema UEFI instalado reinicia pelo disco;
- [ ] ISO inicia em BIOS/Legacy;
- [ ] instalação completa BIOS termina sem erros;
- [ ] sistema BIOS instalado reinicia pelo disco;
- [ ] SDDM carrega corretamente;
- [ ] Plymouth exibe logo transparente sem fundo quadrado;
- [ ] ambiente selecionado inicia;
- [ ] PipeWire/WirePlumber estão ativos;
- [ ] RTKit está disponível;
- [ ] rede funciona;
- [ ] tema escuro está aplicado;
- [ ] Fastfetch aparece automaticamente no terminal gráfico;
- [ ] TTY usa Terminus e prompt simplificado;
- [ ] mouse usa perfil `flat` no MATE/X11;
- [ ] `udiskie` aparece quando necessário;
- [ ] formatação pelo Caja abre GNOME Disks corretamente;
- [ ] GRUB, Plymouth, SDDM e wallpaper exibem o branding Wolf Linux.

---

# Comandos rápidos

## Preparar ambiente do zero

```bash
./preparar_ambiente_wolf_linux.sh
```

## Atualizar projeto existente

```bash
./wolf-upgrade-project-to-1.0.sh
```

## Smoke test

```bash
cd ~/wolf-linux
./tests/wolf-smoke-test.sh
```

## Dry-run do instalador

```bash
./install/wolf-install.sh --dry-run
```

## Gerar ISO

```bash
./tests/wolf-build-iso.sh
```

## Testar UEFI

```bash
./tests/wolf-run-arch-test.sh uefi
```

## Testar BIOS

```bash
./tests/wolf-run-arch-test.sh bios
```

## Instalar pela ISO

```bash
wolf-install
```

---

# Créditos

Wolf Linux é construído sobre o ecossistema Arch Linux e utiliza diversos projetos livres.

Componentes visuais de terceiros utilizados diretamente pelo projeto são documentados em:

[`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md)

Entre eles:

- sddm-astronaut-theme;
- Sunrise GTK Themes.

---

# Estado do projeto

**Wolf Linux 1.0** representa a primeira versão consolidada do instalador e da ISO personalizada.

A partir desta base, correções pequenas podem seguir versionamento `1.0.x`, enquanto mudanças maiores de comportamento, desktop ou arquitetura podem seguir para `1.1` ou superior.


## Wolf Linux 1.0.2

A revisão 1.0.2 acrescenta duas correções finais:

- aplicação correta do perfil de mouse `flat` tanto em dispositivos que expõem 2 valores quanto 3 valores em `libinput Accel Profile Enabled`;
- branding do GRUB da própria mídia live/ISO no boot BIOS usando `assets/grub/background.png`.

## Wolf Linux 1.0.6 — estabilidade

A revisão 1.0.6 remove o experimento `Super + botão do meio` para mover janelas entre monitores. Embora funcionasse em várias janelas do Marco, aplicações CSD/maximizadas como Google Chrome apresentaram condições de corrida e encerramentos do daemon X11.

A decisão para a linha 1.0 é priorizar estabilidade. Permanecem as **barreiras inteligentes de borda** entre monitores, que foram validadas e não apresentaram problemas. O comportamento normal do botão do meio na barra de título do Marco é restaurado para `lower`.

Para remover o recurso de uma instalação que recebeu versões experimentais anteriores:

```bash
./wolf-remove-window-mover-1.0.6.sh
```

Uma solução de movimentação entre monitores pode ser reavaliada futuramente em outra versão, sem fazer parte da base estável 1.0.x.


## Notas da versão 1.0.7

### Boot Legacy BIOS

O boot Legacy da mídia Archiso usa **Syslinux/vesamenu**, não o GRUB.
O Wolf Linux agora substitui explicitamente:

- `iso-profile/syslinux/splash.png`
- `MENU TITLE Arch Linux` → `MENU TITLE Wolf Linux`

A imagem dedicada fica em:

```text
assets/syslinux/splash.png
```

Ela é preparada em 800×600 para o menu VESA do Syslinux.

### Cursor no Cinnamon

O Cinnamon passa a usar o nome real do tema Breeze disponível em seu
seletor de cursores:

```text
breeze_cursors
```

O primeiro login também sincroniza o mesmo tema em GSettings, GTK3/GTK4,
XCursor e nos fallbacks `~/.icons/default` e
`~/.local/share/icons/default`, evitando cursores misturados ou corrompidos.


## Notas da versão 1.0.8

- MATE: Pluma e MATE Calculator instalados explicitamente.
- Cinnamon: Xed definido como editor padrão de texto e Galculator adicionado.
- KDE Plasma: KWrite (pacote `kate`) definido como editor padrão e KCalc adicionado.
- KDE Plasma: o launcher fixado do Discover é removido do painel no primeiro login.
- O fundo preto do Syslinux em alguns boots Legacy é aceito; o menu continua funcional.


## Notas da versão 1.0.9

### Cinnamon

- Corrigido o desktop ID do **Xed**: no Arch atual ele é
  `org.x.editor.desktop`, não `xed.desktop`.
- O Xed é aplicado aos MIME types de texto/código declarados pelo próprio
  aplicativo, além da lista básica do Wolf Linux.
- Adicionado **Xviewer** como visualizador de imagens padrão.
- `org.cinnamon.desktop.default-applications.calculator exec` passa a ser
  `galculator`.
- `gnome-keyring` e `libsecret` passam a fazer parte explicitamente do perfil
  Cinnamon.

### Pacotes pessoais

- `anydesk-bin` foi removido da instalação padrão do Wolf Linux.


## Notas da versão 1.0.10

### Integração Nemo / Cinnamon

O perfil Cinnamon passa a instalar `nemo-python`, `udiskie` e
`gnome-disk-utility`.

O Nemo recebe duas integrações próprias do Wolf Linux:

- **Abrir pasta no VS Code**
- **Formatar mídia removível…**

A ação de formatação só aparece na raiz de um filesystem em dispositivo
USB/MMC/removível e abre o diálogo seguro do GNOME Disks.

O `udiskie` também é iniciado no Cinnamon em modo `--smart-tray`,
sem competir com o automount do Nemo/GVfs.


## Notas da versão 1.0.11

### Cinnamon e mídias removíveis

O `udiskie` foi removido do perfil Cinnamon. O Cinnamon já possui seu próprio
applet para desmontagem/ejeção de mídias removíveis, então manter um segundo
ícone na bandeja seria redundante.

As integrações do Nemo permanecem:

- **Abrir pasta no VS Code**
- **Formatar mídia removível…** via GNOME Disks

O MATE continua usando `udiskie`, pois nele essa integração continua sendo útil.


## Notas da versão 1.0.14 — Cinnamon

O perfil Cinnamon passa a priorizar **Cinnamon X11**. A sessão Wayland continua
instalada, mas não é a sessão padrão do Wolf Linux.

Motivos práticos observados no hardware real:

- aceleração de mouse mais previsível com libinput/XInput;
- Flameshot mais previsível;
- drag-and-drop do gerenciador de arquivos compactados;
- redução de artefatos/piscadas observados no Chrome em Wayland.

### Multimídia

- SMPlayer deixa de ser instalado por padrão.
- VLC + `vlc-plugins-all` passam a ser instalados.
- VLC é o player padrão para vídeo.
- Audacious continua como player padrão de áudio.

### Arquivos compactados

- File Roller/Nemo-Fileroller deixam o perfil Cinnamon.
- Xarchiver passa a ser o gerenciador padrão de arquivos compactados.
- Em X11, Xarchiver suporta drag-and-drop de arquivos a partir do arquivo
  compactado.

### Dark mode e portais

O Cinnamon instala e roteia:

- `xdg-desktop-portal-xapp`
- `xdg-desktop-portal-gtk`
- `org.freedesktop.impl.portal.Settings` → XApp/GTK
- `org.freedesktop.impl.portal.Secret` → GNOME Keyring

### GNOME Keyring / VS Code

O SDDM recebe reforço de PAM apenas quando as linhas de GNOME Keyring estiverem
ausentes. O VS Code usa `password-store=gnome-libsecret`.

### Flameshot

- instalado por padrão;
- sem ícone permanente na tray;
- daemon fecha quando fica ocioso;
- `Print` é configurado para `flameshot gui`.


## Notas da versão 1.0.15 — Cinnamon

### Flameshot

Corrigida a gravação de `~/.config/flameshot/flameshot.ini`.

O Python `ConfigParser` converte nomes de opções para minúsculas por padrão.
Como o Flameshot diferencia maiúsculas/minúsculas, opções válidas como
`contrastOpacity`, `disabledTrayIcon`, `autoCloseIdleDaemon` e
`showStartupLaunchMessage` acabavam sendo regravadas como nomes inválidos.

A configuração agora usa `optionxform = str` e `interpolation=None`, preservando
o case original das chaves existentes e das opções adicionadas pelo Wolf Linux.

### GNOME Keyring / VS Code

A integração foi simplificada para acompanhar o comportamento atual do Arch:

- o PAM fornecido pelo SDDM é reconhecido tanto com quanto sem o prefixo `-`,
  evitando duplicar linhas de `pam_gnome_keyring.so`;
- o Wolf Linux passa a confiar no autostart nativo do pacote Arch do
  `gnome-keyring`, que já inclui Cinnamon;
- o Wolf Linux não inicia mais socket/daemon do GNOME Keyring manualmente
  durante o login, evitando uma segunda inicialização redundante;
- o VS Code continua configurado com `password-store=gnome-libsecret`;
- o script de correção passa a informar se o Secret Service está ativo e se a
  coleção `login` está desbloqueada.

### Estado dos demais ajustes do Cinnamon

- Xarchiver permanece como gerenciador padrão de arquivos compactados;
- o modo escuro permanece aplicado aos aplicativos GTK/portais;
- Cinnamon X11 continua sendo a sessão padrão recomendada pelo Wolf Linux.


## 1.0.16 — Cinnamon: limpeza definitiva do Flameshot e diagnóstico do Login Keyring

### Flameshot

A 1.0.15 passou a preservar maiúsculas/minúsculas ao gravar `flameshot.ini`,
mas entradas inválidas criadas anteriormente pela 1.0.14 podiam permanecer no
arquivo ao lado das opções corretas. A 1.0.16 remove explicitamente:

- `contrastopacity`;
- `autocloseidledaemon`;
- `disabledtrayicon`;
- `showstartuplaunchmessage`.

Em seguida grava somente as opções oficiais camelCase, incluindo
`contrastOpacity=190` quando a opção correta ainda não existia.

### GNOME Keyring / VS Code

O daemon e o Secret Service podem estar ativos mesmo quando a coleção
`login` ainda não existe. O diagnóstico do fix agora diferencia esse estado.
Instalações limpas continuam usando o fluxo nativo SDDM/PAM do Arch; sistemas
que passaram pelas versões de desenvolvimento anteriores podem precisar criar
a coleção `login` uma única vez, usando a mesma senha da conta para que o PAM
consiga desbloqueá-la nos logins seguintes.


## 1.0.17 — Cinnamon X11-only e consolidação dos fixes

### Cinnamon somente em X11

O perfil Cinnamon do Wolf Linux deixa de apenas priorizar X11 e passa a
oferecer **somente Cinnamon X11** no SDDM. O instalador remove as entradas
`/usr/share/wayland-sessions/cinnamon*.desktop` e instala o hook
`/etc/pacman.d/hooks/wolf-cinnamon-x11-only.hook`, que reaplica a remoção
após instalações/atualizações do pacote `cinnamon`. A sessão
`Cinnamon (Software Rendering)` continua disponível por ser uma sessão X11.

### Flameshot

A correção consolidada da 1.0.16 permanece diretamente no instalador:
`ConfigParser` preserva maiúsculas/minúsculas e resíduos inválidos como
`contrastopacity`, `autocloseidledaemon`, `disabledtrayicon` e
`showstartuplaunchmessage` são removidos antes de gravar as chaves camelCase.

### GNOME Keyring / Seahorse / VS Code

O perfil Cinnamon passa a instalar também `seahorse`, além de `gnome-keyring`
e `libsecret`. O instalador valida a integração PAM do SDDM, mantém o fluxo
nativo SDDM/PAM para criação/desbloqueio do chaveiro `Login` e instala um
fallback de autostart apenas se o pacote `gnome-keyring` deixar de listar
Cinnamon. O VS Code continua recebendo `"password-store": "gnome-libsecret"`
em `~/.vscode/argv.json` no setup da sessão.

Em uma instalação limpa, o chaveiro `Login` deve ser criado/desbloqueado no
primeiro login com senha. O Seahorse fica disponível como ferramenta de
diagnóstico/reparo caso isso não ocorra.

O ajuste do VS Code na 1.0.17 também passou a tratar `argv.json` como JSONC:
a chave `password-store` é inserida/atualizada sem apagar comentários,
`enable-crash-reporter`, `crash-reporter-id` ou outras opções já existentes.

## 1.0.18 — Flutter Android/Web pronto nos três desktops

A revisão 1.0.18 consolida a toolchain Flutter como configuração global do Wolf Linux, independente do ambiente gráfico escolhido.

- adiciona `android-platform` ao conjunto Android, preenchendo `/opt/android-sdk/platforms` e evitando o erro `No valid Android SDK platforms found`;
- mantém `android-sdk`, Build Tools, Command-line Tools e Platform Tools;
- cria `/usr/local/bin/google-chrome -> /usr/bin/google-chrome-stable`, permitindo que o Flutter encontre o Google Chrome para desenvolvimento Web;
- exporta `CHROME_EXECUTABLE=/usr/bin/google-chrome-stable`;
- adiciona `wolf-android-licenses`, que abre o `sdkmanager --licenses` com permissão adequada para o SDK compartilhado em `/opt/android-sdk`;
- amplia `wolf-flutter-doctor` para validar plataforma Android e Chrome antes de executar `flutter doctor -v`;
- adiciona regressões correspondentes ao smoke test do projeto.

A aceitação das licenças Android continua sendo uma ação explícita do usuário:

```bash
wolf-android-licenses
```

Depois:

```bash
flutter doctor
```



## 1.0.19 — Flutter 3.47 / Android SDK: ADB único e licenças compatíveis

A revisão 1.0.19 fecha os dois avisos restantes observados no `flutter doctor`:

- remove `android-tools` do manifesto para não instalar `/usr/bin/adb` em paralelo ao ADB oficial do SDK em `/opt/android-sdk/platform-tools/adb`;
- mantém `android-sdk-platform-tools` como a única implementação de ADB/fastboot usada pelo ambiente Android;
- deixa de instalar o AUR `android-sdk-cmdline-tools-latest`, pois a revisão 23+ mudou o fluxo de licenças e o Flutter 3.47.x ainda o interpreta incorretamente;
- instala diretamente do Google o Android Command-line Tools **22.0** (`commandlinetools-linux-15859902_latest.zip`) e valida o SHA-256 oficial antes de extrair;
- organiza a revisão em `/opt/android-sdk/cmdline-tools/22.0` e mantém `latest -> 22.0`;
- preserva `wolf-android-licenses` para a aceitação interativa das licenças com permissões adequadas em `/opt/android-sdk`;
- amplia `wolf-flutter-doctor` e o smoke test para detectar ADB duplicado e regressões na versão das Command-line Tools.

O pin em 22.0 é temporário. Ele deve ser removido quando a versão Stable do Flutter reconhecer oficialmente o novo fluxo de licenças das Command-line Tools 23+.


## 1.0.20 — Permissões corretas para Flutter e Android SDK

A revisão 1.0.20 consolida o comportamento validado em máquina real para que
`flutter doctor --android-licenses` funcione como usuário comum, sem `sudo`.

- `/opt/flutter` permanece pertencendo ao usuário criado pelo instalador, permitindo que o Flutter mantenha seu próprio cache sem criar arquivos root-owned;
- `/opt/android-sdk` permanece administrado pelo root/pacman, mas o instalador cria o grupo `android-sdk` e adiciona o usuário a ele;
- o pacote oficial `acl` passa a ser instalado explicitamente;
- ACLs de leitura/escrita são aplicadas recursivamente ao SDK Android e ACLs padrão são configuradas nos diretórios para novos arquivos/componentes;
- um hook do pacman reaplica as ACLs após atualização de `android-sdk`, Build Tools, Platform Tools ou `android-platform`;
- `wolf-android-licenses` deixa de elevar privilégios e passa a chamar `flutter doctor --android-licenses` como usuário normal;
- `wolf-flutter-doctor` também verifica a associação ao grupo `android-sdk` e se `/opt/android-sdk` está gravável sem sudo;
- os smoke tests passam a impedir regressões nessas permissões.

Após o primeiro login da instalação, as licenças podem ser aceitas simplesmente com:

```bash
flutter doctor --android-licenses
```

ou pelo atalho:

```bash
wolf-android-licenses
```

Como a associação ao grupo é feita durante a instalação, ela já estará ativa no primeiro login normal do usuário.

## 1.0.21 — Smoke test limpo e sincronização de instalações existentes

- Corrige os avisos `SC2016` do ShellCheck no próprio `wolf-smoke-test.sh` sem
  desativar regras do ShellCheck; os testes continuam comparando texto literal
  do instalador, mas agora escapam explicitamente os `$` procurados.
- Mantém `WOLF_VERSION=1.0.21` no instalador.
- Adiciona `wolf-apply-current-system-hooks-1.0.21.sh`, que pode ser executado
  numa instalação Wolf Linux já existente para instalar/reaplicar:
  - hook `wolf-cinnamon-x11-only.hook`;
  - hook `wolf-android-sdk-permissions.hook`;
  - helper `wolf-fix-android-sdk-permissions`;
  - grupo/ACL do Android SDK;
  - propriedade de `/opt/flutter` para o usuário principal;
  - helper `wolf-android-licenses` sem sudo.

Isso permite atualizar a máquina de desenvolvimento atual sem reinstalação.

## 1.0.22 — MPC-QT e proteção permanente de diretórios

- Retorna `mpc-qt` como player de vídeo padrão e remove `vlc`/`vlc-plugins-all` do perfil multimídia.
- Usa `io.github.mpc_qt.mpc-qt.desktop` apenas para MIME types de vídeo; `inode/directory` é deliberadamente ignorado.
- Adiciona `/usr/local/bin/wolf-protect-directory-handler`, executado a cada login via XDG Autostart.
- Mantém `inode/directory` associado ao gerenciador de arquivos nativo: Nemo no Cinnamon, Caja no MATE e Dolphin no KDE Plasma.
- Adiciona `wolf-fix-directory-handler-1.0.22.sh` para aplicar a mesma proteção a instalações existentes sem reinstalação.

## 1.0.23 — CinnVII como menu padrão e Wolf MultiMonitor v0.2

### Cinnamon: CinnVIIStarkMenu por padrão

O perfil Cinnamon passa a baixar o `CinnVIIStarkMenu@NikoKrause` diretamente do
Cinnamon Spices oficial durante a instalação. No primeiro login, o Wolf Linux
substitui `menu@cinnamon.org` pelo CinnVII preservando painel, posição e ID da
instância. A troca é aplicada uma única vez; depois disso o usuário pode alterar
ou remover o applet sem o sistema forçar sua volta. Se o download do Spice
falhar, o instalador mantém o menu nativo do Cinnamon como fallback.

### Wolf MultiMonitor v0.2 (experimental)

O DevKit inclui `wolf-multimonitor-setup-0.2.sh`, ainda sem aplicação automática
na ISO. O helper mantém o protótipo validado de painel e Alt+Tab independentes
por monitor e troca o menu nativo por uma instância do CinnVII em cada painel.
Ele faz backup antes de alterar a configuração e oferece `restore`. Novas
instâncias do CinnVII tentam clonar a configuração visual da instância já usada
pelo usuário.

O objetivo do v0.2 é validar se o popup do menu e os aplicativos iniciados pelo
painel secundário permanecem no monitor correspondente. A integração
multi-monitor só será ativada automaticamente no instalador após esse teste em
hardware.

## 1.0.24 — Wolf MultiMonitor integrado ao Cinnamon

A revisão 1.0.24 integra o Wolf MultiMonitor ao perfil Cinnamon após validação do protótipo v0.2 em hardware real.

- o watcher inicia automaticamente apenas na sessão Cinnamon X11;
- detecta a topologia no login e mudanças de hotplug durante a sessão;
- cria painel inferior apenas nos monitores ativos que ainda não possuem painel;
- garante CinnVIIStarkMenu e Grouped Window List em cada tela ativa;
- mantém a lista de janelas e o Alt+Tab limitados ao monitor correspondente;
- não remove automaticamente painéis de telas desconectadas, preservando personalizações;
- cria um backup-base antes da primeira alteração automática multi-monitor;
- oferece `status`, `enable`, `disable`, `reconcile` e `restore`;
- `restore` desativa o watcher para impedir que o estado restaurado seja imediatamente reaplicado.

