> HISTÓRICO DA PRÉVIA: configuração homologada e integrada à release 2.2.0. Veja `RELEASE-2.2.0-PICOM-GLX.md` na raiz do DevKit.

# Wolf Linux 2.2.0 – Preview de composição Picom

Esta prévia NÃO altera o Openbox, as regras Alt+Tab, as configurações do Chrome, os kernels ou a biblioteca `libfm-qt` customizada.

## Motivação

Com Picom GLX/VSync, as notificações da Steam passaram a renderizar corretamente, mas os painéis ficaram transparentes. O arquivo Wolf-dark (`lxqt-panel.qss`) não definia um fundo para `LXQtPanel #BackgroundWidget`. A prévia corrige o tema e prepara um perfil Picom conservador.

## Procedimento no sistema instalado

A partir da raiz do DevKit:

```bash
python3 experimental/picom/wolf-picom-lxqt.py --check
python3 experimental/picom/wolf-picom-lxqt.py --apply
```

Encerre a sessão LXQt e entre novamente para carregar o tema atualizado. Sem Picom em execução, teste temporariamente:

```bash
picom --config "$HOME/.config/picom/picom.conf"
```

O comando fica em primeiro plano; Ctrl+C encerra o teste. Confirme painel principal, secundário, notificações Steam, Alt+Tab e reprodução de vídeo. Se estiver visualmente correto, habilite o Picom **somente no próximo login**:

```bash
python3 experimental/picom/wolf-picom-lxqt.py --enable
```

Faça logout/login, confira `pgrep -a -u "$(id -u)" -x picom` e revise os efeitos. Para desativar autostart sem desligar um processo em execução:

```bash
python3 experimental/picom/wolf-picom-lxqt.py --disable
```

Para desfazer a última operação (backup da operação mais recente):

```bash
python3 experimental/picom/wolf-picom-lxqt.py --undo
```

Repita `--undo` para retroceder operações anteriores, uma de cada vez, quando os arquivos não tiverem sido alterados por terceiros. Backups em `~/wolf-backups/picom-lxqt/`.

A alteração do tema nesta prévia é experimental. Se o Control Center do sistema **já instalado** reaplicar uma versão antiga do Wolf-dark, o QSS pode voltar a perder o fundo. O DevKit desta prévia atualiza a fonte do tema para futuras instalações, mas não sobrescreve automaticamente o instalador global já presente na máquina.

## Alterações de configuração

- `picom` é incluído na stack LXQt do DevKit, mas não será iniciado automaticamente até a homologação gráfica.
- O configurador de primeira inicialização prepara `~/.config/picom/picom.conf` quando ainda não existe; não sobrescreve um arquivo pessoal existente.
- GLX + VSync, sem fades, sombras, blur ou transparência de janelas inativas. Não ativa redirecionamento automático de fullscreen.
- Fundo `#242a34` aplicado explicitamente ao `LXQtPanel #BackgroundWidget` do tema Wolf-dark.

## Limitações e validação

A reprodução de microtravamentos raros no Chrome ainda não foi demonstrada, com ou sem Picom. Não atribuir melhoria de performance sem comparações reproduzíveis. Somente a notificação da Steam foi validada visualmente com compositor no sistema físico. A aparência corrigida precisa de validação do usuário antes da promoção a release.
