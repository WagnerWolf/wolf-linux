# Wolf Linux DevKit 2.0.0-alpha52 — Interface Live integrada

- A interface de planejamento baseada no protótipo P02 passa a abrir automaticamente na sessão Live.
- Telas de apagar disco, particionamento manual e reutilização são separadas, com seletores dinâmicos, slider e cálculo de capacidade.
- Ajuste de janela à área útil do monitor, menores margens, rolagem da barra lateral, labels responsivos e tabela de revisão com dimensionamento adaptável.
- Duas confirmações por clique e exportação JSON **não executável**; nenhum modo do planejador novo executa particionamento ou instalação.
- Instalador clássico alpha51, já homologado, permanece disponível por botão separado e comando `wolf-live-installer-classic`; seu contrato com Bash é preservado.
- O GParted é uma ferramenta real e pode modificar discos, exigindo autorização na própria interface.
- A ISO precisa ser construída no Arch Linux com archiso e testada em máquina virtual; o ZIP é o DevKit, não a imagem ISO.

**Escopo de segurança:** na alpha52, os três modos da nova UI são somente prévia. O instalador clássico preserva sua capacidade real. Não usar os JSONs de prévia como autorização de execução; a ligação do novo planejador com o backend será validada separadamente.
