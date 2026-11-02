# Integração dos Monitores Wolf — atualização da release 2.2.0

**Origem:** release 2.2.0 LXQt estável, homologada em VM pelo mantenedor.

## Alterações específicas

- `wolf-control-center --monitors`: abre o editor visual sem a janela principal.
- `wolf-monitors`: comando equivalente, pensado para atalhos/diagnóstico.
- `/usr/share/applications/wolf-monitors.desktop`: Monitores (Wolf Linux) no menu LXQt.
- `~/.local/share/applications/lxqt-config-monitor.desktop`: `NoDisplay=true` para ocultar apenas a entrada redundante do LXQt; binário e demais ferramentas `lxqt-config` continuam presentes.
- A configuração LXQt salva backup de arquivos do usuário e permite restauração pelo mecanismo já existente do DevKit.
- Launcher Python busca primeiro os dois módulos completos em `/usr/local/lib/wolf-linux/control-center` e, na ausência deles, a instalação local em `XDG_DATA_HOME/wolf-linux/control-center`.
- `monitor_layout.py` passa a registrar no autostart o caminho real do módulo, em vez de supor uma instalação local.
- Instaladores locais do Control Center corrigidos para copiar todos os módulos, não só `main.py` e `backend.py`.
- Links redundantes para o configurador nativo retirados da interface Wolf.

## Execução após instalar ISO

```bash
wolf-control-center --monitors
# ou
wolf-monitors
```

### Verificar integração

```bash
command -v wolf-monitors
ls -l /usr/local/lib/wolf-linux/control-center/{monitor_editor.py,monitor_layout.py,wolf_monitors.py}
ls -l /usr/share/applications/wolf-monitors.desktop
cat ~/.local/share/applications/lxqt-config-monitor.desktop
```

## Build em Arch Linux

```bash
./tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-monitores" ./gerar-iso-2.2.0.sh
```

O novo destino de build evita conflito com uma pasta anterior `$HOME/wolf-linux-2.2.0`. O script não apaga builds anteriores.

## Validação

Smoke test estático/regressões não destrutivas. Instalação real e abertura gráfica deste ajuste **ainda não homologadas**. A base 2.2.0 anterior permanece homologada em VM.
