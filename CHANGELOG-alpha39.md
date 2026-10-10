# Wolf Linux 2.0.0-alpha39 — Detecção semiautomática de instalações multidisco/LVM

## Entrega

- **Wolf Installer GUI 1.9**: na aba **Partições** > **Reutilizar partições existentes**, botão "Detectar instalações em TODOS os discos (inclui LVM)".
- Scanner privilegado **somente leitura** (`wolf_discovery.py`) usa `lsblk` para identificar partições e volumes lógicos; varre possíveis raízes ext4 lendo `etc/fstab`. Não executa `vgchange`, `fsck`, `mkfs`, `wipefs`, `grub-install`, nem ativa grupos LVM. Para ler `fstab` de raiz não montada, realiza montagem efêmera `ro,noload,nodev,nosuid,noexec`, desmontando em seguida.
- Identifica o mesmo LV LVM através de múltiplos PVs e não o duplica. Associa entradas por **UUID/PARTUUID**, não por comentários do `fstab` ou nome do LV.
- **Seleção semiautomática**: escolhe a instalação encontrada e sugere EFI e `/home`, com caixas editáveis que listam todos os SSDs e LVs compatíveis. Confirmação das associações e confirmação adicional quando diferem do `fstab`.
- Novo documento `wolf.install.multidisk.preview.v1` com identidades de volumes e dependências de PV, `execution=disabled`, ações declarativas raiz=format_ext4, EFI/home=preserve, mais usuário/hostname, teclado, perfil/stacks e avisos.
- O `wolf-install` aceita `--review-multidisk-plan` e `--simulate-multidisk-plan`: ambos reexecutam a descoberta e revalidam estado do armazenamento **antes** de apresentar o relatório. Não há rota desses documentos para o executor VM ou hardware físico.
- A versão de execução em VM preexistente (um disco VirtIO) continua isolada e com seu contrato v4; nenhuma nova operação destrutiva foi habilitada.

## Limitações intencionais

- Descoberta de instalações com raiz ext4 e `fstab` identificável por UUID/caminho; outros filesystems, LUKS fechado e LVM inativo requerem evolução própria.
- Scanner não ativa grupos LVM; somente volumes já expostos pelo kernel podem ser identificados.
- Apenas **revisão e simulação** multidisco. Não reinstala sistema físico nem formatará os SSDs. Formatação de raiz na prévia é uma operação **hipotética**.
- Executar sobre a Live UEFI ou BIOS de acordo com a instalação alvo. O scanner precisa de `sudo` e monta somente para consultar `fstab`, desmontando ao terminar.

## Testes locais

`python3 tests/wolf-test-alpha39.py`, `bash tests/wolf-test-live-desktop.sh`, staging Archiso simulado, `bash -n`, `python -m py_compile` e smoke test estrutural. A validação em sessão Qt/Live e a detecção física real serão realizadas pelo usuário.
