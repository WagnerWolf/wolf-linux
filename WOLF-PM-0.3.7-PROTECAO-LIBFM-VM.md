# Wolf Linux 2.2.0 — proteção de integrações (validação em VM)

A versão `Wolf Package Manager 0.3.7` foi validada pelo usuário em VM quanto à instalação de libfm-qt Wolf, IgnorePkg e auditoria das integrações. A aplicação em hardware físico continua sujeita ao primeiro teste após a reinstalação. O Pacman recebe `IgnorePkg = libfm-qt` num bloco Wolf com backup, **depois** que a instalação da biblioteca personalizada termina. Durante `pacman -Syu` (incluindo atualizações realizadas por fora do Package Manager), a libfm-qt Wolf não é substituída automaticamente. Esse ajuste é um bloqueio de upgrades gerais, **não** de instalações explícitas `pacman -S libfm-qt` / `pacman -U`.

No Package Manager, "Integrações Wolf" possui botão para verificar o estado e para mostrar roteiro de compatibilidade. Se uma atualização oficial da biblioteca aparecer, o gerenciador pergunta se o usuário prefere atualizar os demais pacotes (a biblioteca fica protegida) ou revisar antes. Se uma nova ABI for exigida como dependência, a transação deve falhar: não usar `-Sy` isolado ou `--nodeps`.

**A adaptação do patch C++ para novas versões NÃO está automatizada.** Ainda exige baixar as fontes/receita correspondentes, revisar manualmente o patch, `pkgctl build` em chroot, validar SONAME/ABI, testar VM e recuperar o pacote oficial em caso de problemas.

## Gerar a ISO no Arch

Na raiz do DevKit extraído, copie o pacote `libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst` que já foi compilado e testado, para `release-packages/` e execute o validador, o smoke e o gerador. A ISO **não** é criada automaticamente neste ZIP. O gerador falha se o pacote estiver ausente.

```bash
cp "$HOME/wolf-libfm-build/libfm-qt-wolf-2.4.0-4.1/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst" ./release-packages/
bash tools/wolf-integration-monitor/validar-pacote-usb.sh ./release-packages/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst
bash tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-pm-guard-vm" ./gerar-iso-2.2.0.sh
```

## Homologação após instalar na VM

```bash
pacman -Q libfm-qt
pacman-conf IgnorePkg
wolf-libfm-guard --check
wolf-integrations-check
```

Abra Wolf Package Manager → Integrações Wolf → "Planejar atualização libfm-qt". A instalação deve manter a personalização e o item "Formatar unidade USB…" no menu dos dispositivos do PCManFM-Qt. Antes de testar qualquer formatação, use uma VM com dispositivo USB **descartável** ou apenas abra/cancele a interface. Para validar a proteção sem atualizar pacotes reais, use `wolf-libfm-guard --check` e os testes unitários do DevKit.

Reverter **somente a proteção** na VM, sabendo que ela deixa a biblioteca vulnerável a atualizações gerais:

```bash
sudo wolf-libfm-guard --remove
```

Reaplicar:

```bash
sudo wolf-libfm-guard --install
```

Ao aprovar uma nova biblioteca Wolf, gerar nova versão de pacote e validar em VM antes de liberar a atualização; jamais compilar/reinstalar como root dentro do hook do Pacman.
