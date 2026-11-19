# Wolf libfm-qt — Reconstrução unificada 0.4 (Preview 4)

**Objetivo:** substituir a dependência do antigo `~/wolf-libfm-build/libfm-qt-wolf-2.4.0-4.1/src` por uma reconstrução integral a partir das fontes verificadas, com os dois patches Wolf na mesma receita.

**Status:** testes locais de integração e geração dos patches passaram. A compilação real com Qt6 e a validação da interface no Wolf Linux ainda **não foram executadas**. A release atual do DevKit não é alterada.

## O que acontece automaticamente

1. Verifica ferramentas e a instalação atual de `libfm-qt 2.4.0-4.1` ou `2.4.0-4.2` (recusa revisões inesperadas).
2. Cria **nova pasta de trabalho** em `~/wolf-libfm-build/`, sem apagar builds anteriores.
3. Clona `https://github.com/lxqt/libfm-qt.git` **na tag 2.4.0**, validando o commit conhecido `4294f29…` e a árvore limpa.
4. Clona `https://gitlab.archlinux.org/archlinux/packaging/packages/libfm-qt.git`, recupera a **receita oficial histórica 2.4.0-4**, mesmo se a branch atual contiver 2.5.0 ou outra revisão; recusa se não encontrar receita compatível.
5. Recria `wolf-places-usb.patch` (sidebar: **Formatar unidade USB…**) e `wolf-symlinks-native.patch` (menus de itens/fundo) a partir dos arquivos C++ originais.
6. Verifica ambos os patches com `patch --dry-run --fuzz=0`; gera um PKGBUILD **único** `libfm-qt 2.4.0-4.2`, com SHA512 para cada patch.
7. Executa `makepkg --verifysource`, `makepkg -s -C` e `pacman -Qp`, sem `--skipchecksums` e sem ignorar erros.
8. Grava um `MANIFEST.json` com commits e hashes para auditoria/reprodução.

**Não atualiza automaticamente para versões upstream novas:** em 2.5.x ou outra versão não validada, a rotina **bloqueia**. Atualizar a libfm-qt requer portar e testar ambos os patches, sem perder o USB nem o menu de links. A proteção via `IgnorePkg` continua necessária.

## Executar no Arch / Wolf Linux (usuário normal)

```bash
cd "$(xdg-user-dir DOWNLOAD)"
unzip wolf-libfm-qt-unificado-0.4-preview4.zip
cd wolf-libfm-qt-unificado-0.4-preview4

# Testes sem qualquer modificação do sistema
python3 -m unittest discover -s tests -v

# Fluxo completo: clonar, criar ambos patches, verificar, baixar fontes e compilar
python3 reconstruir-libfm-wolf.py
```

O comando padrão **não instala** a biblioteca nem modifica o Package Manager. Mostra o caminho `~/wolf-libfm-build/wolf-libfm-2.4.0-4.2-<data>/build-4.2/` contendo o `.pkg.tar.zst`.

Se estiver faltando `git`, `patch`, `makepkg` ou outras ferramentas de compilação:

```bash
sudo pacman -S --needed base-devel git
```

`makepkg -s` solicita a instalação das dependências de build do Arch que estiverem faltando.

### Somente preparar, sem compilar

```bash
python3 reconstruir-libfm-wolf.py --preparar-apenas
```

## Instalar experimentalmente, se decidir validar na VM/estação

```bash
python3 reconstruir-libfm-wolf.py --instalar
```

Esta opção **repete o processo inteiro** e, depois de compilar 4.2, compila **também 4.1 com o patch USB**, guardando um pacote de rollback, verifica `pacman-conf IgnorePkg`, a versão do Wolf Package Manager 0.3.7 e atualiza seu `upgrade_guard.py` com backup antes da instalação. Só depois chama `sudo pacman -U` para a biblioteca 4.2 e `instalar-helper.py` para instalar o backend e retirar (com backup) as ações `.desktop` antigas. Se uma pré-condição não for satisfeita, a instalação é bloqueada.

**Importante:** sair da sessão LXQt e executar `--instalar` em TTY é preferível porque a biblioteca será usada por processos gráficos abertos. Depois entre novamente na sessão. O script nunca reinicia o painel e não interfere nas configurações de dois monitores.

O pacote de **rollback 4.1** fica em `~/wolf-libfm-build/wolf-libfm-2.4.0-4.2-<data>/rollback-4.1/`. Para reverter a biblioteca (após encerrar a sessão gráfica):

```bash
sudo pacman -U /CAMINHO/COMPLETO/rollback-4.1/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst
```

Se o guard foi modificado, seu backup fica em `upgrade_guard.py.bak-wolf-4.2-*`. As antigas ações `.desktop` têm backup em `~/.local/share/wolf-symlinks/backups/`. No rollback, retirar ou revisar a integração do helper nativo evita manter menus em estado incoerente.

## Comportamento esperado a validar

| Contexto | Opções Wolf |
|---|---|
| Clique direito em arquivo/pasta selecionado | **Criar link simbólico aqui** e **Criar link simbólico em…** |
| Clique direito em fundo vazio da pasta | **Colar como links simbólicos nesta pasta** (a partir de Ctrl+C) |
| Clique direito em volume na barra lateral | **Formatar unidade USB…** (integrado anteriormente) |

Validar também: nomes com espaços, links na mesma pasta, conflitos de nomes, permissões, PCManFM-Qt, painel por monitor, e ausência de duplicação das ações da Preview 1/2. **Não tratar a compilação como homologação gráfica.**

## Atualizações futuras

O script é reprodutível para **libfm-qt 2.4.0-4**. Não remova o `IgnorePkg` nem aceite atualização upstream automaticamente pelo Pacman até que **todos os patches** sejam portados para a versão nova, compilados e testados no hardware. Essa interrupção deliberada é mais segura do que uma atualização parcial.
