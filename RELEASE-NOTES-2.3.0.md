# Wolf Linux 2.3.0 Stable — KDE Plasma / Wayland

## Origem e status

Base: KDE 2.3.0 Preview1 Fix3, **instalação VM concluída com sucesso** pelo mantenedor em 20/11/2026. Promovida a Stable com ajuste de navegador/Flutter. A build Stable não foi validada em VM nem hardware real neste ambiente; requer validação do mantenedor.

## Alterações da promoção

- `VERSION=2.3.0`, identidade instalada `PRETTY_NAME=Wolf Linux 2.3` e `VERSION_ID=2.3.0` (consistentes com a etapa 61 do instalador).
- Thorium AVX2 (`thorium-browser-avx2-bin` do AUR) substitui Google Chrome na stack Daily (Basic/Test/Full). O pacote é resolvido via Chaotic-AUR quando disponível, ou AUR com `yay`, já previsto pelo DevKit.
- Preflight AVX2 antes da operação destrutiva em perfis Daily.
- KDE `mimeapps.list` escolhe o desktop file Thorium disponível; Wolf Control Center prioriza Thorium nas associações.
- Flutter Web: `CHROME_EXECUTABLE=/usr/local/bin/wolf-thorium`, que resolve binário do Thorium instalado; sem alias Google Chrome. `wolf-flutter-doctor` revisado.
- A Live permanece Openbox + Chromium; o Minimal instalado permanece sem navegador adicional.
- Novos testes de regressão de browser/Flutter/versão e testes históricos do resolver AUR adaptados.

## Testes / critérios para hardware

1. Gerar ISO; validar o preflight gráfico do Archiso e seu SHA-256.
2. Em UEFI real, conferir disco e partições no resumo; não prosseguir se divergirem. Manter backups externos.
3. Após boot: `cat /etc/os-release`, `echo "$XDG_SESSION_TYPE"`, `pacman -Q thorium-browser-avx2-bin`, `command -v wolf-thorium`, `wolf-thorium --version`, `xdg-mime query default x-scheme-handler/https`, `nvidia-smi` (se NVIDIA), boot de kernel principal e LTS.
4. Testar monitores 180 Hz/60 Hz, Shorts no Thorium, atalhos, painéis KDE, Super+E, Package Manager e KWallet.
5. Para Full: `echo "$CHROME_EXECUTABLE"`, `wolf-flutter-doctor`, `flutter devices`, `flutter run -d chrome` em projeto de teste.

AUR é código mantido por terceiros; pacotes binários podem falhar/download não disponível. Se houver pendências, elas são registradas em `/var/log/wolf-optional-failures.log` e avisadas no instalador. Não desativar checks de assinatura/pacman.
