# Wolf Linux 2.2.0 — ajuste de posição de janelas e chaveiro VS Code

Base: release 2.2.0 LXQt / Monitores / SmokeFix1. A identificação da release
permanece 2.2.0. Nenhuma alteração em particionamento, GRUB, kernels,
NVIDIA DKMS ou na instalação BIOS/UEFI/LVM.

## Monitor de origem

Openbox já está configurado com posicionamento Smart/Mouse. Isso funciona
para novas janelas que deixam o gerenciador decidir a posição, mas não impede
aplicativos Electron de reutilizarem janela existente ou restaurarem a
geometria anterior.

A ação **Abrir pasta no Visual Studio Code** do PCManFM-Qt agora usa
`/usr/local/bin/wolf-open-vscode-monitor`, com `code --new-window`.
Ela registra o monitor do ponteiro **no instante do acionamento**, observa
apenas uma nova janela do VS Code no X11, e a coloca nessa tela. Não instala
serviço persistente, não move instâncias antigas do VS Code e não interfere
com o Alt+Tab por monitor.

Limitações: aplicativos que não permitem criar janela nova, janelas que
forçam sua posição e chamadas que não passam pelo menu do PCManFM-Qt podem
manter o comportamento próprio. Monitoramento genérico de todas as janelas
não foi introduzido nesta release.

## Credenciais seguras

O LXQt recebe `gnome-keyring`, `libsecret` e `seahorse`. O autostart
`gnome-keyring-secrets.desktop` é habilitado apenas para LXQt; a integração
PAM com SDDM é verificada antes de acrescentar linhas opcionais ausentes.
O perfil Development configura o VS Code com
`~/.vscode/argv.json` -> `"password-store": "gnome-libsecret"`.
Não usa `basic` e não copia senhas ou chaves para o DevKit.

O cofre de login é desbloqueado automaticamente **somente** quando o SDDM
recebe a senha do usuário e ela corresponde à senha do chaveiro. Autologin
sem senha ou cofre com senha diferente podem exigir desbloqueio manual pelo
Seahorse. Um `argv.json` JSONC com comentários é intencionalmente preservado
sem edição automática, para não destruir preferências já existentes.

## Verificação após instalar a ISO

1. Entrar no LXQt/X11, preferencialmente com senha no SDDM.
2. No PCManFM-Qt, abrir uma pasta pelo menu de contexto em cada monitor,
   confirmando que janelas anteriores do VS Code não mudam de tela.
3. Iniciar o VS Code e testar login/sincronização, sem selecionar criptografia
   básica. Se houver mensagem de cofre bloqueado, abrir Seahorse.
4. Verificar `pgrep -af gnome-keyring-daemon` e
   `grep -E 'pam_gnome_keyring' /etc/pam.d/sddm`.
5. Confirmar que painel, Alt+Tab, aplicações de rede e mídias permanecem OK.

Teste estático: `./tests/wolf-smoke-test.sh`.
