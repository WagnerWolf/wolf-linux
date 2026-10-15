# Changelog — Wolf Linux DevKit

## 2.1.0 — lançamento estável (2026-10-15)

- Promovida a 2.1.0-rc1 validada pelo mantenedor, sem alterações funcionais no instalador, particionamento ou boot.
- Identidade de versão padronizada no DevKit, Live e sistema instalado; documentação oficial atualizada.
- Inclui Wolf Package Manager 0.3.1 em substituição ao Octopi, com autostart na bandeja e integração ao Control Center.

## 2.1.0-rc1 — prévia (2026-10-15)

- Substitui Octopi por Wolf Package Manager 0.3.1.
- Autostart KDE, Control Center, dependências pacman-contrib e yay.
- Teste da ISO/instalação ainda pendente.

## 2.0.0 — lançamento final (2026-10-14)

- Promovida a base alpha59 para a versão 2.0.0 após testes práticos de instalação e inicialização UEFI informados pelo mantenedor.
- Padronização de `VERSION`, versão de reserva do instalador, identidade `/etc/os-release`, identificação da Live e documentação pública.
- Interface gráfica única com teclado primeiro, três modos de armazenamento, escolha obrigatória de perfil, revisão e confirmações por clique, terminal integrado.
- Tratamento de dependências opcionais, prévia de dotfiles e provisão seletiva de Vulkan conforme o hardware foram consolidados na linha alpha56–alpha59.
- Preservadas as proteções de disco, o executor Bash, as verificações de GRUB/EFI e os testes históricos.
- Arquivada documentação de desenvolvimento das versões alpha em `docs/historico-alphas/`.

Nenhuma nova lógica de particionamento, formatação, GPU ou GRUB foi introduzida nesta promoção de versão.

Histórico detalhado: `docs/historico-alphas/CHANGELOG-alpha59.md` e os arquivos de revisões anteriores.
