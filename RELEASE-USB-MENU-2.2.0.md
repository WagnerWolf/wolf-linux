# Wolf Linux LXQt 2.2.0 — Consolidação do menu de dispositivos USB

**Validado no hardware pelo usuário:** item `Formatar unidade USB…` aparece no menu de volumes do PCManFM-Qt e, com o formatador atualizado (`--device`), abre a unidade correta. Fusion/GTK, painel secundário QSettings, indicador de mídia pt_BR e migração XDG também foram validados pelo usuário.

## Alterações

- Remove apenas a ação Wolf legada de pastas montadas, com backup quando preserva `/home`.
- PCManFM-Qt: mantém exclusivamente ação do dispositivo no menu lateral (pacote `libfm-qt 2.4.0-4.1`).
- Formatador estável com `--device`, suporte FAT32, exFAT, NTFS e ext4, guarda USB/UDisks2 e confirmações.
- Control Center oferece auditoria de integrações, abertura do formatador e Package Manager.
- Package Manager reporta pacote Wolf detectado e monitora futuras alterações; **a versão e o checksum não bastam para validar binários automaticamente**.
- A ISO exige o pacote compilado pelo usuário, que não acompanha este ZIP. Falha antes do build caso ausente.

## Preparação obrigatória para gerar ISO

```bash
cp ~/wolf-libfm-build/libfm-qt-wolf-2.4.0-4.1/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst ./release-packages/
./tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-usb-release" ./gerar-iso-2.2.0.sh
```

Se o pacote não estiver nesse local, localize-o com `find ~/wolf-libfm-build -name 'libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst'`. Pacote de compilação debug separado não é necessário.

**Atenção:** qualquer atualização do `libfm-qt` via Pacman pode substituir a biblioteca customizada. O hook somente registra a necessidade de revisão. O Package Manager não recompila bibliotecas automaticamente, e a atualização do pacote Arch pode desativar a opção de menu até ser validada nova versão Wolf.

A compilação/instalação física de uma ISO gerada com esta consolidação específica permanece pendente, apesar da validação funcional anterior de cada componente.
