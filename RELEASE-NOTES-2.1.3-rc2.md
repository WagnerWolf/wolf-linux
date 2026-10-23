# Wolf Linux DevKit 2.1.3-rc2 — atalhos Wolf Package Manager

**Data:** 23 de outubro de 2026. **Estado:** candidata a versão estável; requer validar a interação do menu no KDE Plasma/Wayland.

**Base:** 2.1.3-rc1 validada pelo usuário, mantendo CachyOS principal, LTS de reserva, NVIDIA DKMS e o instalador BIOS/UEFI/multidisco.

## Mudanças desta RC

- Wolf Package Manager atualizado de 0.3.3 para **0.3.4**.
- Menu de contexto no tray: **Atualizar sistema (N)** habilitado quando a última verificação completa detectar atualizações.
- Cliques mostram a janela de atualização e pedem confirmação antes de executar o mesmo plano `pacman -Syu` e `yay -Sua --aur`.
- Durante verificação, operação em andamento, resultado parcial ou erro, ação desabilitada. A contagem é renovada após uma verificação bem-sucedida.
- Mantida a consulta segura via `checkupdates` sem `pacman -Sy`, proteção db.lck, console/PTY, registros, notificações e integração com autostart.
- Sem modificações no instalador de partições, no GRUB, no Baloo, no kernel ou na seleção de perfis além do identificador de versão.

## Validação

- Testes estáticos e unitários podem executar em qualquer Linux, sem pacman nem alterações no disco.
- Teste visual do menu e construção real da ISO precisam ocorrer no Arch Linux com Plasma, PySide6 e Archiso.
- Testar os estados: zero, atualizações encontradas, consulta parcial/erro, atualização ativa, cancelamento da confirmação e atualização concluída.
- Caso aprovado, promover 2.1.3 estável após smoke tests da nova ISO.
