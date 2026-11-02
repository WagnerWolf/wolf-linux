# Wolf Linux 2.2.0 — Release LXQt / Package Manager 0.3.7

**Promoção em 02/11/2026 após validação em VM do mecanismo de proteção da integração USB.**

A base do DevKit é a Preview 0.3.7 já testada. Nesta promoção, apenas a versão e a documentação foram consolidadas; a configuração do particionamento, kernels, EFI/LVM, interface LXQt e política de atualização não foram alteradas.

## Como gerar a ISO no Arch Linux

Execute a partir da **raiz do DevKit extraído**, depois de conferir a existência do pacote compilado pelo mantenedor:

```bash
cp "$HOME/wolf-libfm-build/libfm-qt-wolf-2.4.0-4.1/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst" ./release-packages/
bash tools/wolf-integration-monitor/validar-pacote-usb.sh ./release-packages/libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst
bash tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-pm-0.3.7-release" ./gerar-iso-2.2.0.sh
```

O projeto de compilação não pode existir previamente. O gerador **falha** quando o pacote binário Wolf está ausente. Ele não é distribuído neste ZIP. Se o repositório oficial já não disponibilizar a `libfm-qt 2.4.0-4` esperada na instalação, o instalador interromperá a etapa de integração em vez de forçar ABI diferente. Não tente contornar a checagem.

## Conferência após o primeiro boot (VM ou instalação física)

```bash
pacman -Q libfm-qt pcmanfm-qt
pacman-conf IgnorePkg
wolf-libfm-guard --check
wolf-integrations-check
```

Abra **Wolf Package Manager → Integrações Wolf** e confira a auditoria e o botão **Planejar atualização libfm-qt**. Conecte um pendrive **descartável**: confira a ação de formatação pelo menu do dispositivo no PCManFM-Qt, apenas abrindo a janela e cancelando. Confirme ainda o funcionamento do painel em ambos os monitores, o estilo Fusion, GTK escuro, rede e a restauração da disposição dos monitores.

## Proteção da biblioteca

`IgnorePkg` preserva a biblioteca durante atualizações gerais; não impede todas as instalações explícitas. O Package Manager verifica a proteção antes de suas próprias operações e avisa ao detectar atualização oficial da biblioteca. O botão de planejamento **não recompila nem atualiza automaticamente**. O hook do Pacman somente registra alterações após a transação. Uma nova versão da `libfm-qt` exige revisão do patch, compilação isolada e testes de ABI/VM antes de atualização. Não deixe de atualizar indefinidamente pacotes críticos por causa da proteção; resolva incompatibilidades em versão futura.

## Cuidado com reinstalação física e LVM

Antes de reinstalar, mantenha backup externo, confira `lsblk -f`, EFI, raiz, `/home` LVM e opções de formatação na revisão gráfica. Não presuma que o teste em VM valida automaticamente a topologia física.
