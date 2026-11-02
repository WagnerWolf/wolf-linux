# Wolf Package Manager 0.3.7

Gerenciador de pacotes do **Wolf Linux**, em PySide6, com pacman + yay, verificação periódica, bandeja e seção Integrações Wolf no LXQt.

## Instalação (usuário comum)

```bash
sudo pacman -S --needed pyside6 pacman-contrib util-linux
# Necessários também: pacman, sudo, yay
./iniciar.sh
./install-local.sh
```

Encerre a versão anterior pelo menu da bandeja antes de substituir os arquivos; depois reinicie o gerenciador. O instalador grava os lançadores em `~/.local/bin`, no menu de aplicações e em `~/.config/autostart`. Para não abrir janela no login, o autostart usa **`wolf-package-manager --tray`**. A abertura pelo menu usa o comando sem parâmetro. Se o Plasma não oferecer bandeja, a janela aparece para não sumir silenciosamente.

## Pesquisa mais rápida (0.3.1)

No filtro **Todos**, as fontes Repositório, AUR e Comandos são consultadas em
paralelo, em vez de uma após a outra. O aplicativo informa o avanço por fonte.
Resultados de pesquisas repetidas são mantidos **somente em memória** por até
cinco minutos, evitando repetir consultas à rede e ao índice de arquivos. A
memória de pesquisas é descartada após instalação ou atualização bem-sucedida.
A busca AUR ainda depende da rede e pode continuar lenta quando o servidor
estiver indisponível. Use o filtro Repositório para consultas exclusivamente locais.

## Pesquisa e instalações em lote

- Filtro **Todos / Repositório / AUR / Comandos**. Em **Todos**, pesquisa também arquivos de comandos disponíveis nos índices de repositórios.
- Para pesquisar quem fornece `nc`, é preciso ter os bancos `repo.files` sincronizados. Execute **uma vez** `sudo pacman -Fy` (ou atualize quando o índice estiver desatualizado). A busca consulta `pacman -F --machinereadable` sem elevar privilégios. Os arquivos AUR não estão nesse índice.
- Marque as caixas da primeira coluna para escolher vários pacotes. O botão **Instalar pacotes marcados** executa um único `sudo -A pacman -Syu` para os repositórios e, caso haja seleção AUR, uma única chamada `yay -S --aur --needed` como usuário comum, **somente após sucesso do pacman**.
- Instalações e atualizações exigem confirmação gráfica, e o `sudo -A` pede senha em diálogo. O terminal PTY continua com entrada manual para casos especiais.

## Segurança e diagnóstico

- A presença de `/var/lib/pacman/db.lck` bloqueia novas operações iniciadas pelo gerenciador, mesmo quando aparenta ser uma trava antiga.
- O botão **Analisar db.lck** mostra processos relevantes, idade e utilização visível pelo `fuser`; **não remove** a trava automaticamente. Se estiver inconclusivo, não remova a trava; examine processos de pacman, hooks e DKMS antes de qualquer intervenção. Não reinicie durante transações.
- **Diagnóstico** coleta leitura de `/var/log/pacman.log`, `dkms status`, pacotes kernel/NVIDIA, mensagens de kernel do boot atual/anterior, processos e espaço. Logs de operações ficam em `~/.local/state/wolf-package-manager/logs/` com `0600`; podem conter nomes de arquivos e caminhos. Revise antes de compartilhar.
- A ausência de saída por 90s gera aviso, mas não encerra transações automaticamente. `--noconfirm` não impede todas as perguntas ou falhas; AUR pode executar scripts de terceiros, por isso a opção automática pode ser desativada.
- Este aplicativo **não é um substituto para as ferramentas de recuperação** do Arch. Um bloqueio durante DKMS/mkinitcpio exige checagem dos logs antes de atualizar novamente ou reiniciar.

## Testes

```bash
python3 -m unittest discover -s tests -v
python3 -m compileall -q wolfpkg
bash -n iniciar.sh install-local.sh uninstall-local.sh wolfpkg/askpass.sh
```

A aplicação Qt e as transações reais ainda precisam ser validadas no KDE. O DevKit oficial 2.0.0 não foi alterado.

## Verificação consistente de atualizações (0.3.2)

- Continua usando `checkupdates --nocolor` (banco temporário separado, sem sincronizar `/var/lib/pacman/sync`); **não** executa `pacman -Sy` para verificação.
- Quando a base isolada retorna zero, consulta também `pacman -Qu` para detectar divergência com o índice local, mostrando aviso em vez de "nenhuma atualização". Uma divergência não prova qual base está correta; confira os mirrors.
- Se `db.lck` estiver presente ou `/var/log/pacman.log` mudar durante a consulta (por exemplo, `sudo pacman -Syu` foi iniciado em outro terminal), descarta os resultados como potencialmente obsoletos. Tenta novamente depois de 60 segundos.
- A interface diferencia consulta parcial/adiada de ausência real de atualizações. Uma notificação antiga não deve ser mostrada após atualização concorrente detectável.
- Limitação: nenhum cliente pode garantir que não surgirá atualização entre a consulta e uma posterior atualização; `pacman -Syu` permanece a autoridade para aplicar atualizações.

## Baloo KDE

Os crashes de `baloo_file_extractor` devem ser investigados separadamente: nos logs do usuário o Qt não encontrou o socket Wayland e falhou também com o fallback XCB. Esse problema não é causado por uma consulta `checkupdates` e não é corrigido pelo aplicativo.

## Terminal de progresso (0.3.3)

As atualizações da barra do pacman feitas via CR são redesenhadas na linha atual, sem duplicar blocos. A apresentação não modifica a saída capturada nem os comandos. O widget Qt não quebra automaticamente linhas longas; é possível navegar horizontalmente. UTF-8 e sequências ANSI são decodificados incrementalmente.

## Atalho no menu da bandeja (0.3.4)

- Menu de contexto do ícone: **Atualizar sistema (N)** quando uma verificação completa encontrar N atualizações. Sem atualizações, durante consulta/transação ou com resultado parcial, a ação fica desabilitada.
- Ao clicar, abre a página de Atualizações e executa o mesmo fluxo da interface principal, com confirmação gráfica, inspeção de `db.lck`, `pacman -Syu` e somente depois `yay -Sua --aur` (com sudo askpass). Não inicia alterações sem confirmação.
- Durante operações ou verificações a ação fica indisponível. Uma nova consulta depois de instalar ou atualizar renova o número exibido.
- A indicação reflete a última verificação bem-sucedida; podem surgir novas atualizações depois dela.


## Verificação pós-atualização (0.3.5)

Depois de uma etapa `pacman -Syu`, o programa executa em segundo plano uma **conferência somente leitura** antes de passar ao `yay`. Também confere novamente depois da etapa AUR na atualização completa. O botão **Verificar boot/DKMS**, na página Terminal, permite executar a mesma conferência manualmente após atualizações feitas por outro programa.

A rotina identifica kernels instalados, compara os artefatos em `/usr/lib/modules` e `/boot`, lê os destinos literais nos presets de `mkinitcpio`, consulta `dkms status` para os módulos NVIDIA em cada kernel e verifica a consistência do banco com `pacman -Dk`.

- Se faltar kernel, initramfs/preset ou NVIDIA DKMS, mostra um alerta e **não considera o plano seguro para continuar ao AUR**. Não executa reparos nem remove/atualiza pacotes por conta própria.
- Falhas não críticas de leitura e verificações não aplicáveis são descritas como **ressalvas**, não como garantia de estabilidade.
- A verificação funciona em *thread* Qt para não bloquear a interface; mostra detalhes no terminal e registra no log da operação.
- A checagem de `mkinitcpio` cobre presets padrão (`default_image` ou `default_uki` com caminho literal). Boot por dracut, rEFInd, UKI ou layouts personalizados podem exigir verificação manual. O diagnóstico é uma camada de proteção, não substitui testes de inicialização.
- O código de retorno de `pacman` continua determinando o sucesso da transação. Um retorno 0 **não prova** que todos os hooks geraram artefatos válidos; por isso verificamos os arquivos após a transação.

O instalador do Wolf Linux DevKit 2.1.3 **não foi alterado** nesta atualização independente do Package Manager.

## Nome correto nas notificações do KDE (0.3.5 Preview 2)

- A aplicação registra explicitamente o nome e o nome de exibição **Wolf Package Manager** no Qt, em vez de herdar `main.py`.
- A propriedade Qt `desktopFileName` aponta para `wolf-package-manager.desktop`, criada por `install-local.sh`, e o ícone global é associado ao aplicativo.
- As mudanças não alteram consultas, instalações, atualizações, Pacman, yay ou a verificação boot/DKMS.
- Para testar no KDE/Wayland, encerre a instância antiga pelo menu da bandeja antes de executar a nova prévia. Uma instância já aberta não é substituída pelo novo comando, por causa do bloqueio de instância única.
- O resultado visual de uma notificação deve ser conferido no Plasma real; a prévia apenas passou pelos testes de código.


**Wolf Package Manager 0.3.6:** inclui Integrações Wolf somente leitura; nenhuma biblioteca é recompilada automaticamente.

### Proteção de integrações (0.3.7 — validada em VM)
A `libfm-qt` Wolf é preservada com `IgnorePkg`, após a sua instalação validada. O gerente bloqueia atualização se essa proteção estiver ausente e oferece plano supervisionado em **Integrações Wolf**. Atualizar os demais pacotes não prova que novos pacotes sejam compatíveis com a ABI antiga; nunca forçar dependências. A verificação via `pacman-conf` e a auditoria permanecem somente leitura.
