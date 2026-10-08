# Wolf Linux DevKit 2.0.0-alpha18

Baseline **KDE Plasma / Wayland** com preparação limpa, helpers completos porém
**Branding/MultiMonitor automáticos uma vez no primeiro login**, demais helpers manuais,
validação guiada e VM persistente fácil de retomar.

## Fluxo recomendado

Não faça upgrade incremental nesta fase. Recrie o projeto:

```bash
rm -rf ~/wolf-linux
chmod +x preparar_ambiente_wolf_linux.sh
./preparar_ambiente_wolf_linux.sh
```

O preparador parte de `/usr/share/archiso/configs/releng`, recria
`~/wolf-linux`, customiza a ISO, faz staging do SSH live e roda o smoke test.

## Build

```bash
cd ~/wolf-linux
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
