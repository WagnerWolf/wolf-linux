## Atualização alpha33

Contrato operacional atual: `wolf.install.preview.v4` (somente planejamento). `storage.erase_sizes={"root_gib":N,"home_gib":N}` valida tamanhos em GiB e é aceito apenas para `mode=erase`. Exportação experimental para Bash: 19 campos, incluindo modo de `/home` no campo 13 (`separate` ou vazio), tamanhos de raiz e /home nos campos 18 e 19 (índices 17 e 18). `execution=disabled` permanece obrigatório; execução por comando separado e confirmação. Valores são revalidados pelo Bash antes de formatar. Em UEFI cria ESP 1 GiB; em BIOS/MBR nenhuma EFI. Discos físicos e LVM continuam bloqueados.

# Alpha31 — contrato de planejamento v3 e reutilização UEFI VM

- `wolf.install.preview.v3`, `execution=disabled`. O JSON não concede permissão para executar instalação.
- `storage.cleanup_home` booleano, por padrão `false`; permitido somente no modo `reuse`, com partição `/home` dedicada **preservada**.
- Execução `--execute-gui-plan-vm` revalida inventário de partições e aplica somente em VM QEMU/KVM com disco VirtIO, UEFI, GPT, raiz >=20 GiB, EFI FAT32 >=512MiB e home ext4.
- Em `reuse`, o backend **formata apenas a raiz ext4**. EFI e `/home` são montadas, sem `mkfs`; GRUB atualiza o caminho `EFI/WolfLinux`, sem instalar fallback removível neste modo.
- Limpeza opt-in: antes de qualquer `mkfs`, monta /home em leitura somente, lista as entradas ocultas imediatamente dentro de cada usuário existente, exige `LIMPAR`, guarda a lista, depois compara a lista após a montagem real e só remove os caminhos aprovados. Arquivos visíveis são preservados. **Entradas ocultas podem incluir chaves SSH e cofres de senhas**.
- No modo `manual`, formatações de EFI e /home continuam independentes, mas a limpeza opt-in da home preservada é exclusivamente do modo reuse.
- No modo `erase`, disco inteiro será apagado mediante confirmação.
- Reutilização com `/home` dentro de `/` NÃO preserva arquivos pessoais, pois a raiz é formatada; o piloto reuse **exige `/home` dedicada**.
- A execução em hardware real continua BLOQUEADA. Faça backup da imagem qcow2 original antes do teste.

---

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
