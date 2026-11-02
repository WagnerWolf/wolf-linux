# Wolf Package Manager · Integrações Wolf 0.3.6-integ-preview1

Esta **prévia experimental** parte do Wolf Linux 2.2.0 Fix7 e acrescenta uma aba ao Package Manager para verificar integrações. A ISO/instalação estável **não foi alterada** para instalar automaticamente esta prévia ou o hook. O formatador Wolf existente não foi modificado.

## Teste sem instalação

```sh
python3 tools/package-manager/wolf-integrations-check.py
cd tools/package-manager
python3 main.py
```

Verifique a aba **Integrações Wolf** e o estado `Pendente` da modificação do menu USB. O botão **Verificar integrações** é apenas uma consulta.

## Próximo passo: versão exata da biblioteca

```sh
bash experimental/integracoes-wolf/coletar-libfm-info.sh
```

Esse resultado indica qual `libfm-qt` e PCManFM-Qt estão instalados. O patch C++ e o pacote Pacman **não fazem parte desta prévia**, para evitar apresentar um binário não compilado/testado como funcional. Ao validar o patch em hardware de teste, a distribuição será registrada e controlada pelo Wolf Package Manager com rollback explícito.

## Hook opcional

Consulte `experimental/integracoes-wolf/README.md`. Não há `makepkg`, instalação ou atualização dentro do hook.
