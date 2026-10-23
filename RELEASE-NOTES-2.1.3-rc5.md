# Wolf Linux DevKit 2.1.3-rc5 — SmokeFix: origem dos assets Zsh e versões

- Corrigido descompasso da RC4: `branding-assets/zsh/zshrc` (arquivo de fato instalado pelo preparador) agora contém o mesmo fallback Powerlevel10k de `assets/zsh/zshrc`.
- O teste de ausência do Powerlevel10k passa a verificar o arquivo efetivamente transportado para a ISO, além da igualdade entre as duas cópias. A ausência do tema mantém prompt simples no Zsh e registra pendência sem abortar.
- Atualizadas as verificações antigas de versão: testam a versão real declarada em `VERSION`, `install/wolf-install.sh` e `wolf-customize-iso-profile.sh` sem uma lista estática de release candidates.
- O LTS de contingência, CachyOS, GRUB e Wolf Package Manager 0.3.4 permanecem inalterados em relação à RC4.
- Esta é uma versão candidata. ISO e instalação real devem ser validadas no Arch Linux/VM antes de promover para estável.
