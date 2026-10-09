# Alpha24 — Contrato de preview v2 e simulação segura

**NÃO executável.** Os comandos `wolf-install --review-gui-plan` e `wolf-install --simulate-gui-plan` encerram antes da rotina principal. Nunca são equivalentes a `--install` ou `--vm-install`.

- `schema`: `wolf.install.preview.v2` (o JSON da alpha23 não é aceito pelo validador novo).
- `execution`: sempre `disabled`; a revisão rejeita qualquer outra opção.
- `storage.home_layout`: `in-root` ou `separate`. No modo `in-root`, `storage.partitions.home` deve ser nulo e `storage.format.home` deve ser falso.
- `storage.mode`: `erase`, `reuse`, `manual`.
- `storage.partitions`: associação de `/`, ESP e `/home` às partições EXISTENTES do disco selecionado; múltiplos discos e LVM não são mapeados automaticamente nesta revisão.
- `storage.format`: apenas intenções. A simulação bloqueia combinações incompatíveis com os métodos do Bash atual.
- `disk`: caminho, tamanho, MAJ:MIN, modelo, transporte, removibilidade revalidados via `lsblk`.
- `identity`, `software`, `keyboard`, `boot_mode` seguem a revisão anterior.
- `warnings`: mensagens canônicas recalculadas, impedindo aceitar documento modificado após geração.

## Correspondência com o Bash

- `erase`: apaga o disco escolhido apenas na FUTURA instalação real; simulação jamais executa.
- `reuse`: equivale ao modo `reuse-manual` do Bash: raiz obrigatória formatada como ext4, ESP UEFI preservada, /home opcional preservada ou dentro da raiz; formatação de /home e EFI não estão implementadas nesse modo.
- `manual`: requer montagem de `/mnt` feita previamente pelo usuário. A GUI ainda NÃO transforma a escolha de partições em uma sequência de montagens. Em GParted, mudanças podem ocorrer apenas mediante operação direta/confirmada do usuário.

A simulação é *descritiva*, não um replay de shell commands, não contém senhas e não habilita a instalação. Qualquer modo executável futuro exigirá novo schema e testes próprios contra discos de VM descartáveis.
