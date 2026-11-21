# Wolf Linux 2.3.0 Stable — Refinos 1 / BuildFix 1

Correção exclusiva do fluxo de geração da ISO. Sem alteração dos pacotes instalados,
perfil KDE, Live, instalador nem refinamentos homologados.

## Causa

`preparar_ambiente_wolf_linux.sh` verificava o perfil `releng` antes da instalação
via `pacman`. Agora instala primeiro as dependências e só então verifica o perfil.
Se `archiso` estiver registrado como instalado, mas seus arquivos estiverem faltando,
reinstala exclusivamente `archiso` e verifica novamente.

## Fluxo recomendado

```bash
./gerar-iso.sh
```

Ou, no fluxo em duas etapas habitual:

```bash
./preparar_ambiente_wolf_linux.sh
./gerar-iso.sh
```

O padrão é `~/wolf-linux-2.3.0-refinos1-buildfix1` para preservar os projetos
antigos. O gerador aceita `--project /caminho/novo` e `--skip-deps` (somente
para uma preparação nova; exige releng previamente instalado).

Foram removidos três lançadores antigos de geração da raiz. O construtor
`tests/wolf-build-iso.sh` é interno e permanece necessário.

**Segurança:** nunca apaga um projeto anterior desconhecido, não reinstala se
já foi preparado por esta revisão e não executa operações de particionamento
do sistema local. A compilação usa `mkarchiso` e requer Arch Linux com sudo.

**Validação:** testes de sintaxe e de regressão de dependências podem rodar sem
pacman real. A compilação física da ISO ainda requer validação no Arch Linux.
