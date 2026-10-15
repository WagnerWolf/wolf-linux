# Wolf Linux DevKit 2.0.0-alpha44 — correção do teste UID/GID

Base: alpha43, sem mudanças nas rotinas destrutivas de instalação, particionamento, montagem ou recuperação.

## Correção

O teste `tests/wolf-test-alpha43.py` assumia que um diretório temporário
criado pelo executor de testes teria UID 0 (`root-owned`). Isso é falso na
preparação executada como usuário comum. Além disso, o mock usado no teste
para `Path.lstat()` não é herdado pelo `subprocess.run()`.

O teste agora verifica a função sob mock separadamente e compara a saída
CLI do subprocesso com a identidade real obtida fora do mock. A regressão
foi reproduzida como usuário regular e verificada novamente após correção.

## Verificação local

```
python3 tests/wolf-test-alpha43.py
bash tests/wolf-test-live-desktop.sh
bash tests/wolf-smoke-test.sh
```

Não é necessário usar `sudo` para os testes. Instalação em hardware físico
continua bloqueada no executor gráfico multidisco experimental.

Também foi estabilizada uma asserção legada de `wolf-test-alpha35.py`, que procurava a substring `rw` no comando inteiro (inclusive nome aleatório da pasta temporária), em vez de verificar apenas as opções de montagem.
