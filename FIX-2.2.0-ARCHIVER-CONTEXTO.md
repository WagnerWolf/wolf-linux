# Wolf Linux 2.2.0 — Arquivos compactados / PCManFM-Qt

## Sintoma

Menu do botão direito exibe **Extrair aqui** e **Extrair para**, mas nada acontece.

## Primeira correção (preferência gráfica)

PCManFM-Qt → Editar → Preferências → Avançado → Integração com compactador: `lxqt-archiver`.

No sistema instalado, conferir e reparar sem reinstalação:

```bash
python3 wolf-corrigir-archiver-2.2.0.py --check
python3 wolf-corrigir-archiver-2.2.0.py --apply
```

A rotina faz backup em `~/wolf-backups/pcmanfm-qt-archiver/`, preserva as demais preferências e não altera a biblioteca Wolf. Encerre a sessão LXQt e entre novamente após aplicar, pois o PCManFM-Qt gerencia também a área de trabalho e pode manter configurações em memória.

## Alteração no DevKit

O configurador `tools/lxqt/configurar.py` agora grava explicitamente `Archiver=lxqt-archiver` em `[System]` de `~/.config/pcmanfm-qt/lxqt/settings.conf`, preservando opções existentes. A versão 2.2.0 permanece inalterada. A aplicação gráfica precisa ser homologada na máquina real antes de promover a revisão como release final.

Se o ajuste gráfico não resolver, executar:

```bash
pacman -Q pcmanfm-qt libfm-qt lxqt-archiver
command -v lxqt-archiver
sed -n '/^\[System\]/,/^\[/p' ~/.config/pcmanfm-qt/lxqt/settings.conf
```

Arquivos específicos `.7z`, `.rar`, etc. podem exigir backends adicionais; um teste `.zip` simples diferencia a configuração da disponibilidade de codecs.
