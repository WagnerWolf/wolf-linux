## 0.3.7 (2/11/2026)
- Auditoria da libfm-qt Wolf antes de qualquer transação (inclusive instalação).
- Proteção em pacman.conf via IgnorePkg, instalada após a biblioteca Wolf, com backup e reversão.
- Mensagem preventiva para novas versões, com opção de atualizar os demais pacotes.
- Assistente de planejamento (não compila, não autoriza novas bibliotecas automaticamente).
- Hook pós-atualização continua somente registrando alterações; atualizações de ABI exigem revisão.

## 0.3.6 — Integrações Wolf (auditável, não destrutivo)

- Aba Integrações Wolf; detecção conservadora de libfm-qt Wolf e utilitário USB --device.
- Hook ALPM apenas avisa sobre revisões; atualização do pacote permanece sob controle do usuário.
- Controle de kernels/NVIDIA preservado de 0.3.5.

# Wolf Package Manager 0.3.5 (Preview 2 — identidade das notificações, 27/10/2026)

- Corrige o cabeçalho `main.py` nas notificações KDE/Plasma do monitor de atualizações.
- Define applicationName e applicationDisplayName do Qt como `Wolf Package Manager` e desktopFileName como `wolf-package-manager`.
- Define ícone padrão do QApplication e alinha o __version__ do módulo à versão do aplicativo.
- Sem mudanças na instalação/atualização de pacotes ou nas verificações pós-atualização.

# Wolf Package Manager 0.3.5 (prévia para validação)

- Adicionada verificação pós-atualização somente leitura após `pacman -Syu`, antes de iniciar AUR, e novamente após etapa AUR.
- Verifica vmlinuz, initramfs/preset de mkinitcpio, módulos NVIDIA DKMS para cada kernel e `pacman -Dk`.
- Alerta e interrompe o plano de atualização ao detectar inconsistência crítica, sem executar reparos automaticamente.
- Botão manual «Verificar boot/DKMS»; execução em thread para não bloquear o KDE.
- Preservados o atalho na bandeja, os controles de confirmação, os logs e o fluxo de atualização da 0.3.4.
- Testes simulando a falha real: kernel instalado, mas ausente em /boot, initramfs faltando e NVIDIA DKMS ausente.

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
