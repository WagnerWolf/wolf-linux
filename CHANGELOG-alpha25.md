# Wolf Linux DevKit 2.0.0-alpha25 — correções de revisão GUI

- Preserva integralmente a alpha24; versão corretiva sem habilitar instalações.
- GUI 0.5.1: seleção `/home` dentro de `/` remove a escolha de partição e flag antiga de `/home`.
- Desativa seleção implícita de formatação da raiz; intenção de formatar raiz/EFI/home requer confirmação explícita de perda de dados (default Não).
- Banner de alerta persistente enquanto existir intenção de formatação; reset de consentimento ao trocar partição/destino.
- Revisão: texto e legenda com quebra automática de linha; pilha de stacks apresentada uma por linha.
- Avisos sobre riscos de apagar partição e limitação do Bash (reutilização exige ext4) apresentados no contrato de plano.
- `wolf.install.preview.v2` segue apenas simulação, `execution=disabled`. Sem chamadas a formatação, montagem ou instalação pela GUI.
