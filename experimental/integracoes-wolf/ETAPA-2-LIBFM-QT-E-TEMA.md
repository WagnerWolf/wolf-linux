# Wolf Linux · Etapa 2 (experimental, sem alterar a release)

## O que já sabemos

- libfm-qt 2.4.0-4; pcmanfm-qt 2.4.1-1; ABI libfm-qt6.so.17.
- `pkgctl` ausente. Instalar o pacote oficial `devtools` quando for compilar.
- O estado 'Pendente' na aba Integrações Wolf é correto: ainda não existe pacote modificado.
- O menu desejado é `Fm::PlacesView::contextMenuEvent()` em `src/placesview.cpp` da tag `2.4.0`.

## Contraste do LXQt Archiver

A imagem mostra fundo escuro e texto de menus quase preto, possivelmente devido à combinação Breeze + paleta Qt customizada. **Não é necessariamente um defeito GTK.**

Teste isolado, sem modificar preferências:

```bash
bash experimental/integracoes-wolf/testar-contraste-qt.sh
```

Como o teste Fusion passou, nesta prévia existe uma aplicação opcional para toda a sessão LXQt, com backup:

```bash
bash experimental/integracoes-wolf/ativar-fusion-wolf.sh --check
bash experimental/integracoes-wolf/ativar-fusion-wolf.sh --apply
```

Reinicie a sessão LXQt. O GTK/Breeze-Dark continua configurado e os aplicativos já abertos não são modificados. O backup do usuário fica em `~/wolf-backups/qt-fusion/`. Para reverter, execute `python3 experimental/integracoes-wolf/wolf-fusion-session.py --restore PASTA_DE_BACKUP` e recupere o antigo script `wolf-appearance-dark` do backup se necessário.

## Desenvolvimento da extensão libfm-qt (sem instalar)

**Não execute na máquina de trabalho nenhum pacote compilado não validado.**

1. Em ambiente de desenvolvimento, obtenha a tag upstream exata e os arquivos de empacotamento do Arch (`devtools`/`pkgctl`).
2. Gere o patch (somente texto):

O comando anterior falhava porque duplicava `experimental/integracoes-wolf/` quando executado de dentro dessa pasta. Agora use:

```bash
# Execute a partir da raiz do projeto wolf-linux-devkit-2.2.0
cd experimental/integracoes-wolf
# Se ainda não clonou:
# git clone --depth 1 --branch 2.4.0 https://github.com/lxqt/libfm-qt.git
python3 ./gerar-patch-libfm-qt-2.4.0.py ./libfm-qt/src/placesview.cpp \
  --output /tmp/wolf-places-usb.patch
git -C ./libfm-qt apply --check /tmp/wolf-places-usb.patch
```

O aviso `detached HEAD` é esperado ao clonar uma tag. `git apply --check` não modifica arquivos.


3. O patch adiciona `Formatar unidade USB…` ao menu de volumes com caminho UNIX_DEVICE. O aplicativo Wolf experimental aceita `--device /dev/XYZ`; é o **formatador**, não a biblioteca, que confirma via `lsblk` se é uma partição USB segura.
4. Compilar em ambiente limpo, gerar pacote Pacman rastreável, verificar ABI/dependências, e só então testar na VM/sistema de teste. **Ainda não há compilação, pacote Wolf ou integração instalada.**
5. O Wolf Package Manager permanecerá marcando `Pendente` até uma versão comprovadamente validada ser distribuída.

## Segurança e atualização

- Não executar `makepkg` como root.
- Não recompilar em hooks do Pacman; apenas detectar mudanças e avisar.
- Não mudar `libfm-qt` no sistema principal durante estes testes.
- Não automatizar uma modificação para uma versão upstream diferente de 2.4.0; exige revisão.
- O formatador original permanece funcionando; arquivo `wolf-format-removable-device-experimental` é apenas uma cópia para desenvolvimento, não é instalado automaticamente.
