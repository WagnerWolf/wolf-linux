# Wolf Linux 2.2.0 — Fix4: painel secundário

## Causa identificada no teste físico

O `~/.config/lxqt/panel.conf` continha duas chaves `panels` no nível raiz:

```
panels=panel1,panel2
panels=panel1
```

O Qt/QSettings retornava a última (`panel1`); o painel secundário não era iniciado,
mesmo com as seções e os dois monitores corretos. Agora `wolf_lxqt_monitors.py`
verifica quantidade **e** valor das declarações e não aceita duplicidade.

## Testar no computador instalado

No diretório do DevKit extraído:

```bash
python3 wolf-corrigir-painel-duplo.py --check
python3 wolf-corrigir-painel-duplo.py --apply
```

O programa faz backup, não requer sudo e não altera o XRandR. Ele reinicia o
`lxqt-panel`, portanto pode ocorrer uma breve interrupção na barra. Se o
gerenciador de sessão sobrescrever a alteração, informe a saída e prefira
encerrar a sessão e entrar novamente após aplicar a correção.

## Arquivos da ISO

O helper `tools/lxqt/wolf_lxqt_monitors.py` é instalado pelo gerador de ISO.
Na nova instalação ele remove duplicações da lista durante a aplicação por
monitor e impede falsos-positivos na verificação de sincronização.

## Estado

Smoke test não destrutivo aprovado; reexibição do painel em hardware físico
**pendente** até repetir o teste no usuário afetado.
