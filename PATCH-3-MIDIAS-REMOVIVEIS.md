# Wolf Linux DevKit 2.2.0-rc1 — Patch 3: mídias removíveis LXQt

Base: Patch 2 (PCManFM-Qt). Não modifica particionamento, LVM, bootloader ou identidade da distro.

## Componentes

- `udiskie` + `udisks2`: ícone na tray do painel principal LXQt (já configurado com `tray` e `statusnotifier`).
- `gnome-disk-utility`: interface madura de formatação, particionamento e informação de discos.
- `wolf-format-removable`: integração entre seleção de pastas montadas no PCManFM-Qt e o diálogo nativo `gnome-disks --block-device /dev/... --format-device`.
- Entradas: `~/.config/autostart/wolf-udiskie.desktop`, `~/.local/share/file-manager/actions/wolf-format-removable.desktop` e `/usr/share/applications/wolf-disks.desktop`.

### Política de montagem

O udiskie inicia com `--smart-tray --no-automount --file-manager=pcmanfm-qt`.
O ícone só fica visível quando há dispositivos/ações. Montagem manual disponível pelo ícone ou pela barra lateral do PCManFM-Qt. `--no-automount` evita automontagem concorrente com os recursos de dispositivos do PCManFM-Qt/GVfs. Notificações padrão permanecem ativas.

### Formatação com segurança

- A ação aparece em diretórios sob `/run/media/*` e `/media/*`. O `Folders=` é um filtro visual, **não uma barreira de segurança**.
- O helper revalida, imediatamente antes de invocar a interface, se o caminho selecionado é **a raiz exata de um volume montado**.
- Exige um dispositivo de bloco real associado a uma **partição**, não ao disco inteiro.
- Permite somente discos conectados por USB ou marcados pelo kernel como removíveis; recusa disco interno, partição LVM mapeada diretamente e outras origens não reconhecidas.
- Recusa discos com qualquer volume montado fora das árvores de mídia removível (por exemplo `/`, `/boot`, `/home`, swap ou `/mnt`).
- Nenhuma formatação é executada diretamente pelo helper, nem se recorre a `sudo`/`pkexec` ou `mkfs` próprios. O GNOME Disks faz suas confirmações e usa a autorização UDisks2/Polkit.
- Formatar apaga dados: **nunca formatar mídia importante sem backup**.

Limitação: ações customizadas do PCManFM-Qt se destinam ao menu de contexto de **arquivos e diretórios**. O item pode não aparecer no contexto de dispositivos da **barra lateral**. Para discos não montados, uma tabela de partições nova ou qualquer mídia não reconhecida pelo filtro, acessar **Menu → Discos e mídias (Wolf)** ou executar `gnome-disks`.

## Diagnóstico

```bash
# Inspecionar dispositivo sem ação destrutiva
wolf-format-removable --check "/run/media/$USER/NOME_DA_MIDIA"

# Verificar ícone e processo
pgrep -af udiskie

# Abrir o utilitário completo
gnome-disks
```

Para atualizar um `/home` reutilizado, o configurador cria um backup versionado sob `~/wolf-backups/lxqt/` com função de reversão. Execute a configuração fora da sessão LXQt.

## Testes

```bash
./tests/wolf-smoke-test.sh
python3 tests/wolf-test-removable-media.py
```

Os testes são simulados: não há escrita em discos, formatação ou montagem real. É necessário validar numa VM com dispositivo USB de testes, depois em hardware físico com pendrive descartável.
