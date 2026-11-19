# Wolf libfm-qt 2.4.0-4.2 — Correção de build (Next Preview 2)

A Preview 1 incluía `FindMenuCache.cmake` no cache do usuário e tentava
comunicá-lo ao CMake por `CMAKE_TOOLCHAIN_FILE`. No sistema testado a variável
não resolveu `find_package(MenuCache)`; a compilação parou antes de gerar pacote.

Na Preview 2, o próprio PKGBUILD recebe `FindMenuCache.cmake` como fonte local
verificada com SHA-512, e em `prepare()` copia para
`libfm-qt-2.4.0/cmake/FindMenuCache.cmake`. O CMakeLists do upstream 2.4.0
adiciona essa pasta ao `CMAKE_MODULE_PATH`; assim a solução independe do
ambiente e do cache do CMake.

O patch `wolf-legacy-getpgid.patch` adiciona `_DEFAULT_SOURCE` e o include de
`unistd.h` no arquivo `src/core/legacy/fm-app-info.c`, em lugar do antigo
workaround com `-include unistd.h` via toolchain.

A `libfm-qt` que já está instalada NÃO é removida nem modificada por
`python3 reconstruir-libfm-wolf.py` sem opções. `--instalar` permanece explícito.
Não usar `--skippgpcheck`, `--skipchecksums` ou downgrade de LXQt 2.5.

## Execução

```bash
python3 -m unittest discover -s tests -v
python3 reconstruir-libfm-wolf.py
```

O pacote ficará sob `~/wolf-libfm-build/wolf-libfm-2.4.0-4.2-*/build-4.2/`.
É necessário copiar o pacote gerado para `release-packages/` no DevKit
para permitir o build da ISO. Sem pacote 4.2 o gerador bloqueia.

Status: testes estáticos e integração simulada de `prepare()` passaram neste
ambiente. Compilação real com `makepkg`/Arch e geração de ISO pendentes.
