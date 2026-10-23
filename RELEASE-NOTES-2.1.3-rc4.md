# Wolf Linux DevKit 2.1.3-rc4 — Powerlevel10k opcional e fallback Zsh

- Corrige interrupção após o usuário pular Chaotic-AUR e a instalação AUR de `zsh-theme-powerlevel10k` não concluir.
- `install_wolf_kde_personal_defaults` não usa mais `die` na falta de um tema opcional; registra pendência em `/var/log/wolf-optional-failures.log`.
- O perfil `.zshrc` carrega o Powerlevel10k apenas se o tema existir; senão mantém Zsh com um prompt simples e legível, conservando os plugins locais disponíveis.
- Mantém as correções da RC3 para Chaotic-AUR/CachyOS + fallback ao LTS e o Package Manager 0.3.4.
- A ISO precisa ser compilada em Arch Linux e validada na VM (inclusive Chaotic-AUR indisponível).
