# Wolf Linux 2.2.0 — Release estável LXQt/X11

**Data:** 01/11/2026  
**Base:** Wolf Linux 2.2.0-rc1 Patch 6 (painel e locais).  
**Homologação:** instalação e uso em máquina virtual confirmados pelo mantenedor.

## Escopo da promoção

A versão 2.2.0 estabiliza a base LXQt/X11 com as correções acumuladas dos Patches 1 a 6. **A promoção não muda a lógica testada de particionamento, perfil LXQt, painel, favoritos, kernels ou programas instalados**. Apenas atualiza os identificadores de versão, a identidade da Live e do sistema instalado, o gerador, os testes de regressão e a documentação.

## Destaques

- Kernel oficial Arch `linux` (principal), `linux-lts` (reserva), sem dependência do CachyOS para boot; tratamento de falha opcional no Chaotic-AUR.
- PCManFM-Qt padrão em lugar do Dolphin; associação de pastas, atalhos e favoritos XDG; menu contextual do VS Code conforme perfil.
- Painel principal completo em uma tela e painel secundário automático na presença de dois monitores; tray com NetworkManager Applet, Udiskie e serviços compatíveis.
- GNOME Disks e ação protegida para formatar mídia removível a partir de pastas montadas elegíveis.
- Wolf Control Center com gerenciamento de monitores; Wolf Package Manager com checagem pós-atualização.
- Correções de identidade Wolf Linux, remoção de autostarts herdados do Plasma e ferramenta opcional de diagnóstico do Chrome.

## Limites da homologação

A instalação foi validada em **VM**, não em hardware real nesta release. Recomenda-se ensaio em hardware físico antes de reinstalação com EFI e `/home` em LVM multidisco. Testes estáticos do DevKit não substituem essa etapa.

## Configurador de monitores LXQt

**Integração após homologação em VM:** o comando `wolf-control-center --monitors` (ou `wolf-monitors`) abre diretamente o editor Wolf; a entrada **Monitores (Wolf Linux)** aparece no menu. A entrada nativa `lxqt-config-monitor.desktop` é ocultada em `~/.local/share/applications` com backup criado pelo configurador LXQt. O pacote `lxqt-config` e o executável nativo continuam instalados.

O launcher verifica primeiro o editor completo da release em `/usr/local/lib/wolf-linux/control-center/` e aceita a instalação local em `${XDG_DATA_HOME:-~/.local/share}/wolf-linux/control-center/` como alternativa. A persistência de layout agora usa o caminho real do script que salvou o layout, corrigindo o caminho fixo antigo.

## Build

```
./tests/wolf-smoke-test.sh
./gerar-iso-2.2.0.sh
```

A saída é um DevKit que **gera** a ISO; o ZIP distribuído não contém a ISO pronta.

### Ajuste pós-release — posicionamento VS Code e cofre de credenciais

- Ação PCManFM-Qt usa `wolf-open-vscode-monitor`: abre janela nova do VS Code no
  monitor de origem, sem daemon de posicionamento.
- LXQt com GNOME Keyring, libsecret e Seahorse, integrados ao SDDM/PAM e ao
  autostart Secret Service da sessão.
- VS Code Development usa `password-store=gnome-libsecret`, sem criptografia
  básica. Arquivos `argv.json` que não são JSON puro são preservados.
- Smoke test de regressão adicional, sem modificar as rotinas de instalação
  de disco, EFI, LVM ou kernels.


## Consolidação USB integrada (2 de novembro de 2026)

- Opção de formatação somente no menu da unidade removível da barra lateral do PCManFM-Qt, por `libfm-qt` Wolf 2.4.0-4.1, validada em hardware físico.
- Ação legada de formatação de pastas removida na configuração nova e durante migração de `/home`, com backup.
- Formatador com `--device`, sistemas FAT32/exFAT/NTFS/ext4, verificações USB e duas confirmações.
- Wolf Control Center com atalhos para formatador, auditoria e Package Manager; monitoramento de alterações do pacote via hook seguro.
- Aplicação global Qt Fusion e GTK Breeze-Dark preservada.
- O pacote compilado não é redistribuído neste DevKit e deve ser fornecido pelo responsável pela ISO. O gerador recusa criar ISO sem ele, para não prometer uma integração ausente.

## Consolidação do Package Manager 0.3.7 (02/11/2026)

A revisão com integração de menu USB na `libfm-qt 2.4.0-4.1` e proteção `IgnorePkg` foi validada pelo mantenedor em VM: pacote, marcador Wolf, `IgnorePkg`, suporte `--device`, formatador e Control Center identificados. A ação gráfica de formatação na barra lateral já havia funcionado no hardware físico com a biblioteca Wolf, separadamente da ISO candidata. A atualização 0.3.7 mantém planejamento supervisionado para novas versões; não recompila patches.

Esta promoção apenas consolida os identificadores e a documentação. A ISO com a revisão 0.3.7 e sua instalação física ainda exigem testes próprios. O gerador precisa receber, em `release-packages/`, o pacote `libfm-qt-2.4.0-4.1-x86_64.pkg.tar.zst` compilado pelo mantenedor.
