# Changelog — Wolf Linux DevKit

## 2.0.0 — lançamento final (2026-10-14)

- Promovida a base alpha59 para a versão 2.0.0 após testes práticos de instalação e inicialização UEFI informados pelo mantenedor.
- Padronização de `VERSION`, versão de reserva do instalador, identidade `/etc/os-release`, identificação da Live e documentação pública.
- Interface gráfica única com teclado primeiro, três modos de armazenamento, escolha obrigatória de perfil, revisão e confirmações por clique, terminal integrado.
- Tratamento de dependências opcionais, prévia de dotfiles e provisão seletiva de Vulkan conforme o hardware foram consolidados na linha alpha56–alpha59.
- Preservadas as proteções de disco, o executor Bash, as verificações de GRUB/EFI e os testes históricos.
- Arquivada documentação de desenvolvimento das versões alpha em `docs/historico-alphas/`.

Nenhuma nova lógica de particionamento, formatação, GPU ou GRUB foi introduzida nesta promoção de versão.

Histórico detalhado: `docs/historico-alphas/CHANGELOG-alpha59.md` e os arquivos de revisões anteriores.
