# Wolf Linux DevKit 2.1.1-rc2 — Correção visual do terminal

Base: **2.1.1-rc1**, com suporte a instalações multidisco e `/home` LVM.

## Mudança única de comportamento

- Corrigida a apresentação das barras de progresso e da saída PTY no instalador gráfico. O `pacman` usa retornos de carro (`\r`) para redesenhar o progresso; a interface substitui apenas a linha atual, sem concatenar as atualizações.
- O conteúdo do log, o executor Bash e o fluxo de instalação não são alterados.
- A correção não resolve nem modifica o `baloo_file_extractor` do sistema instalado; investigar separadamente o plugin Qt a partir dos logs da sessão de usuário.

## Validação

- Testes unitários da normalização de saída, sintaxe Python e staging simulado podem ser executados sem privilégios administrativos.
- A aparência final Qt e a ISO deverão ser conferidas no equipamento do mantenedor.
