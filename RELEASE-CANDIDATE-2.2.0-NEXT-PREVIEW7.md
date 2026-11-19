# Wolf Linux DevKit 2.2.0 — Next Preview 7 (08/11/2026)

## Inclusão: Monitor do Sistema do GNOME no LXQt

- Pacote **gnome-system-monitor** adicionado ao LXQT_PACKAGES do repositório
  oficial `extra`, em todas as instalações LXQt (inclusive Minimal).
- Ordenação padrão da visualização de processos: **Nome** (`sort-col=0`),
  ordem crescente (`sort-order=0`). Números de CPU e memória são atualizados,
  mas não reordenam dinamicamente a lista.
- Padrão implementado via `99-wolf-system-monitor.gschema.override` e compilação
  dos esquemas GLib após instalação; não altera preferências próprias dos usuários.
- O próprio GNOME System Monitor cria entrada no menu de aplicativos, traduzida
  para português se a sessão estiver em pt_BR. Não requer GNOME Shell.
- `btop` continua instalado como ferramenta de terminal.
- Aplicação imediata ao sistema já instalado via `wolf-monitor-sistema-instalar.sh`
  incluído em `tools/lxqt/` e como ZIP separado.

## Compatibilidade e validação

Preservados integralmente: Alt+Tab residente 0.3, Window Keeper 0.2,
Picom VM Guard, libfm-qt custom 2.4.0-4.2, Wolf Package Manager 0.3.7,
formatador USB nativo, links simbólicos e instalações/particionamento.

As alterações de DevKit foram verificadas com teste estático e smoke local;
**a ISO Next Preview 7 ainda não foi gerada nem validada em instalação real**.

## Histórico da Preview 5



Baseline preservada: 2.2.0 + Package Manager 0.3.7 + Picom GLX/VSync, painel duplo,
Alt+Tab por monitor, defaults e correções XDG/GTK/Archiver/NTFS/VS Code/Keyring.

## Inclusão permanente na Next Preview 5: monitor/janelas e Alt+Tab

A sessão LXQt/Openbox/X11 passa a iniciar automaticamente dois componentes:

- **Wolf Alt+Tab 0.3 residente**: serviço único com socket Unix privado e cache
  X11 orientado por eventos, mantendo o seletor visual aprovado e o atalho
  por monitor, sem várias janelas simultâneas. `Super+Tab` continua reserva.
- **Wolf Window Keeper 0.2**: correção da tela cheia e abertura do Thorium,
  Chromium e Chrome no monitor original, disparada por eventos X11, com
  timeout pontual de 35 ms na restauração e trava de instância `flock` por
  DISPLAY. Aguardará eventos XRandR quando o login começar com uma só tela.

O instalador `tools/lxqt/wolf-responsividade-instalar.py` é idempotente, cria
backup verificável, não reconfigura o Openbox do usuário e oferece restauração.
Na instalação do sistema pelo Live, usa `--no-start`, pois o daemon só deve
iniciar na sessão gráfica do usuário. No sistema já instalado, pode ser usado
sem root e inicia os dois componentes; também configura os respectivos
`~/.config/autostart/*.desktop` para próximas sessões.

A restauração de tela cheia e a versão 0.3 do Alt+Tab foram **validadas pelo
usuário no hardware físico**. A nova automação de login e o tratamento de
reconexão de monitores têm testes estáticos, mas não foram homologados em
nova ISO/hardware.

### Atualização do Wolf Linux já instalado (sem reinstalar)

O pacote separado `wolf-lxqt-persistencia-0.4` contém o mesmo instalador e as
fontes homologadas. Execute como usuário normal, sem `sudo`:

```bash
cd ~/Downloads/wolf-lxqt-persistencia-0.4
python3 wolf-responsividade-instalar.py
python3 wolf-responsividade-instalar.py --status
```

Antes, encerre o Keeper experimental se ainda estiver rodando manualmente em
outro terminal. Na próxima sessão LXQt ambos iniciarão automaticamente.
As operações são por usuário e preservam as configurações do Openbox.

## Correção da Preview 4: Picom GLX em máquinas virtuais

A inicialização do Picom passa pelo script `~/.local/bin/wolf-picom-session`
instalado com backup pelo configurador LXQt. A detecção ocorre **no login** via
`systemd-detect-virt --vm`, não durante a criação da ISO. No hardware físico
mantém GLX/VSync; em VMs o Picom fica desligado por padrão, evitando tela preta
por falha de apresentação de quadros. XRender é opt-in
(`WOLF_PICOM_VM_MODE=xrender`). Sessões Wayland não iniciam Picom.

O autostart Wolf antigo (texto exato `Exec=picom`) migra com backup; entradas
personalizadas ou explicitamente desativadas são preservadas. Inclusão de teste
com simulação de VM/físico/Wayland, e de hotfix seguro para uma VM já instalada.
O diagnóstico somente leitura fica em `experimental/picom/diagnosticar-picom-vm.sh`.
Não foi testado diretamente no hipervisor do usuário.

## Correções herdadas da Preview 2

- Corrigido erro recorrente `find_package(MenuCache)` com `lxqt-build-tools 2.5`.
- Adicionado patch do cabeçalho de `getpgid()` sem flags globais do compilador.
- Inclusão de testes de execução da função `prepare()` em ambiente isolado.
- Preview 2 substituída por esta versão; sem mudança da identidade 2.2.0.

## Correção de preparação da ISO nesta Preview 3

- `preparar_ambiente_wolf_linux.sh` deixou de copiar um nome fixo da Preview 1.
- Exige **exatamente uma** nota de release `RELEASE-CANDIDATE-2.2.0-NEXT-PREVIEW*.md` antes de qualquer operação que possa substituir o diretório preparado.
- O documento existente é copiado para o projeto mantendo o nome real, e a regressão é testada com notas presentes, ausentes e duplicadas.
- O pacote local `libfm-qt 2.4.0-4.2` continua obrigatório para gerar ISO; ainda não foi compilada neste ambiente.

## Inclusões

- Pacote libfm-qt **2.4.0-4.2** como requisito obrigatório da ISO, ABI 17.
- `placesview.cpp`: formatador USB Wolf. `filemenu.cpp` e `foldermenu.cpp`:
  três operações nativas de links simbólicos.
- Helper Wolf Symlink Native silencioso em sucesso; erros continuam mostrando diálogos.
- Instalação do helper como usuário no *stage* 69d4, após pacote 4.2 no stage 69d3,
  com backups e remoção de actions Desktop antigas.
- Package Manager 0.3.7 reconhece 4.2 e continua protegendo 4.1 durante transição.
- Builder reprodutível 2.4.0-4.2 integrado e compatibilidade CMake LXQt 2.5,
  sem `--skippgpcheck`; compilações oficiais somente no Arch.
- Wolf Menu Editor Preview 1 incluído como ferramenta **experimental opt-in**,
  ainda não habilitado automaticamente na ISO sem validação no hardware.

## Limitações e proteção

A imagem ISO não foi compilada ou homologada aqui: pacote binário de 4.2 compilado
pelo mantenedor não consta deste ZIP. Sem o pacote o gerador para antes de instalar.
**Não** usar pacote oficial libfm-qt 2.5.x no lugar do 4.2 customizado.
Se o repositório oficial do Arch migrar PCManFM-Qt e libfm-qt para ABI 18,
o instalador deve bloquear em vez de forçar downgrade parcial de ABI.
Portar os patches a 2.5.x será uma migração separada.

## Gerar imagem

```bash
# Na pasta do DevKit extraído:
# Copie o pacote homologado de sua compilação real, NÃO um pacote 4.1.
cp '/CAMINHO/VALIDADO/libfm-qt-2.4.0-4.2-x86_64.pkg.tar.zst' release-packages/
bash tools/wolf-integration-monitor/validar-pacote-usb.sh release-packages/libfm-qt-2.4.0-4.2-x86_64.pkg.tar.zst
bash tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-next-preview5" ./gerar-iso-2.2.0.sh
```

As verificações estáticas não substituem a instalação em VM, validação do boot,
regressão de menus, USB, rede, temas, painel duplo, Alt+Tab e integridade de discos.

## Segurança extra: sincronização e ABI

O gerador confere `extra/libfm-qt` e `extra/pcmanfm-qt`. A instalação Live
sincroniza os metadados oficiais e confere a série 2.4.x/ABI 17 **antes**
de formatar discos. Em erro de rede/chaves, para sem iniciar a formatação.

Como o Arch é rolling release, se a série 2.5/ABI 18 entrar no repositório
normal, não tentar `--nodeps`, `-Rdd`, downgrade parcial ou ignorar a validação.
A integração 2.5 requer portar novamente os patches nativos.

## Wolf Menu Editor Preview 1 (opcional)

O projeto contém `experimental/wolf-menu-editor-preview1/` com autodiagnóstico,
instalação por usuário e reversão. Ele não entra no perfil padrão porque ainda
não foi homologado graficamente no Wolf LXQt físico. Para testar sem root:

```bash
cd experimental/wolf-menu-editor-preview1
python3 wolf-menu-editor.py --self-test
python3 wolf-menu-editor.py --check
bash instalar.sh
```

## Compilação da libfm-qt 4.2 em hardware Arch

Se for necessário reconstruir o pacote, a receita fica em
`experimental/integracoes-wolf/libfm-qt-unificado-0.4/`.
O reconstrutor obtém o módulo oficial `FindMenuCache.cmake` do LXQt 2.4.0,
verifica seu conteúdo, inclui o arquivo como fonte local com SHA-512 no PKGBUILD
e instala uma cópia em `src/libfm-qt-2.4.0/cmake/` na etapa `prepare()`.
Isso evita depender de `CMAKE_TOOLCHAIN_FILE`/variáveis de ambiente, inclusive
após `makepkg -s -C`. Também aplica o patch `wolf-legacy-getpgid.patch`, com
`_DEFAULT_SOURCE` e `<unistd.h>` antes dos includes do C legado.
Assinaturas PGP e checksums continuam obrigatórios.
Seu padrão compila e **não instala**. Para manter a segurança não use
`--skippgpcheck` nem atualize para 2.5.x sem portar os patches.


## Fix de aparência do monitor do sistema (Next Preview 7)
- GNOME System Monitor (GTK4/libadwaita) usa `org.gnome.desktop.interface color-scheme`;
  um padrão `prefer-dark` foi acrescentado ao override GSettings após o ajuste
  de ordenação Nome A-Z. `gtk-theme` e `GTK_THEME` globais NÃO são alterados.
- `tools/lxqt/wolf-monitor-sistema-instalar.sh` atualizado para sistema instalado:
  define preferência escura com backup separado e permite `--restore`.
- Se o portal LXQt fornecer uma preferência divergente, teste
  `ADW_DISABLE_PORTAL=1 gnome-system-monitor` e valide em hardware;
  não há desativação global de portal.
- Ainda não homologado em instalação física a partir da ISO Next Preview 7.
