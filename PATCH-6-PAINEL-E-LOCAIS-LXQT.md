# Wolf Linux 2.2.0-rc1 — Patch 6 (painel principal e locais)

Base: Patch 5 (kernel Arch + LTS). Mantém as correções dos Patches 1 a 5.

## Causas

- `install_wolf_lxqt_profile()` executava `configurar.py --telas 2` mesmo quando a VM tinha apenas um monitor ativo.
- `panel1` tinha StatusNotifier, tray e volume; `panel2` não. Assim, em algumas situações a tela da VM recebia o painel reduzido.
- O `panel.conf` antigo era mesclado, permitindo sobreviverem entradas do quicklaunch do Dolphin.
- Os favoritos XDG não eram populados explicitamente no perfil PCManFM-Qt.

## Correções

1. Perfil inicial do `panel.conf`: sempre `panels=panel1` com menu, quicklaunch do Chrome/PCManFM-Qt/Konsole (quando instalados), tarefas, `statusnotifier`, `tray`, volume, relógio e mostrar desktop.
2. `panel2` continua preparado para quando dois monitores forem detectados e terá tarefas locais e painel mais simples.
3. Novo `/usr/local/bin/wolf-lxqt-monitors` lê `xrandr --listmonitors` no login LXQt, ativa `panel2` apenas se houver segunda tela e recarrega somente o LXQt Panel se houver alterações. Não há watcher persistente. Após conectar/desconectar monitores durante a sessão, execute `wolf-lxqt-monitors` para aplicar imediatamente.
4. O `panel.conf` antigo é copiado para backup pelo configurador e substituído pelo painel Wolf padronizado; remove referências antigas do quicklaunch do Dolphin.
5. Favoritos do PCManFM-Qt no arquivo `~/.config/gtk-3.0/bookmarks`, seguindo caminhos XDG do usuário: Documentos, Downloads, Imagens, Músicas e Vídeos. Os caminhos já configurados são respeitados e os favoritos adicionais preservados, evitando duplicação.

**Limitação do PCManFM-Qt**: as pastas personalizadas aparecem na seção de Favoritos/Bookmarks da barra lateral. Itens internos como Computador e Aplicações não podem ser posicionados/removidos por esse arquivo. O nome da seção e a posição exata dos itens nativos variam conforme a versão do PCManFM-Qt.

## Testes não destrutivos

```
./tests/wolf-smoke-test.sh
python3 tests/wolf-test-panel-places.py
```

Teste ainda necessário na VM e no hardware real: primeiro login com um monitor, login com dois, ícones reais de nm-applet e Udiskie, abertura dos favoritos e recolocação de monitor. A aprovação do smoke test não equivale à validação visual do desktop.
