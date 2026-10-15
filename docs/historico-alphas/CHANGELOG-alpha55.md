# Wolf Linux DevKit 2.0.0-alpha55

- Entrada do instalador: etapa de seleção/teste de teclado antes da escolha do particionamento.
- Sem modo de instalação pré-selecionado. Exigir clique do usuário.
- Terminal PTY interativo na própria GUI nova (mesmo motor do instalador clássico); saída, entrada, status e resultado real do Bash.
- Corrigida a allowlist da ISO: aceita `--execute-gui-plan-vm-click` e recusa flags desconhecidas.
- Motor PTY autoriza somente esta nova flag adicional, sem shell genérico.
- GUI mantém dupla confirmação por clique; Bash VM dispensa a digitação extra `LIMPAR` apenas nesse fluxo, revalidando a lista de dotfiles.
- Pré-validação antes da revisão e novamente antes da execução; revalidação Bash continua obrigatória.
- Preservado o executor físico clássico e limites da execução VM da alpha53.

## Testes

- `python3 tests/wolf-test-alpha55.py`: wrapper isolado, rejeição de flags não permitidas e PTY com sudo simulado, nenhum disco alterado.
- Regressões relevantes do planejador, PTY e preflight.
- **Pendente:** teste gráfico Qt e instalação destrutiva completa na VM (ainda não realizada aqui).
