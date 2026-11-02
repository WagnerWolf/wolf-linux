# Wolf Linux 2.2.0 — Painéis e diretórios no Control Center

Esta atualização amplia a 2.2.0 já instalada, mas **ainda necessita teste físico**.

## O que mudou

- `Wolf Control Center > Monitores`: **Verificar painéis e monitores** e **Aplicar painéis aos monitores**. O segundo comando recria painéis ausentes, reaproveita lançadores do primeiro painel e sincroniza `panel1..panelN` com o XRandR. Não usa watchers permanentes. O painel principal mantém status notifier, tray e volume.
- Salva `panel.conf` em `~/wolf-backups/lxqt-panels/` antes de alterar. Reinicia `lxqt-panel` somente quando necessário.
- `Wolf Control Center > Sistema`: prévia e migração explícita dos diretórios XDG pt_BR. Respeita pastas personalizadas, não substitui arquivos em conflito e mantém a configuração original das pastas que ainda têm conflitos.
- Pastas que foram criadas vazias na instalação podem receber arquivos da pasta inglesa automaticamente **após confirmação**; favoritos do PCManFM-Qt são atualizados.
- A release continua 2.2.0; kernels, instalação, partições e boot não mudaram.

## Testar antes de criar nova ISO

Dentro da pasta extraída:

```bash
bash atualizar-paineis-pastas-control-center.sh --check
bash atualizar-paineis-pastas-control-center.sh --apply
```

Feche e reabra o Control Center. Na seção **Monitores**, primeiro confira e depois aplique. Na seção **Sistema**, pré-visualize e só então confirme a migração. Quando alguma entrada possuir colisão, o arquivo original é preservado e deve ser revisado manualmente. Não execute a migração com PCManFM-Qt aberto em pastas alteradas.

## Validação

Testes estáticos/simulados executados em ambiente isolado; ainda é necessário validar no LXQt físico, especialmente o comportamento do `lxqt-panel` ao reiniciar.
