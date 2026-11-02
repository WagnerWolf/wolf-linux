# Wolf Linux DevKit 2.2.0 — Release LXQt/X11

**Versão 2.2.0 com Package Manager 0.3.7 (integração USB e proteção validadas em VM, 02/11/2026).**
Esta distribuição contém o **DevKit gerador da ISO**, não uma ISO compilada.
A integração de libfm-qt e a proteção do Pacman passaram no teste em VM. A reinstalação física com esta compilação específica continua pendente.

## Componentes da release

- LXQt / Openbox X11, com **PCManFM-Qt** como explorador padrão, inclusive atalhos `Super+E`, `Ctrl+Alt+E` e lançadores. Dolphin não integra os perfis de instalação.
- Painel principal completo com Status Notifier, tray, áudio, rede, Bluetooth e dispositivos removíveis; painel secundário simplificado somente quando há duas telas; `wolf-lxqt-monitors` reaplica a disposição por demanda.
- Locais do PCManFM-Qt: diretórios XDG pessoais (Documentos, Downloads, Imagens, Músicas, Vídeos), preservando favoritos extras ao reutilizar `/home`.
- Gerenciamento de rede: NetworkManager, `nm-applet --indicator` e editor de conexões.
- Mídias: Udiskie, GNOME Disks, integração de formatação via menu de contexto com verificações de segurança.
- Kernel Arch oficial **`linux`** como principal e **`linux-lts`** como reserva; headers e módulos DKMS correspondentes. Chaotic-AUR é opcional para aplicativos, não determina a escolha de kernels.
- Wolf Control Center, Wolf Package Manager, Alt+Tab por monitor, branding Wolf; Zsh, Kate, Konsole, Spectacle, Okular, Gwenview e MPC-QT conforme perfil.
- Correção da identidade `os-release` da RC1 e mitigação/diagnóstico experimental de falhas do Chrome.


## Integração USB e Package Manager 0.3.7 (02/11/2026)

- A versão `libfm-qt 2.4.0-4.1` modificada inclui “Formatar unidade USB…” no menu de **dispositivos** do PCManFM-Qt; a ação antiga no interior de pastas foi removida.
- O formato Wolf suporta FAT32, exFAT, NTFS e ext4 e recebe o dispositivo via `--device`. É necessário o pacote personalizado compilado separadamente em `release-packages/`.
- O instalador habilita `IgnorePkg = libfm-qt` após instalar a biblioteca Wolf. O Wolf Package Manager **0.3.7** alerta e preserva a personalização em atualizações gerais, mas `IgnorePkg` não bloqueia toda instalação explícita.
- O botão **Planejar atualização libfm-qt** apresenta instruções e estados; **não adapta, compila nem instala patches automaticamente**.
- Foi validado na VM: `libfm-qt 2.4.0-4.1`, `pacman-conf IgnorePkg`, `wolf-libfm-guard --check`, `wolf-integrations-check`; teste gráfico do menu USB havia sido validado separadamente em hardware físico.
- O pacote `libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst` não está incluído neste ZIP, pois foi construído na máquina do mantenedor. Sem ele a geração da ISO deve falhar.

Comandos completos e checklist atualizados: `RELEASE-2.2.0-PM-0.3.7.md`.

## Gerar a ISO (Arch Linux)

```bash
unzip wolf-linux-devkit-2.2.0-lxqt-pm-0.3.7-release.zip
cd wolf-linux-devkit-2.2.0
cp "$HOME/wolf-libfm-build/libfm-qt-wolf-2.4.0-4.1/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst" ./release-packages/
bash tools/wolf-integration-monitor/validar-pacote-usb.sh ./release-packages/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst
bash tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-pm-0.3.7-release" ./gerar-iso-2.2.0.sh
```

É necessário `archiso`, `pacman`, conexão de rede e espaço disponível. O gerador usa por padrão `~/wolf-linux-2.2.0` e produz a ISO no subdiretório `out/`. **Por segurança, não sobrescreve um diretório de projeto preexistente.** Pode-se definir outro local com `WOLF_BUILD_PROJECT=/caminho/novo`.

## Reinstalação com preservação de `/home`

1. Faça backup externo dos dados e registre `lsblk -f`, UUIDs, ESP, PVs e LVs.
2. Selecione Reutilizar/Manual e confira individualmente raiz, EFI e `/home` na revisão gráfica.
3. Para preservar o volume de dados: `FORMAT_ROOT=yes`, `FORMAT_ESP=no`, `FORMAT_HOME=no` e `CLEAN_HOME_DOTFILES=no`.
4. Confirme que somente a raiz está marcada para formatação; verifique UID e permissões do usuário antigo.
5. Se a topologia apresentada não coincidir com a real, **cancele**. Mesmo o modo de preservação não substitui backup.

## Estado de validação

- **Aprovado pelo mantenedor:** instalação e uso inicial em VM na base RC1 Patch 6, promovida sem alterações funcionais na lógica do desktop ou particionamento.
- **Verificação neste DevKit:** smoke test estático, sintaxe, validações de versão/identidade e regressões de desktop/multidisco.
- **Ainda não homologado nesta release:** instalação/boot em hardware real, NVIDIA DKMS em dois kernels físicos, mídia removível real e alternância de monitores no hardware específico.

Para detalhes consulte `RELEASE-NOTES-2.2.0.md`. Versões anteriores e correções intermediárias permanecem documentadas nos arquivos históricos.

### Sobre o configurador de monitores nativo

O aplicativo `lxqt-config-monitor` faz parte do pacote `lxqt-config`. A release o mantém **inalterado**, e mantém também o Wolf Control Center. Se desejar ocultar somente a entrada do menu, use uma sobreposição `.desktop` com `NoDisplay=true`; não remova o pacote nem a entrada `lxqt-config-monitor-autostart.desktop` sem uma validação separada.

## Monitores (integração pós-homologação da release 2.2.0)

Use `wolf-control-center --monitors` ou `wolf-monitors` para abrir o editor visual sem a janela principal. O menu LXQt apresenta **Monitores (Wolf Linux)**; a entrada nativa é ocultada sem remover `lxqt-config`. O configurador LXQt salva backup do override ao reaplicar o perfil.
