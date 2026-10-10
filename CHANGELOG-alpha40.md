# Wolf Linux 2.0.0-alpha40 — Correção do lançador de revisão multidisco

## Correção

- O instalador Bash já reconhecia `--review-multidisk-plan` e `--simulate-multidisk-plan` na alpha39. No entanto, o lançador `/usr/local/bin/wolf-install`, gerado no estágio do Archiso, não os reconhecia como comandos de revisão. Ele introduzia `--install`, causando erro de opção desconhecida.
- Ambos os comandos agora são explicitamente encaminhados sem adicionar opções de instalação. O `--reset-state` também não provoca seleção automática de modo de instalação.
- O lançador recusa opções de comando desconhecidas antes de selecionar automaticamente o modo real/VM. A seleção automática legada permanece disponível quando nenhum modo foi escolhido e a invocação é válida.
- Ajuda do Bash lista os dois comandos multidisco; mensagens da GUI foram ajustadas para a versão 2.0.

## Segurança

- `wolf.install.multidisk.preview.v1` permanece um documento exclusivamente para revisão e simulação com `execution=disabled`.
- A validação independente refaz `lsblk`, UUID, `fstab` e dependências LVM; instalação física continua bloqueada.
- Nenhuma rotina de particionamento, formatação ou GRUB foi modificada nesta revisão.

## Testes

- `tests/wolf-test-alpha40.py`: verifica o lançador gerado no estágio com stub (capturando argumentos), as duas opções, o encaminhamento sem `--install`, rejeição de opção desconhecida e modos legados.
- Smoke test e staging Archiso simulados; ainda é necessária homologação real em Live do usuário.
