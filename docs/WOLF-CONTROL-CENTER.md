# Wolf Control Center 0.1.1 — Plano de validação

Esta central usa PySide6 e é distribuída com o Wolf Linux. `main.py` é a interface;
`backend.py` contém detecção e ações simples sem dependência Qt.

## Testar imediatamente na máquina física com alpha15

1. Instale a dependência gráfica do Arch: `sudo pacman -S --needed pyside6`.
2. Extraia o ZIP da alpha17 e entre em `tools/control-center/`.
3. Execute `./install-local.sh` **como usuário normal**. Não é necessária reinstalação.
4. Abra `Wolf Control Center` no menu Plasma ou execute `~/.local/bin/wolf-control-center`.
5. Teste: visão geral; status MultiMonitor; reconciliar com confirmação; assistente Gamepad (Konsole); GRUB Manager (diagnóstico **sem editar**); ativar Octopi; checar autosuggestions.
6. Desinstale apenas a central com `./uninstall-local.sh`, se desejar. O comando preserva o sistema, helpers e configurações pessoais.

O pacote `pyside6` é instalado separadamente para a alpha15; a alpha17 já inclui
a dependência no manifesto do KDE.

## Segurança e escopo

- Somente comandos específicos são permitidos: nada de shell arbitrário, e nenhum acesso root silencioso.
- GRUB/Gamepad continuam interativos no Konsole com as confirmações originais.
- MultiMonitor requer confirmação, preserva backup do próprio helper e não cria watcher.
- No primeiro uso, a central não altera arquivos do usuário automaticamente.
- Octopi: configuração de autostart por usuário e backup de arquivo anterior, sem atualização automática.
- A central não precisa iniciar junto com o Plasma e não realiza polling periódico.

## Próxima fase — interface gráfica do instalador

Reutilizar o **motor Bash do instalador** já validado, antes de introduzir telas de
instalação de disco novas. A interface Qt deverá gerar e exibir um plano de instalação
estruturado para revisão, permitindo escolher sistema UEFI/BIOS, partições,
stacks e preservação de `/home`, e solicitar confirmação explícita antes de
formatar qualquer disco. Essa separação ainda precisa ser implementada: não
executar o instalador CLI existente num QProcess com respostas simuladas.

## Novidades 0.1.1

- Páginas com rolagem e botões empilhados evitam cortes em janelas menores.
- Octopi exibe estado do autostart e processo quando consultado; permite ativar/desativar
  o autostart por usuário (efeito no próximo login), sem matar processos existentes.
- Zsh testa uma **nova sessão** interativa, informa se o plugin foi carregado e qual cor
  está configurada. Não inspeciona o estado da aba Konsole já aberta.
- Não são usados timers, watchers ou polling para acompanhar alterações em tempo real.
