# Wolf Linux 2.3.0 Stable — Refinos 1 BuildFix 3

## Falha corrigida

Na retomada do projeto `wolf-linux-2.3.0-refinos1-buildfix1`, a preparação anterior recuperava somente o wallpaper, mas o projeto também podia estar sem o SVG original do Kickoff (`assets/kde/wolf-linux-kickoff.svg`). O teste KDE então abortava com `[FALHA] branding Plasma SVG`.

Esta versão verifica **todos os assets fornecidos com o DevKit**, confirma que `assets/` e `branding-assets/` têm conteúdo idêntico e restaura **somente arquivos ausentes** no projeto interrompido. Arquivos existentes e divergentes bloqueiam a retomada e nunca são sobrescritos. Antes de concluir o preparador, confirma também que todos os assets foram realmente transportados para `iso-profile/airootfs/root/wolf-linux/assets/`.

## Retomar o projeto, sem perder a preparação anterior

Extraia este DevKit BuildFix 3 em pasta separada e, dentro dela, execute:

```bash
./preparar_ambiente_wolf_linux.sh --resume --skip-deps
./gerar-iso.sh
```

Por padrão, ambas as operações trabalham no projeto anteriormente criado:

`~/wolf-linux-2.3.0-refinos1-buildfix1`

Não apague o projeto e não copie manualmente um SVG alternativo: o DevKit já contém o arquivo exato, com verificação de integridade.

## Testes

```bash
python3 tests/wolf-test-build-assets-2.3.0.py .
python3 tests/wolf-test-kde-2.3.0.py .
```

A aplicação ao projeto interrompido, as verificações estáticas e a reprodução da falta de assets foram testadas sem executar `mkarchiso`. Ainda é necessária a geração da ISO real no Arch Linux.
