# Validações alpha52

- Testes do novo planejador: 23 verificações aprovadas.
- Integração de launchers / segurança do planejador: 5 verificações aprovadas.
- `wolf-test-live-desktop.sh`: aprovado, incluindo regressões anteriores e validação da interface clássica.
- Staging da interface Live: executado duas vezes sem duplicação de pacotes; módulos `preview` e dois launchers conferidos com `cmp`.
- `bash -n` e compilação Python: aprovados.
- Smoke test completo: primeira execução encontrou listas históricas de versão, atualizadas para reconhecer alpha52; segunda execução esgotou tempo de execução deste ambiente antes da conclusão. **Não está homologado como smoke completo.**
- Testes Qt (PySide6): 4 casos preparados mas ignorados por ausência de PySide6 neste ambiente. O teste visual real das resoluções deve ocorrer na VM.
- Geração real da ISO/mkarchiso e boot em VM: não realizados neste ambiente; precisam ser executados no Arch Linux do usuário.

Observação: os três modos da interface nova produzem **somente prévias não executáveis**. O executor clássico alpha51 está preservado em paralelo para a fase de homologação.
