# Wolf Installer — interface Live 2.0

O instalador principal usa Python/PySide6 na sessão Live (Openbox/Xorg). O sistema instalado usa KDE Plasma/Wayland.

Fluxo: layout do teclado → escolha explícita do tipo de instalação → configuração e perfil → revisão das partições/operações → duas confirmações por clique → terminal PTY integrado → conclusão.

Modalidades: apagar disco inteiro, atribuição manual de partições e reutilização das partições existentes. O GParted pode ser aberto na modalidade manual e pode alterar discos independentemente do instalador.

As permissões elevadas são usadas somente em ações de diagnóstico e execução autorizadas pelo backend; a GUI em si funciona como usuário da Live. A confirmação da interface **não substitui** a revalidação independente do Bash.

A aplicação principal é `live-gui/preview/app.py`. O nome técnico `vm_bridge.py` e algumas flags legadas permanecem por compatibilidade com os contratos já homologados: não representam uma exigência atual de VM para os modos comuns.

Arquivos históricos sobre protótipos anteriores estão em `docs/historico-alphas/`.
