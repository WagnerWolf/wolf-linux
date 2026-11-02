# Wolf Linux DevKit 2.2.0-rc1 — LXQt/X11 (PRÉVIA DE INSTALAÇÃO FÍSICA)

**Atenção:** prévia integrada ainda não homologada em instalação física pós-rebuild. A 2.1.3 permanece como última versão estável. Esta distribuição contém o **projeto gerador da ISO**, não uma ISO já compilada.

## Componentes integrados

- Desktop principal LXQt 2.4 / Openbox X11, sem o Plasma Desktop; PCManFM-Qt como explorador padrão (sem Dolphin); Kate/Konsole/Spectacle/Okular/Gwenview mantidos.
- PCManFM-Qt abre pastas e dispositivos, Super+E/Ctrl+Alt+E e atalhos do painel; menu “Abrir pasta no Visual Studio Code” quando a stack Development estiver instalada.
- Personalização Wolf LXQt baseada no configurador Preview 7 e Alt+Tab padrão por monitor da Preview 11.
- Wolf Control Center 0.3.0 Preview 4 e Wolf Package Manager 0.3.5 Preview 2.
- LXQt Archiver padrão; MPC-QT com identificador MIME válido `io.github.mpc_qt.mpc-qt.desktop` na auditoria.
- Dois painéis na instalação inicial (perfil homologado de dois monitores), wallpaper individual, menu Super, Bluetooth Blueman.
- Linux Arch oficial como principal e `linux-lts` reserva; DKMS NVIDIA deve passar nos dois antes de completar instalação.
- SDDM com sessão LXQt/X11, Zsh/P10k e preferências multimídia conforme stack selecionada.

## Construção no Arch Linux (não usar sudo para o próprio wrapper)

```bash
unzip wolf-linux-devkit-2.2.0-rc1.zip
cd wolf-linux-devkit-2.2.0-rc1
./tests/wolf-smoke-test.sh
./gerar-iso-2.2.0-rc1.sh
```

Geração requer `archiso`, acesso à rede, pacman e repositórios atualizados. O gerador cria `~/wolf-linux-2.2.0-rc1` e produz a ISO em `out/`. Ele **não** apaga projetos preexistentes; falha caso o destino já exista.

## Reinstalação preservando /home — verificação obrigatória

1. Fazer backup externo de arquivos insubstituíveis e registrar `lsblk -f`, UUIDs, grupos LVM e localização ESP.
2. Na Live, escolher **Reutilizar / Manual** e identificar separadamente partição raiz, EFI e LV de `/home`.
3. `FORMAT_ROOT=yes`, `FORMAT_ESP=no`, `FORMAT_HOME=no`, `CLEAN_HOME_DOTFILES=no`. Nunca escolher **Apagar disco**.
4. No resumo final, verificar pelo UUID e tamanho se somente a raiz está marcada para formatação.
5. Confirmar UID do usuário original, PVs LVM e montagens de `/home` antes de aceitar.
6. Os arquivos pessoais ocultos **não** são removidos; configurações Wolf são mescladas/arquivadas antes de alteração, mas a reinstalação ainda traz risco. Não confundir preservação com backup.

Se o instalador exibir uma topologia diferente da esperada, **cancelar**, não prosseguir. Não há garantia de segurança apenas pela revisão estática.

## Validação antes de instalar fisicamente

- ISO gerada e validada pelo `wolf-build-iso.sh` (inclui verificação do SquashFS/Live GUI).
- Iniciar a Live em hardware e confirmar teclado, rede, SDDM, discos, UUID, LVM e revisão do plano. Sem necessidade de VM.
- Depois de instalar: `uname -r`, `dkms status`, `nvidia-smi`, `echo "$XDG_SESSION_TYPE"`, `wolf-control-center`, auditoria MIME e Wolf Alt+Tab.

## Conhecidos / ressalvas

- O instalador utiliza linux + linux-lts oficiais; Chaotic-AUR é opcional apenas para aplicativos. Componentes históricos não ativados permanecem arquivados em scripts e documentação legada.
- O esquema inicial é configurado para **dois monitores** (seu hardware atual); em topologia diferente, ajustar no Control Center.
- Chrome com `GTK_MODULES=` é mitigação experimental baseada em testes de estabilidade, não diagnóstico definitivo.
- O build do Archiso e a instalação física **não foram executados neste ambiente**.

