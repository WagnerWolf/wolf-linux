# Wolf Linux 2.2.0 — Fix7 NTFS e GTK/X11

## O que muda
- **NTFS no formatador:** opção adicional no Wolf Formatador USB. Requer `mkfs.ntfs` (pacote `ntfs-3g`, já previsto no perfil base), utiliza a interface UDisks2 e mantém verificações de USB, duas confirmações e a política de não formatar discos internos.
- **GTK:** `wolf-appearance-dark --apply` verifica a instalação real de Breeze-Dark, grava ajustes GTK3/GTK4, GSettings, inicia o `xsettingsd` se não estiver ativo e recarrega o daemon Wolf quando já existe. Agora `--check` mostra os processos e, se disponível, o tema XSETTINGS efetivo.
- **Login:** `wolf-gtk-xsettings` usa um caminho de configuração **explícito** para evitar a precedência de `~/.xsettingsd` antigo.

## No sistema instalado (sem reinstalar)

```bash
sudo pacman -Syu --needed xsettingsd breeze-gtk ntfs-3g
bash atualizar-paineis-pastas-control-center.sh --check
bash atualizar-paineis-pastas-control-center.sh --apply
wolf-appearance-dark --check
wolf-appearance-dark --apply
wolf-appearance-dark --check
```

Feche e reabra o Blueman e outros aplicativos GTK. Se um outro processo controlar XSETTINGS, o script exibirá aviso e **não o interromperá**. Feche o configurador de aparência LXQt e reinicie a sessão para que o daemon Wolf assuma.

A formatação permanece uma operação irreversível: teste a GUI em `wolf-format-removable --browse` e só formate uma partição USB descartável após revisar o dispositivo mostrado.

## Limites
- A integração pelo PCManFM-Qt permanece no contexto de **pastas** de mídias montadas; não altera o menu de dispositivos da barra lateral.
- Um aplicativo GTK já em execução pode manter a aparência anterior até ser reiniciado.
- Apps libadwaita podem seguir regras próprias, mesmo com `color-scheme=prefer-dark`.
- GTK real e formatação real necessitam validação física; smoke test é simulado.
