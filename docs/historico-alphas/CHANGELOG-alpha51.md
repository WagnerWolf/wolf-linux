# Wolf Linux DevKit 2.0.0-alpha51

## Correção da regressão no smoke test da alpha50

- **Causa:** `wolf-test-alpha50.py` gravava o manifesto temporário com o proprietário do processo de testes (normalmente o usuário `wolf`), porém `wolf_home_cleanup._read_manifest()` exige **root:root + modo 0600**. O teste falhava em usuários normais, mas passava como root.
- **Correção:** o teste agora simula *apenas* a propriedade root do manifesto durante o teste isolado. A rotina **real** mantém intacta a validação de propriedade root e permissões restritas.
- **Regressões novas:** é verificada explicitamente a recusa de manifesto pertencente a usuário comum (quando não root), a recusa de modo 0644 mesmo quando o dono simulado é root, e a aceitação simulada com modo 0600.
- Testes legados alpha43, alpha45 e alpha49 atualizados para reconhecer alpha51 como versão sucessora.
- Sem mudanças no executor físico, no particionamento, na GUI, no backup ou na política de remoção. **A rotina de limpeza física com dados reais segue não homologada.**

Para validar como usuário comum:

```bash
bash tests/wolf-smoke-test.sh
```
