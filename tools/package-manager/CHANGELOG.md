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
