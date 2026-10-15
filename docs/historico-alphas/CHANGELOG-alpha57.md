# Wolf Linux DevKit 2.0.0-alpha57 — correção do smoke test Qt

- Corrige `tests/wolf_test_alpha52_ui.py` para respeitar o perfil obrigatório da alpha56. Antes, o teste esperava que **Revisar** fosse habilitado mesmo sem selecionar Minimal, Test ou Full.
- Adiciona cobertura Qt para o botão **Revisar**: desabilitado sem perfil, habilitado após escolher cada perfil válido e desabilitado ao voltar à opção vazia.
- Inclui regressão independente do PySide6 para detectar o descompasso entre teste e interface (`wolf-test-alpha57.py`).
- Atualiza validações de versão antigas para aceitar a nova alpha57 e inclui o teste novo no staging.
- Nenhuma alteração no executor de instalação, operações de disco, configuração da interface, gerenciamento de partições, PTY ou limpeza do `/home`.

## Escopo
Correção exclusiva da suíte de testes; preserva as funcionalidades da alpha56. Não constitui uma nova homologação física.
