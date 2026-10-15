# Wolf Linux DevKit 2.0.0-alpha45 — diagnóstico ext4 somente leitura

Base: alpha44 validada em laboratório multidisco. A alpha45 resolve a falha
observada quando a partição raiz existia, mas não podia ser montada com
`ro,noload` devido a `needs_recovery` e `orphan_present` no ext4.

## Alterações

- Dependência `e2fsprogs` declarada na Live, para assegurar `tune2fs` e
  `e2fsck` apenas para diagnóstico manual.
- `wolf_discovery.py`: consulta `tune2fs -l` **sem escrita**, após confirmar
  dispositivo de bloco e antes de montar um ext4 não montado. Em caso de
  recuperação pendente, recusa a candidatura da raiz e registra diagnóstico
  explícito com dispositivo e flags detectadas. Não usa `fsck`, recuperação
  automática do journal, `mount` com replay, nem altera UUIDs.
- Falhas reais de `mount -o ro,noload,nosuid,nodev,noexec` agora produzem
  mensagens nos `errors` do inventário (em vez de desaparecer silenciosamente).
- GUI: área visível para os detalhes da detecção, com texto não editável e
  quebra de linha. O scanner nunca autoriza execução física.
- Testes alpha45 simulam `needs_recovery`, `orphan_present`, ext4 limpo,
  falha de montagem e propagação dos erros até o scanner.
- Consolidação do comentário `shellcheck disable=SC2016` na chamada de
  `runuser` com `/bin/sh -c`, pois a expansão das variáveis é deliberada no
  shell dentro do `arch-chroot`. Sem alteração funcional do executor.

## Segurança e homologação

Na VM alpha44, a reinstalação multivolume foi validada pelo usuário com
raiz formatada, EFI/NTFS/LVM preservados, home `wolf:wolf` UID/GID 1000 e
prova de escrita bem-sucedida. O tratamento do ext4 pendente foi inspirado
pela falha real de montagem vista na Live antes de `e2fsck` manual.
A alpha45 ainda necessita boot/GUI real pelo usuário; nenhuma instalação
física destrutiva é autorizada pela GUI multidisco.
