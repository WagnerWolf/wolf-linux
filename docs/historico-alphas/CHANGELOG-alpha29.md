# Wolf Linux 2.0.0-alpha29 — Piloto manual em VM e correções de armazenamento

## Base preservada

- Derivado da alpha28 (instalação gráfica limpa + tela final validadas pelo usuário).
- KDE Plasma/Wayland instalado, branding, Control Center, MultiMonitor, rede live e stacks mantidos.
- Alpha18 baseline estável e versões anteriores não modificadas.

## Instalação gráfica

- GUI 0.9: campos e rótulos distintos para **raiz /** (sistema), **EFI /boot/efi** (boot) e **/home** (arquivos pessoais, partição opcional).
- "Apagar disco inteiro" apaga todas as partições existentes, mesmo que o disco já tenha GPT/MBR, criando uma ESP e a raiz; /home fica dentro de /. Exige disco VirtIO de VM QEMU/KVM e verificação de montagem/swap.
- Confirmação textual reduzida a `APAGAR`, exigida tanto na janela gráfica quanto no Bash, depois de mostrar disco e partições afetados.
- **Manual UEFI experimental:** partições são CRIADAS/formatadas previamente pelo operador no GParted. A GUI atribui /, EFI e /home opcional. Backend revalida e monta as partições via fluxo `reuse-manual`, formatando APENAS a raiz / em ext4. ESP (FAT32, tipo GPT EFI System, >=512 MiB) e /home separada ext4 são preservadas (sem formatação). Raiz >=20 GiB e disco >=32 GiB.
- BIOS manual, LVM, criptografia, volumes em discos diferentes, formatação automática de ESP ou /home, e instalação gráfica em hardware real continuam **bloqueados**.
- "Reutilizar partições" segue revisão/simulação, com botão de instalação desabilitado. Validar preservação de dados antes de habilitar.
- A GUI não executa ferramentas destrutivas diretamente. O validador exige plano JSON canônico e identidade atual dos dispositivos antes da confirmação e imediatamente antes da instalação.

## Minimal/AUR

- O resolvedor de pacotes ignora entradas vazias, inclusive emitidas por arrays opcionais vazios.
- Adicionado teste para preset Minimal sem stacks opcionais: não deve invocar pacman/yay na etapa de stacks.
- A origem exata do relato `[AUR 1/31]` não foi reproduzida; validar novamente numa instalação Minimal real e encaminhar package-resolution.log se persistir.

## Verificações realizadas fora da VM

- `bash -n` e compilação Python.
- Smoke test completo.
- Testes sintéticos de planos adulterados/partições não pertencentes ao disco/discos montados/ESP sem flag/EFI com FS inadequado/raiz pequena, sem qualquer escrita em bloco.
- Teste do caminho Minimal com `arch-chroot` simulado bloqueando toda chamada ao gerenciador de pacotes.
- Preparação e staging Archiso simulados; build real e inicialização ainda precisam de validação na VM do usuário.

## Teste recomendado na VM descartável UEFI

1. Faça snapshot ou use um novo disco VirtIO (80 GiB).
2. Na Live, abra GParted e crie tabela GPT, ESP FAT32 1 GiB com flag **esp**; raiz ext4 40 GiB; restante opcional /home ext4. Aplique as operações no GParted.
3. Atualize a lista de discos na GUI, selecione o disco e **Avançado/manual**.
4. Selecione **Raiz /** na partição ext4 criada, selecione **EFI /boot/efi** na FAT32, e escolha **/home dentro da raiz** ou **/home em partição dedicada** com a partição ext4 criada.
5. Marque **Formatar RAIZ /**; leia o aviso. Não habilite formatação da EFI nem /home, que devem ser preservadas.
6. Selecione Minimal ou Test; valide e simule. Na aba Revisão, clique **Instalar nesta VM — MANUAL UEFI** e confirme com `APAGAR` nas duas etapas.
7. Depois da conclusão, use a tela de reinicialização e verifique o boot pelo disco instalado.
8. A validação do modo Reutilizar será uma próxima etapa, aproveitando o layout instalado após snapshot.
