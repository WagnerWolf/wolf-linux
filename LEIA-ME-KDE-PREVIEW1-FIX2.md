# Wolf Linux KDE 2.3.0 — Preview 1 Fix2 (instalador)

## Correção de falha crítica na apresentação dos limites do disco

O instalador gráfico exibia o valor anterior do controle de raiz (60 GiB) mesmo
quando a unidade escolhida tinha somente 20 GiB. O `erase_budget()` já
recusava discos pequenos, mas `update_erase_budget()` ocultava o motivo da falha
e não zerava/desabilitava os sliders. A revisão e a execução eram defendidas por
validações posteriores, mas a interface induzia o usuário a uma seleção impossível.

### Mudanças

- Instalação automática exige **32 GiB reais** no disco, coerente com o contrato
  do executor (`VM_MIN_BYTES`), em vez dos 30 GiB usados antes no protótipo.
- Em disco insuficiente, a UI exibe o tamanho medido e a mensagem de bloqueio;
  zera/desabilita controles de / e /home. Não exibe mais 60 GiB antigos.
- Com /home separada, exige 35 GiB *úteis* antes de disponibilizar os controles
  (25 GiB de raiz + 10 GiB de /home); inclui reservas de boot/alinhamento.
- Aviso de espaço agora é atualizado **após** recalcular os controles.
- `Minimal — KDE Plasma/Wayland essencial` e avisos próprios para KDE; removidas
  estimativas numéricas de LXQt não homologadas para o sistema KDE.
- Testes novos inteiramente artificiais (sem tocar discos), para BIOS e UEFI com
  20/30/31/32/35/40/120 GiB, incluindo rejeição pelo executor canônico.

### Aplicar no projeto de build já criado (host Arch)

Extrair os 3 arquivos `live-gui/preview/app.py`, `live-gui/preview/planner.py`
e `tests/wolf-test-kde-2.3.0-rc1.py`, além do teste
`tests/wolf-test-kde-erase-budget.py`, no projeto `~/wolf-linux-2.3.0-rc1`.

A ISO já gerada é imutável: executar **novamente**
`WOLF_OUT_DIR="$HOME/wolf-linux-2.3.0-rc1/out-fix2" bash tests/wolf-build-iso.sh`
no projeto após substituir os arquivos e passar nos testes. Usar diretório de
saída separado evita confundir a ISO antiga e a nova. A etapa de staging
recopia a GUI atualizada para `iso-profile/airootfs`.

**Atenção:** NÃO instalar a Preview 1/Fix1 em nenhum disco, principalmente
porque a GUI antiga exibe tamanhos impossíveis. A Preview 1 Fix2 ainda requer
validação visual na VM e instalação completa para ser homologada.
