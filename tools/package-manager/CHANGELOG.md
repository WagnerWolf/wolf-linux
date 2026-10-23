# Wolf Package Manager 0.3.4 (23/10/2026)

- Ação «Atualizar sistema (N)» no menu de contexto da bandeja, habilitada exclusivamente após consulta completa com atualizações.
- Usa a confirmação gráfica e o fluxo existente do gerenciador; não executa transações pelo simples clique sem aprovação.
- Desabilita a ação durante verificações/operações e após resultados parciais ou transações, evitando contagem desatualizada.
- Abre a janela antes de exibir confirmação no KDE Wayland.
- Testes isolados da política da bandeja, sem acesso ao pacman.

# Wolf Package Manager 0.3.3 (16/10/2026)

- Corrigida a visualização de progresso do pacman (carriage return e backspace) em terminal integrado, sem alterar o PTY ou transações.
- Eliminação incremental de ANSI e decodificação UTF-8 sem corromper caracteres entre leituras parciais.
- Testes regressivos do renderizador e desativação do wrap automático de linhas longas.

# Wolf Package Manager 0.3.2

- Verificação de atualizações mais confiável e sem alteração destrutiva do banco do pacman.
- Detecta divergência entre `checkupdates` e `pacman -Qu` quando a primeira consulta retorna zero.
- Descarta resultados de verificações que se sobreponham a transação externa registrada no pacman.log ou a uma trava presente.
- Distingue consulta incompleta de sistema atualizado; retenta após 60 s quando uma transação foi detectada.
- Busca e instalação continuam como na versão 0.3.1.
