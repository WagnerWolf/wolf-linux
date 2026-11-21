# Wolf Linux 2.3.0-rc1 — Preview KDE Plasma / Wayland

## Fonte
Derivado diretamente do último DevKit 2.2.0 LXQt/X11 enviado pelo mantenedor, **sem reescrever as rotinas de disco**.
A Live permanece **Openbox/X11**, com Wi-Fi, terminal, PCManFM-Qt, resgate e instalador gráfico.
A instalação alvo, inclusive no perfil Minimal, é **Plasma Wayland**, sem LXQt/Openbox/Picom.

## Recuperado
- Plasma Wayland (sessao plasma.desktop, SDDM com greeter Xorg separado); Dolphin, Konsole, Kate, Okular, Gwenview, Ark, KCalc;
  redes Plasma-NM, áudio Plasma-PA, KScreen/KWin, portals KDE, XWayland, KWallet.
- Wolf Package Manager 0.3.7, Arch/Chaotic/AUR, verificação de atualizações, autostart KDE;
  GRUB Manager, gamepad, Control Center e resolução do instalador.
- Perfil visual Breeze Dark, Papirus-Dark, wallpaper e ícone Kickoff Wolf pelo helper original de primeiro login;
  dois painéis com tarefas por monitor via Plasma MultiMonitor 0.3 (one-shot, sem watcher).
- Alt+Tab filtrado pela tela corrente com KWin `TabBox/MultiScreenMode=1`, 1 desktop virtual;
  KScreen para frequências mistas 180/60 Hz, sem XRandR/ForceCompositionPipeline.
- Perfis Minimal/Basic/Test/Full e kernel Arch principal + LTS de reserva da base 2.2.0.

## Desativado apenas no sistema instalado
- LXQt/Openbox/Picom, lxqt-config-monitor/Monitor Guard, alternador X11 próprio;
  PCManFM-Qt, libfm-qt Wolf ABI 17/IgnorePkg, formatador contextual do PCManFM-Qt;
  helper de links simbólicos exclusivo libfm, xsettingsd e gerenciador Wolf XRandR.
- LXQt Clip: KDE usa o **Klipper nativo**, que preserva clipboard no fechamento das aplicações.
  O SVG branco aprovado está preservado como asset opcional, sem sobrepor os ícones KDE.

## Pendências para homologação
- VM: Boot de ISO, BIOS/UEFI, disco virtual, login realmente Wayland, falta de Discover,
  KDE predefinido, kernel/DKMS, temas, painel por tela; testas em 1 e 2 monitores.
- Hardware: NVIDIA RTX 4060 180/60 Hz, travamentos de vídeo, suspensão, logind e KWin.
- Portar ao Dolphin a ação de formatar unidade USB da barra lateral e o helper de links simbólicos;
  **não** instalar biblioteca libfm-qt modificada nem alegar equivalência já disponível.
- Subtitles/VS Code por monitor: no KDE/Wayland devem usar KWin/Dolphin, não X11/PCManFM.
- Conferir atalhos Meta+E, Ctrl+Alt+T e Super e aceleração do mouse flat usando KWin
  (a opção de tela atual para Alt+Tab está preconfigurada; demais precisam validação no KDE).
- Validar perfis de áudio, screenshots, SDDM Astronaut, autenticação KWallet/Secret Service.
- Não migrar o perfil de usuário LXQt existente automaticamente e não executar remoção de pacotes
  ou reinstalação em máquinas reais sem plano/backup específico.

## Gerar projeto e ISO em Arch Linux

```
./preparar_ambiente_wolf_linux.sh --project "$HOME/wolf-linux-2.3.0-rc1" --skip-deps
# ou ./gerar-iso-2.3.0-rc1.sh (instala archiso e chama o build)
cd "$HOME/wolf-linux-2.3.0-rc1"
python3 tests/wolf-test-kde-2.3.0-rc1.py .
./tests/wolf-build-iso.sh
```

**Atenção:** não é versão Stable. O smoke é estático, sem pacstrap, mkarchiso nem boot real.
O procedimento de geração exige os pacotes oficiais atuais e conexão com repositórios.
