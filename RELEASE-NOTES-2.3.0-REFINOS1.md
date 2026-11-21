# Wolf Linux 2.3.0 Stable — Refinos 1 (homologação de instalação limpa pendente)

Base: Wolf Linux 2.3.0 Stable KDE Plasma/Wayland, instalada com sucesso em VM e hardware real.
Esta revisão integra ajustes aprovados na instalação física, sem alterar VERSION nem a identidade /etc/os-release (2.3.0).

## Mudanças integradas

1. **NVIDIA 620.x + KWin Wayland**: nos perfis `nvidia-modern` com `nvidia-utils` 620.x, instala `/etc/modprobe.d/90-wolf-nvidia-wayland-multimonitor.conf` com `options nvidia_modeset opportunistic_flip_sync=0`, antes da geração do initramfs do Arch e LTS. Não se aplica a outros drivers, Nouveau ou versões futuras automaticamente. Validado pelo usuário com RTX 4060 e dois monitores (180/60 Hz), inclusive após inicialização com ambos conectados. Monitorar jogos, desempenho e atualizações da NVIDIA; o contorno não é garantia de desempenho idêntico.
2. **Mouse Wayland**: grava `~/.config/kcminputrc` `[Mouse] PointerAccelerationProfile=1` (Flat) como padrão para o usuário instalado, preservando ajustes por dispositivo e alterações posteriores feitas no KCM.
3. **Fastfetch TTY**: Tux ASCII em `/usr/share/wolf-linux/fastfetch/wolf-tux-tty.txt`, somente `config-tty.jsonc`; configuração do Konsole continua com Wolf original.
4. **Thorium AVX2**: `~/.local/share/applications/thorium-browser-avx2.desktop` com `StartupWMClass=Thorium-browser`, baseado no lançador AUR e preservando seções extras. Evita ícone duplicado e ícone de interrogação no gerenciador de tarefas Plasma. Navegador padrão e Flutter permanecem Thorium.
5. **Dolphin**: ação 'Abrir pasta no Visual Studio Code' apenas para perfis com stack Development. Helper Wayland não usa wmctrl/xdotool e abre nova janela.
6. **Formatador USB**: backend UDisks2 da prévia validada, instalado em `/usr/local/bin`; ação **exclusivamente** no widget KDE `Discos e Dispositivos`, filtrada por dispositivos USB hotplug; sem menus de pastas nem lançador universal. Restrições de USB e dupla confirmação mantidas.
7. **Atalhos**: desativa todos os atalhos globais do KWin de navegação/movimentação entre áreas de trabalho virtuais: desktops 1–20, Ctrl+F1–F4, setas entre desktops, próximo/anterior, navegação pela lista/grade e envio de janelas para outros desktops. Mantém uma única área de trabalho. Inclui `Ctrl+F4` como alternativa local para o fechamento em aplicativos KDE que honram KStandardShortcut; preserva Alt+F4, Meta+E e Alt+Tab.
8. **SDDM**: permanece em Xorg somente para o greeter, enquanto o desktop usa Plasma/Wayland. Medição física: Xorg 0,6% de CPU acumulada e RSS ~73 MiB, VRAM 22 MiB; migração não justificada.

## Reversões e precauções

- **NVIDIA**: se o parâmetro causar problemas em jogos ou depois de atualizações, remova somente `/etc/modprobe.d/90-wolf-nvidia-wayland-multimonitor.conf`, execute `sudo mkinitcpio -P` e reinicie. Nunca remova os módulos ou arquivos de configuração base `nvidia-drm.conf`.
- **Mouse**: Sistema > Mouse > Perfil de aceleração para voltar a adaptativo.
- **Thorium/KDE**: o lançador local fica em `~/.local/share/applications/` e pode ser excluído para voltar ao original do AUR; também desfixe/reafixe o ícone se necessário.
- **Formatador**: o dispositivo precisa ser USB; a interface recusa partições internas, discos inteiros e volumes montados fora de caminhos permitidos. Não executar formatação apenas para testar menus.

## Construção / validação

```
cd wolf-linux-devkit-2.3.0-stable-refinos1
python3 tests/wolf-test-kde-2.3.0.py .
python3 tests/wolf-test-kde-refinos1.py .
./gerar-iso.sh
```

Projeto Archiso criado em `~/wolf-linux-2.3.0-refinos1-buildfix1`, separado da Stable anterior. Gerador exige Arch Linux com Archiso instalado. Ainda não foram realizados construção real de ISO, boot de VM nem instalação limpa desta revisão.

## Teste Ctrl+F4 após instalação

- No Thorium, abra duas abas e use `Ctrl+F4`: deve fechar somente a aba atual.
- No Dolphin, teste `Ctrl+F4` e `Ctrl+W` após abrir duas abas. Se essa versão do Dolphin ignorar o atalho padrão KDE, ajuste *Configurar atalhos de teclado → Fechar aba* e informe o resultado antes de homologar o comportamento.
- Confirme que `Alt+F4`, `Meta+E` e `Alt+Tab` funcionam.
