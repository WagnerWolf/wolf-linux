## Wolf Linux 2.1.2 — release (16/10/2026)

- Promovida a 2.1.2-rc1 SmokeFix2 após validação da instalação Basic em VM relatada pelo usuário; nenhuma mudança de armazenamento/GRUB/EFI.
- Wolf Package Manager 0.3.3: controle de retorno de cursor, barra de progresso incremental no terminal Qt, UTF-8/ANSI por blocos, log preservado; 51 testes upstream.
- Kernels e módulos NVIDIA permanecem inalterados aguardando análise da falha de boot Zen. Plasma 6.8.0 multimonitor permanece upstream.

## 2.1.2-rc1 — SmokeFix 2 (16/10/2026)

- Corrige uma falha de execução da etapa 64 (`install_selected_stack_packages`): as funções de coleta podiam terminar com código 1 quando a última stack não estava selecionada. Sob `set -Eeuo pipefail` e o `ERR trap`, o diagnóstico "FALHA NA INSTALAÇÃO" era escrito no stdout da substituição de processo e passava a ser interpretado como nomes de pacotes AUR.
- As três funções de coleta agora retornam sucesso explicitamente (`return 0`) e usam ramificações `if` sem falso erro ao consultar uma stack não selecionada.
- O resolvedor rejeita qualquer nome de pacote incompatível com o formato esperado antes de executar `pacman` ou `yay`, protegendo todos os perfis.
- Novo teste funcional `wolf-test-aur-stdout-2.1.2.py`, integrado ao smoke test; usa um Bash `ERR trap` real com comandos `pacman/yay` simulados e executa perfis Minimal, Basic, Test e Full sem operações de instalação.
- Sem mudanças no particionamento, bootloader, UI Qt ou regras de permissões do /home.

### 2.1.2-rc1 SmokeFix 1 — ShellCheck
- Documentada expansão deliberada de variáveis pelo `/bin/sh` dentro do `arch-chroot`, suprimindo SC2016 somente no teste de escrita do cache.
- Nenhuma alteração na lógica do instalador.

## 2.1.2-rc1 — Basic, ferramentas auxiliares e propriedade do cache
- Adicionado perfil Basic (Daily reduzida) sem stacks Gaming/Development.
- GIMP, OBS Studio e Transmission movidos para Extras, mantendo Test/Full.
- Correção dos nomes invisíveis na lista de ferramentas da sessão Live.
- Criação segura de ~/.cache como usuário; proteção contra diretórios de outros UID, links e teste real de escrita.
- Testes de regressão de perfil, UI, cache, multidisco/LVM e terminal.

### SmokeFix 2 (Live GUI, 2.1.1)
- Corrige importação Qt fatal do QTextCursor e adiciona teste funcional pós-mkarchiso no ambiente da Live.
- Captura erros de inicialização automática em log.

### Correção de empacotamento — smoke test 2.1.1 (2026-10-16)

- Isolado o teste do Wolf Control Center do autostart global já instalado na máquina do mantenedor.
- Adicionados cenários para autostart ausente, autostart global ativo e prioridade da desativação por usuário.
- Comportamento do Control Center e da instalação preservado; sem alterações em particionamento, LVM, EFI, boot ou pacotes.
- Smoke test executado novamente com código de saída 0 no ambiente de validação; compilação da ISO ainda deve ser validada no Arch Linux.

## 2.1.1 — lançamento estável (2026-10-15)

- Promovida a RC2 após instalação física e boot bem-sucedidos com EFI e raiz em NVMe distintos e `/home` LVM multidisco preservado.
- Mantida a correção do terminal PTY para progresso `\r` do pacman.
- Instalado override systemd exclusivo do Baloo (`QT_QPA_PLATFORM=offscreen`) após validação sem novos crashes depois do reboot.
- Wolf Package Manager atualizado de 0.3.1 para 0.3.2, com revisão da consistência da verificação de atualizações.
- Identificação de versão, Live, sistema instalado e documentação padronizadas para 2.1.1.
- Sem alterações funcionais nas rotinas de particionamento, formatação, GRUB e seleção de GPU.

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

## 2.1.1-rc1 — 2026-10-15

- Compatibilidade de planejamento/executor com UEFI e raiz em discos distintos e /home LVM ext4 preservada; prévia de dotfiles em LVM.
- Candidato de homologação física: não promover até testes reais.

## 2.1.1-rc2 — 2026-10-15

- Corrigida visualização incremental do terminal PTY do instalador gráfico: retornos de cursor sobrescrevem apenas a linha ativa, sem repetir quadros de progresso do pacman.
- Mantidos o log de instalação, entrada interativa, proteções de disco e comportamento do executor da 2.1.1-rc1.
- Acrescentados testes de fragmentação de saída, CRLF, progresso e staging da Live.
