# Wolf Linux DevKit 2.0.0-alpha48 — integração de PTY físico

- Corrigida a divergência alpha47: `main.py` disparava o executor físico, mas
  `terminal_engine.py` recusava o modo com `Modo de execução PTY não autorizado`.
- Acrescentado `--execute-multidisk-physical` ao conjunto FINITO e explícito de
  modos autorizados no PTY. Não foi habilitado `--install` genérico nem shell
  arbitrário. `sudo -n wolf-install <modo> <plano>` permanece fixo.
- Mantidos sem alteração os validadores de UUID/PARTUUID, fstab, LVM multi-PV,
  dois NVMe, boot UEFI, ambiente Live, confirmação dupla e rechecagem imediatamente
  antes do mkfs.ext4; EFI, /home e outras partições não são formatadas pelo plano.
- Avisos da GUI atualizados para não sugerir que hardware físico continua bloqueado
  e para esclarecer que a presença de backup geral não é verificada.
- Teste de regressão PTY com `sudo` falso em ambiente temporário: duas confirmações,
  código de saída, modo físico e recusa de comandos não autorizados. Sem operações
  em discos; execução real física ainda exige homologação pelo usuário.
