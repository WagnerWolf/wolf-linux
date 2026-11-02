# Wolf Linux 2.2.0 — FirstBootFix1 (revisão pós-instalação física)

Base: `wolf-linux-devkit-2.2.0-lxqt-release-janelas-keyring-smokefix2.zip`.
Identificação do sistema continua 2.2.0. Não promove mudanças ainda não testadas em hardware à condição de homologadas.

## Problemas relatados

1. **Editor XRandR:** a rotina de montagem dos botões referia-se à variável `native`, removida do editor. Eliminada apenas a referência inválida; rollback e confirmação XRandR mantidos.
2. **Painel secundário:** o restaurador de layout e o configurador de painéis utilizavam o mesmo `~/.config/autostart/wolf-lxqt-monitors.desktop`. A restauração passa a usar `wolf-lxqt-layout-restore.desktop`; o autostart de painéis fica com nome próprio. A detecção no login agora admite uma janela curta de espera, sem watcher permanente. Painel é encerrado antes de editar `panel.conf` para não sobrescrever o novo conteúdo ao sair; relançado depois. Ao confirmar uma mudança no editor, os painéis são sincronizados com o XRandR.
3. **Mouse:** regra Xorg/libinput para `AccelProfile flat`, excluindo touchpads, além de um ajuste pontual na inicialização da sessão LXQt/X11. Requer `xorg-xinput` para aplicação dinâmica e gera configuração Xorg independente.
4. **Pastas XDG em português:** em uma instalação limpa, o configurador inicial cria o arquivo `user-dirs.dirs` em pt_BR **antes** da chamada `xdg-user-dirs-update` e dos favoritos do PCManFM-Qt. Nomes: Área de Trabalho, Documentos, Downloads, Imagens, Músicas e Vídeos (além de Modelos e Público). Se já existir configuração XDG em `/home` reutilizada, ela é preservada. Para instalações existentes, `wolf-user-dirs-ptbr` exibe um plano; `wolf-user-dirs-ptbr --migrate` aplica alterações com backup, sem mesclar diretórios nem seguir symlinks e sem sobrescrever caminhos personalizados. Entradas conflitantes são preservadas para revisão manual.

## Testar no Wolf Linux já instalado

A partir da pasta raiz do DevKit extraído:

```sh
bash corrigir-lxqt-instalado-2.2.0.sh --check
bash corrigir-lxqt-instalado-2.2.0.sh --apply
wolf-user-dirs-ptbr
# Se o plano estiver correto e desejar migrar os nomes reais:
wolf-user-dirs-ptbr --migrate
```

Depois, encerrar e iniciar novamente a sessão LXQt. O `--apply` salva os arquivos substituídos em `~/wolf-backups/lxqt-firstboot-fix/<data>`. Ele não reconfigura o disco, GRUB, kernels ou qualquer outro desktop. O `wolf-user-dirs-ptbr --migrate` possui backup próprio em `~/wolf-backups/xdg-ptbr/` e preserva arquivos existentes. Se `xinput` não estiver instalado na máquina atual, a regra Xorg será aplicada no próximo login após reiniciar o servidor X; para forçar a propriedade na sessão, instalar `xorg-xinput` pelo gerenciador de pacotes.

Verificações úteis:

```sh
xrandr --listmonitors
wolf-lxqt-monitors
wolf-control-center --monitors
cat ~/.config/user-dirs.dirs
xinput list --name-only  # se xorg-xinput estiver instalado
```

Atenção: `wolf-lxqt-monitors` reinicia apenas o painel caso precise atualizar o arquivo de configuração, portanto o menu pode piscar durante a atualização. O monitor primário continua com a bandeja, o secundário com o painel simplificado.

## Gerar ISO

```sh
./tests/wolf-smoke-test.sh
WOLF_BUILD_PROJECT="$HOME/wolf-linux-2.2.0-firstbootfix1" ./gerar-iso-2.2.0.sh
```

A ISO e o comportamento gráfico real desta revisão ainda precisam ser validados. Testes executados: sintaxe Bash/Python, smoke estático, regressões de painel/XDG/monitores, 6 regressões multidisco/LVM.
