# Wolf Linux 2.2.0 — Archiver SmokeFix1

Correção de empacotamento, sem alterações nas bibliotecas, kernels ou instalação do sistema.

**Causa:** `tests/wolf-test-archiver-integration-2.2.py` importava o módulo `wolf-corrigir-archiver-2.2.0.py` da raiz da árvore preparada, mas o `preparar_ambiente_wolf_linux.sh` copiava os testes e não copiava esse arquivo. O DevKit original passava; o smoke no projeto preparado falhava com `FileNotFoundError`.

**Correção:** o preparador valida a presença do reparador antes de limpar um destino, copia o arquivo com permissão 0755 para a raiz preparada, confere os bytes copiados, e o teste do Archiver verifica o contrato de cópia.

## Reparar projeto preparado já existente sem refazer a ISO

Entre na raiz do DevKit SmokeFix1 e execute:

```bash
DEVKIT="$PWD"
PROJECT="$HOME/wolf-linux"
install -m 755 "$DEVKIT/wolf-corrigir-archiver-2.2.0.py" "$PROJECT/wolf-corrigir-archiver-2.2.0.py"
install -m 644 "$DEVKIT/tests/wolf-test-archiver-integration-2.2.py" "$PROJECT/tests/wolf-test-archiver-integration-2.2.py"
install -m 755 "$DEVKIT/preparar_ambiente_wolf_linux.sh" "$PROJECT/preparar_ambiente_wolf_linux.sh"
bash "$PROJECT/tests/wolf-smoke-test.sh"
```

Os comandos não alteram o LXQt instalado, não removem pacotes e não recompilam a ISO. Use o DevKit completo da correção para o próximo preparo limpo.
