# Wolf Linux 2.1.1 — SmokeFix 2 (Live GUI)

A ISO da SmokeFix 1 incluía `wolf-live-installer`, mas a execução falhava na importação
`QTextCursor` de `PySide6.QtWidgets`: a classe pertence a `PySide6.QtGui`.
O código foi corrigido sem alterar o executor, particionamento, LVM ou boot.

## Correções
- Import de `QTextCursor` no módulo Qt correto.
- `--self-test` da GUI: instancia uma janela usando inventário fictício e nunca formata discos.
- Após mkarchiso, `wolf-build-iso.sh` exige que a GUI rode dentro do airootfs final
  por `arch-chroot` com `QT_QPA_PLATFORM=offscreen`, impedindo concluir build com GUI quebrada.
- Autostart registra stderr em `~/.local/state/wolf-linux/live-installer.log`.
- Testes de regressão que verificam imports e ligação ao self-test.

## Correção pontual (projeto já preparado)
Aplicar o patch na raiz do projeto e executar:

```bash
python3 tests/wolf-test-live-gui-startup.py
bash tests/wolf-smoke-test.sh
bash tests/wolf-build-iso.sh
```

O teste funcional Qt completo depende do Archiso construído no computador com Arch.
O nome/versão do sistema instalado continua **2.1.1**.
