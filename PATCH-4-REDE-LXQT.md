# Wolf Linux DevKit 2.2.0-rc1 — Patch 4: rede na bandeja LXQt

Base: Patch 3 (mídias removíveis). Preserva identidade 2.2 RC1, PCManFM-Qt, Udiskie, GNOME Disks, kernels e instalação multidisco/LVM.

## Mudanças

- `network-manager-applet` e `nm-connection-editor` são obrigatórios na stack LXQt, vindos do repositório oficial `extra` do Arch.
- `NetworkManager.service` já era habilitado pelo instalador. Não introduzimos ConnMan, systemd-networkd, dhcpcd ou outro daemon de rede concorrente.
- `tools/lxqt/configurar.py` gera `~/.config/autostart/nm-applet.desktop` com `Exec=nm-applet --indicator` e `OnlyShowIn=LXQt;`.
- O arquivo tem **o mesmo nome** que `/etc/xdg/autostart/nm-applet.desktop` instalado pelo pacote: a precedência XDG garante um único lançamento, em vez de dois applets.
- A bandeja e o Status Notifier já configurados no primeiro painel LXQt recebem o indicador. Em uma instalação com dois monitores, o ícone fica no painel primário.
- Todos os arquivos de usuário alterados pelo configurador entram no backup versionado `~/wolf-backups/lxqt/`, inclusive um autostart antigo ou desabilitado.
- Editor de perfis pelo aplicativo `nm-connection-editor` e menu do applet; Wi-Fi, Ethernet e VPNs disponíveis conforme dispositivos/plugins instalados.

## Uso em instalação existente, sem gerar ISO

Na sessão LXQt atual, como usuário normal:

```bash
sudo pacman -Syu --needed network-manager-applet nm-connection-editor
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/nm-applet.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Conexões de rede (Wolf LXQt)
Exec=nm-applet --indicator
TryExec=nm-applet
OnlyShowIn=LXQt;
X-LXQt-Need-Tray=true
Terminal=false
NoDisplay=true
DESKTOP
# Para validar imediatamente, execute uma vez:
nm-applet --indicator &
```

**Atenção**: se um `nm-applet` já estiver rodando, não inicie uma segunda instância manual. Verifique com `pgrep -af nm-applet`. O novo autostart entrará em vigor na sessão seguinte. O NetworkManager deve estar ativo (`systemctl is-active NetworkManager`). Não reinicie nem desabilite a rede remotamente durante os testes.

## Diagnóstico

```bash
systemctl is-enabled NetworkManager
systemctl is-active NetworkManager
nmcli general status
pgrep -af nm-applet
ls -l ~/.config/autostart/nm-applet.desktop
nm-connection-editor
```

## Testes não destrutivos

```bash
./tests/wolf-smoke-test.sh
python3 tests/wolf-test-network-tray.py
```

Os testes validam manifesto de pacotes, executáveis esperados, autostart único, suporte do painel, restauração de `/home` e regressões anteriores. **Ainda requer teste gráfico real**: ícone na bandeja, seleção Wi-Fi, solicitação de senha, reconexão, Ethernet e perfis VPN em hardware físico.
