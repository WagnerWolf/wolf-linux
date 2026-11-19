# Wolf Menu Editor — Preview 1

Editor nativo PySide6/Qt para o menu do LXQt/Openbox. **Prévia para testar no hardware real; ainda não incorporada à ISO.**

## Instalação

O Wolf Linux 2.2.0 já usa PySide6. Caso não esteja disponível:

```bash
sudo pacman -S --needed pyside6
```

Extraia o ZIP, entre na pasta e execute:

```bash
python3 wolf-menu-editor.py --self-test
/usr/bin/python3 wolf-menu-editor.py --check
bash instalar.sh
~/.local/bin/wolf-menu-editor
```

Ou abra **Editor do Menu (Wolf Linux)** pelo menu LXQt.

## Recursos

- Busca, lista entradas globais e pessoais, inclusive ocultas.
- Cria lançadores pessoais com nome, comando, descrição, ícone, categorias, diretório de trabalho e terminal.
- Edita aplicativos do sistema **por sobreposição local**, sem modificar `/usr/share/applications`.
- Oculta uma entrada do menu (não desinstala o aplicativo).
- Restaura a entrada original do pacote quando houver sobreposição local.
- Exclui apenas entradas pessoais sem correspondente global.
- Preserva outras seções dos arquivos `.desktop`, inclusive ações e campos não editados.
- Faz backups das personalizações antes de modificá-las ou excluí-las.

## Onde ficam os dados

- Entradas editadas: `~/.local/share/applications/`
- Backups: `~/.local/share/wolf-menu-editor/backups/`
- Programa: `~/.local/share/wolf-linux/menu-editor/`
- Lançador: `~/.local/share/applications/wolf-menu-editor.desktop`

**Nota sobre categorias:** o editor altera o campo `Categories=` dos lançadores e oferece categorias XDG comuns; a criação de categorias totalmente novas no arquivo `.menu` será uma funcionalidade futura.

## Segurança

O editor não deve ser iniciado com sudo e nunca edita nem remove arquivos de aplicativos do sistema. Ocultar um item não desinstala o pacote; para desinstalar softwares use o Wolf Package Manager.

Se uma mudança não aparecer imediatamente no menu, aguarde um pouco ou encerre e entre novamente na sessão LXQt. Não reinicie manualmente o painel duplo.

## Desinstalação

```bash
bash desinstalar.sh
```

Entradas pessoais e backups permanecem no computador.
