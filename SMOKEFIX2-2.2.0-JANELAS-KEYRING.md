# Wolf Linux 2.2.0 — SmokeFix2 (janelas/Keyring)

Corrigida a regressão no `wolf-test-windows-keyring-2.2.0.py` após preparar a árvore com `preparar_ambiente_wolf_linux.sh`.

- O DevKit contém `branding-assets/` e `assets/`.
- O preparador copia `branding-assets/` para `assets/` no projeto final; ele não preserva um diretório separado chamado `branding-assets/`.
- O teste agora valida `assets/pcmanfm-qt/wolf-open-vscode.desktop` nos dois layouts e compara a cópia fonte, quando disponível.
- O preparador verifica a igualdade das duas fontes antes do build e verifica a cópia gerada depois do estágio.
- Não altera a implementação de abertura do VS Code, gerenciamento de monitores, chaveiro ou a instalação.

Para projeto `~/wolf-linux` já preparado, sem reconstruir: copie `tests/wolf-test-windows-keyring-2.2.0.py` e `preparar_ambiente_wolf_linux.sh` deste DevKit para os caminhos homônimos do projeto. Execute `bash ~/wolf-linux/tests/wolf-smoke-test.sh`.
