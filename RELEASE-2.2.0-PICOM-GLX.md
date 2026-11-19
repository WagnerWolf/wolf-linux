# Wolf Linux 2.2.0 — Picom GLX/VSync integrado à release

## Homologação no hardware físico (02/11/2026)

- LXQt/Openbox/X11 preservados; Picom GLX/VSync com configurações conservadoras.
- Usuário confirmou fundo opaco nos dois painéis Wolf-dark com Picom ativo.
- Notificações da Steam passam a renderizar corretamente com compositor.
- Não foi demonstrada correção dos microtravamentos raros no Chrome; continuar monitorando sem atribuir causalidade.

## Nova instalação

O perfil LXQt instala o pacote oficial `picom` e prepara, com backup:

- `~/.config/picom/picom.conf`: GLX + VSync, sem sombras, fades, transparência ou blur.
- `~/.config/autostart/wolf-picom.desktop`: inicialização por guard de VM somente LXQt (não Plasma nem Wayland).
- `~/.local/share/lxqt/themes/wolf-dark/lxqt-panel.qss`: fundo opaco `#242a34`.

A reaplicação de Wolf-dark pelo Control Center utiliza `THEME_QSS` do configurador
atualizado, portanto não remove mais o fundo opaco do painel. O configurador
preserva o arquivo de configuração e o autostart Picom caso já existam num
`/home` reutilizado; não sobrescreve escolhas do usuário.

## Testes pós-instalação (executar no Wolf Linux LXQt)

```bash
pacman -Q picom
pgrep -a -u "$(id -u)" -x picom
cat ~/.config/picom/picom.conf
cat ~/.config/autostart/wolf-picom.desktop
```

Teste os painéis nos dois monitores, notificações da Steam, Alt+Tab, vídeos
e jogos. Para desativar a inicialização na próxima sessão, sem remover o
pacote Picom, execute:

```bash
mkdir -p ~/.config/autostart
cp -a ~/.config/autostart/wolf-picom.desktop ~/.config/autostart/wolf-picom.desktop.backup
sed -i '/^Hidden=/d' ~/.config/autostart/wolf-picom.desktop
printf '\nHidden=true\n' >> ~/.config/autostart/wolf-picom.desktop
```

Encerre a sessão e entre novamente. Para reativar, retire `Hidden=true`
do arquivo `.desktop`, ou use o controle experimental
`python3 experimental/picom/wolf-picom-lxqt.py --enable` quando estiver na
árvore do DevKit e tiver certeza de que o arquivo é Wolf. Não habilite dois
compositores simultaneamente.

## Escopo

Sem alterações em kernéis, NVIDIA, Openbox, regras de Alt+Tab, PCManFM-Qt,
biblioteca `libfm-qt` Wolf, particionamento, Chrome ou proteção IgnorePkg.
O Package Manager permanece na versão 0.3.7. A ISO gerada com esta revisão
continua dependendo do pacote `libfm-qt 2.4.0-4.1` compilado pelo usuário.


## Atualização Preview 4 — proteção de VM

O autostart chama `~/.local/bin/wolf-picom-session` que verifica `systemd-detect-virt --vm` na sessão. Em VM omite o compositor por padrão; em físico mantém GLX/VSync. `~/.local/bin/wolf-picom-session --status` informa o modo escolhido. Para ensaiar XRender em VM, use `WOLF_PICOM_VM_MODE=xrender ~/.local/bin/wolf-picom-session` em um terminal, depois de parar outros compositores. Não é ativado automaticamente.
