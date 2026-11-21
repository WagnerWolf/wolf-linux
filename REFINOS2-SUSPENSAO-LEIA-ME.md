# Wolf Linux 2.3.0 — Refinos 2: utilitário de suspensão opcional

Base: 2.3.0 Stable — Refinos 1 BuildFix 3. A alteração desta revisão é **somente a integração** do utilitário de suspensão opcional.

## O que aparece após instalar a ISO

No menu de aplicativos KDE: **Wolf Linux - Desativar suspensão (opcional)**.

Ao abrir a opção, um Konsole apresenta o resultado e solicita `sudo` quando for instalar a política systemd. **A instalação da ISO não desativa a suspensão e não executa o utilitário automaticamente.**

Também está disponível no Konsole:

```bash
wolf-sem-suspensao --status  # leitura, sem alterar
wolf-sem-suspensao --apply   # desativa suspensão/hibernação e usa wallpaper Wolf no bloqueio
wolf-sem-suspensao --undo    # reverte as seis preferências e remove política Wolf
```

O menu KDE também disponibiliza as ações **Consultar estado** e **Restaurar suspensão** ao abrir o menu de contexto do aplicativo.

O aplicativo opcional não mexe em brilho, NVIDIA, SDDM, modo dos monitores, atalhos, desktop nem pastas do usuário. Mantém o bloqueio de tela funcionando. A imagem usada é a já instalada em `/usr/share/backgrounds/wolf-linux/wallpaper.png`.

## Preparação e geração da ISO

No diretório do DevKit:

```bash
./preparar_ambiente_wolf_linux.sh
./gerar-iso.sh
```

Ou apenas `./gerar-iso.sh`, que prepara o ambiente se não encontrar o projeto.

**Projeto novo isolado**: `~/wolf-linux-2.3.0-refinos2-suspensao`; saída em `out/`. Não use `--resume` na pasta antiga do BuildFix 1; os instaladores agora têm conteúdos diferentes.

## Observação de homologação

Os testes estáticos do DevKit e o teste de integração opcional devem passar antes de gerar a ISO. A compilação do Archiso e a instalação limpa no hardware ainda exigem validação no seu Arch Linux.
