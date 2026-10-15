# Wolf Linux DevKit 2.0.0-alpha59

- Corrigido o catálogo **estrito** de etapas do ensaio físico: a etapa `63b-vulkan` da alpha58 agora consta de `wolf_physical_rehearsal.STAGE_LABELS`.
- O relatório do ensaio físico marca a etapa Vulkan como **não aplicável** quando a stack Gaming não está selecionada.
- Teste de regressão garante alinhamento entre as etapas do Bash e o relatório físico, incluindo bloqueio para etapas desconhecidas.
- Nenhuma alteração no executor Bash, nas rotinas de formatação, nas configurações de GRUB ou na interface.
