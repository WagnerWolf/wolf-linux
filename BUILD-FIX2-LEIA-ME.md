# Wolf Linux 2.3.0 Stable — Refinos 1 BuildFix 2

## Alteração

A construção BuildFix 1 pode parar durante o staging da Live por falta de
`assets/wallpapers/wolf-linux-wallpaper.png` dentro da cópia de projeto,
embora o arquivo esteja presente no ZIP distribuído. O motivo da ausência
na cópia local não foi determinado. O BuildFix 2:

- Recupera automaticamente o wallpaper original de `branding-assets/wallpapers/`, sem gerar uma imagem substituta.
- Valida que as duas cópias são idênticas.
- Permite retomar o projeto *já criado e interrompido*, por `--resume`, após validar versão, estrutura, perfil releng e instalador.
- Não remove o projeto, work, out ou conteúdo do disco. Não altera o sistema instalado.
- Mantém só os dois scripts de entrada na raiz: `preparar_ambiente_wolf_linux.sh` e `gerar-iso.sh`.

## Recuperação do projeto interrompido

Extraia este DevKit em uma nova pasta, acesse-a e execute:

```bash
bash preparar_ambiente_wolf_linux.sh --resume --skip-deps \
  --project "$HOME/wolf-linux-2.3.0-refinos1-buildfix1"
bash gerar-iso.sh
```

A retomada é bloqueada caso a estrutura ou o instalador não coincidam com
este DevKit. Não use `rm -rf` para recuperar o projeto.

O gerador reutiliza o projeto pronto e produz a ISO em `out/`.

## Validação

```bash
python3 tests/wolf-test-build-assets-2.3.0.py .
python3 tests/wolf-test-kde-2.3.0.py .
```

Não houve geração real de ISO neste ambiente. Requer teste na máquina Arch.
