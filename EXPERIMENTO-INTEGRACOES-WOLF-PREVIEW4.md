# Integrações Wolf Preview 4 — preparação de pacote libfm-qt

**Experimental. Não integra nem substitui a release estável 2.2.0.** O Fusion foi aprovado no LXQt instalado e foi preservado; não houve alteração no tema.

## Objetivo

Preparar a modificação da versão EXATA `libfm-qt 2.4.0-4` (ABI `libfm-qt6.so.17`) com a ação **Formatar unidade USB…** no menu de dispositivos da barra lateral. O formatador valida o dispositivo USB e exige confirmação. O patch C++ não executa formatação diretamente.

## Etapa A — checar o patch na fonte real (sem instalar)

Os comandos abaixo devem ser executados **a partir da raiz do DevKit**. Se você já clonou `libfm-qt` na prévia anterior, passe o caminho antigo de sua cópia; NÃO é necessário clonar de novo.

```bash
# Onde estão os scripts da Preview 4
DEVKIT="$PWD"
# Exemplo: alterar se o clone anterior estiver em outro local
SOURCE="$HOME/Projetos/wolf-linux/experimental/integracoes-wolf/libfm-qt"

python3 "$DEVKIT/experimental/integracoes-wolf/gerar-patch-libfm-qt-2.4.0.py" \
  "$SOURCE/src/placesview.cpp" --output /tmp/wolf-places-usb.patch

git -C "$SOURCE" apply --check /tmp/wolf-places-usb.patch
```

Se `git apply --check` falhar, **não compile o pacote**: envie a saída para revisão.

## Etapa B — obter a receita de empacotamento do Arch

Em um Arch de teste (preferencialmente VM), instale as ferramentas, se necessário, e clone o repositório oficial de receitas por HTTPS:

```bash
sudo pacman -Syu --needed devtools base-devel
mkdir -p "$HOME/wolf-build-test"
cd "$HOME/wolf-build-test"
pkgctl repo clone --protocol=https libfm-qt
```

O checkout atual pode estar numa revisão diferente. O preparador **recusa** qualquer `PKGBUILD` que não corresponda a `pkgver=2.4.0`, `pkgrel=4`, tenha uma função `prepare()` não tratada ou já contenha outro patch Wolf. Nesse caso, pare para ajustarmos à revisão correta — não force.

## Etapa C — criar receita experimental rastreada pelo Pacman

Da raiz do DevKit Preview 4:

```bash
DEVKIT="$PWD"
SOURCE="$HOME/Projetos/wolf-linux/experimental/integracoes-wolf/libfm-qt"
python3 "$DEVKIT/experimental/integracoes-wolf/preparar-pacote-libfm-qt-2.4.0.py" \
  --source "$SOURCE/src/placesview.cpp" \
  --packaging "$HOME/wolf-build-test/libfm-qt" \
  --output "$HOME/wolf-build-test/libfm-qt-wolf-2.4.0-4.1"
```

O resultado contém um `PKGBUILD` derivado da receita oficial com `pkgrel=4.1`, o patch com SHA512 e uma nota de proveniência. O preparador não instala, não recompila e não chama `pacman`. Se o diretório de saída existir, ele recusa sobrescrevê-lo.

## Etapa D — build em ambiente limpo e teste em VM

```bash
cd "$HOME/wolf-build-test/libfm-qt-wolf-2.4.0-4.1"
# Revise o PKGBUILD antes de compilar
less PKGBUILD
pkgctl build
```

O `pkgctl build` constrói em um chroot limpo, sem instalar o resultado no host. Não usar `--install-to-host` ou `sudo pacman -U` no computador principal. Registre os erros de build; um pacote compilado **não significa** extensão validada. A etapa posterior será teste do menu do PCManFM-Qt em VM com o formatador Wolf atualizado que suporta `--device`, seguido de rollback para o `libfm-qt` oficial.

## Critérios para futura integração no Wolf Package Manager

- `git apply --check` e compilação do pacote passam contra a fonte real.
- `libfm-qt6.so.17` e os símbolos exigidos pelo PCManFM-Qt são preservados.
- A ação abre o formato correto somente em volumes elegíveis; o formatador recusa unidades internas.
- Formatação não é iniciada sem confirmação explícita.
- Reversão para pacote oficial testada em VM.
- Manifesto de compatibilidade só é marcado `validated=true` **depois** de teste real; até lá o Package Manager deve continuar mostrando **Pendente**.
- Hook do Pacman segue apenas registrando mudanças, sem recompilar nada.

Nenhuma ISO atualizada é necessária nesta fase.
