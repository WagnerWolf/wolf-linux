# Wolf Linux 2.2.0 LXQt — Fix6 (candidato a validação)

## Mudanças

1. **Painéis:** integração da correção Fix5 homologada: o botão *Aplicar painéis aos monitores* escreve `QStringList` com `QSettings`, verifica em um novo processo Qt e restaura o backup em caso de erro. A validação não confia apenas na linha `panels=`. O autostart reaplica na sessão sem watcher permanente.
2. **Remoção segura:** `wolf-removable-tray` é um indicador PySide6 com textos próprios em português, usa `lsblk` para apresentar apenas discos USB e `udisksctl` (UDisks2) para montar, desmontar e desligar unidades. Não executa operações com permissões de root diretamente, não faz automontagem nem formatação automática. O autostart Wolf do Udiskie é desabilitado, sem remover pacotes à força.
3. **Formatador:** `wolf-format-removable` mantém interface Qt em português, lista partições USB e oferece exFAT/FAT32/ext4, com duas confirmações, proteção contra partições do sistema e acesso controlado pelo UDisks2. No PCManFM-Qt, ação **Formatar unidade USB…** na seleção da raiz de uma pasta USB montada em `/run/media/...` ou `/media/...`. Também existe entrada no menu de aplicativos e no ícone Wolf de mídias para pendrives desmontados.
4. **Tema:** `wolf-appearance-dark --apply` restaura os estilos originais do Wolf-dark (QSS, menu, paleta), o estilo Qt Breeze, Breeze-Dark para GTK3/4, GSettings dark e configura XSETTINGS por `xsettingsd` no X11. O pacote `xsettingsd` passou ao perfil LXQt. Configurações anteriores recebem backups.

## Limitação do PCManFM-Qt

Ações customizadas atuam no menu de contexto de **arquivos e diretórios**. O menu de contexto dos **dispositivos da barra lateral** não oferece a mesma extensão. Não é correto prometer integração nesse menu sem modificar o próprio PCManFM-Qt. Como alternativa, use o menu do indicador Wolf (Formatar unidade USB…) ou o lançador de aplicativos. Para que o novo menu de pasta apareça, reinicie o PCManFM-Qt/desktop LXQt após a instalação do atalho.

## Atualizar somente o sistema já instalado

Na pasta `wolf-linux-devkit-2.2.0`:

```bash
bash atualizar-paineis-pastas-control-center.sh --check
# Caso não esteja presente, instale xsettingsd na próxima atualização completa:
sudo pacman -Syu --needed xsettingsd
bash atualizar-paineis-pastas-control-center.sh --apply
```

Reinicie a sessão LXQt (não o computador necessariamente). Feche e reabra o Control Center e use **Monitores → Aplicar painéis aos monitores** e **Aparência e atalhos → Reaplicar Wolf-dark (LXQt + GTK)**. Depois reabra Blueman.

Para conferir o formatador sem alterar dados, execute `wolf-format-removable --browse`, veja a lista e feche a janela **sem confirmar**. Para validar uma formatação real, use apenas um pendrive de testes vazio ou descartável, confirmando o dispositivo e a capacidade.

O instalador de atualização NÃO aplica a formatação nem altera a disposição de monitores. Backups em `~/wolf-backups/`. Para reverter a lista Qt do painel, restaure o `panel.conf` de backup **fora da sessão LXQt**.

## Validação

- Smoke estático do DevKit aprovado; testes de regressão multidisco/LVM (6) aprovados.
- Testes em memória com USB fictício, Qt simulado e atalhos PCManFM-Qt aprovados.
- **Não testado graficamente:** indicador na tray, menus USB, formatação real, temas GTK no hardware do usuário e funcionamento integrado pós-login. Não promover Fix6 à condição de homologado até esses testes.
- Fix5 portátil para painéis: o usuário confirmou funcionamento no hardware; a integração no Control Center ainda depende de validação.
