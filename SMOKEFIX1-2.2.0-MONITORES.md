# Wolf Linux 2.2.0 — SmokeFix1 (integração de monitores)

Esta revisão é uma correção pontual **do DevKit**, sem alterar a lógica de instalação,
o editor gráfico, o kernel, as configurações do LXQt nem o perfil de pacotes.

## Problema

O preparador copiava `tests/wolf-test-release-2.2.0.py` para `~/wolf-linux`,
mas deixava `gerar-iso-2.2.0.sh` somente na pasta original do DevKit.
O smoke test, quando executado na árvore preparada, falhava no `assert`.

O teste negativo do editor Wolf também imprimia uma mensagem `[ERRO]` quando
simulava uma sessão Wayland, mesmo tendo sido executado com sucesso.

## Correções

- `preparar_ambiente_wolf_linux.sh` agora instala a cópia do gerador na árvore
  preparada com permissão de execução, e verifica a existência da fonte.
- `tests/wolf-test-release-2.2.0.py` exige que o preparador mantenha essa cópia
  e fornece diagnóstico explícito caso o arquivo esteja faltando.
- `tests/wolf-test-monitors-entry-2.2.0.py` captura a mensagem do cenário
  negativo Wayland e confirma seu conteúdo, sem poluir o smoke test.

## Validar

Na pasta extraída do DevKit:

```bash
./tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-smokefix1" ./gerar-iso-2.2.0.sh
```

**Atenção:** o gerador faz preparação limpa do destino especificado e se recusa
se o diretório já existir. Não use `--force` em projetos que deseja preservar.

Para testar apenas o projeto preparado existente, sem recriá-lo nem apagá-lo:

```bash
cp -a /caminho/do/devkit/gerar-iso-2.2.0.sh "$HOME/wolf-linux/gerar-iso-2.2.0.sh"
bash "$HOME/wolf-linux/tests/wolf-smoke-test.sh"
```

O comando acima só transfere o gerador; se o projeto anterior contiver a versão
antiga do teste de monitor, a mensagem simulada Wayland ainda pode aparecer.
