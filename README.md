## Wolf Linux DevKit 2.1.2 — Release

Consulte RELEASE-NOTES-2.1.2.md. Inclui Wolf Package Manager 0.3.3 e correções da RC1 SmokeFix2.

## Novidades da 2.1.2-rc1 (prévia)

- **Basic:** perfil de uso diário entre Minimal e Test: LibreOffice pt-BR, Chrome, áudio/vídeo e Okular/PDF; nenhuma stack Gaming, Development, Android ou Containers.
- O conteúdo pesado GIMP, OBS Studio e Transmission passou da stack Daily para Extras, ainda presente nos perfis Test e Full.
- Janela de ferramentas da Live redesenhada: nomes visíveis e botões com largura fixa.
- `~/.cache` e `~/.cache/wolf-linux`: dono e escrita verificados como usuário real, com correção pontual de diretório criado como root, nunca `chown -R` na home.
- Preservadas as barreiras de particionamento, LVM e EFI homologadas em 2.1.1.

# Wolf Linux DevKit 2.1.1

**Versão estável 2.1.1 — KDE Plasma / Wayland, base Arch Linux.**

O Wolf Linux 2.1 utiliza uma interface gráfica própria na mídia Live para instalar o sistema em máquinas BIOS/Legacy ou UEFI. A interface é o instalador principal: o executor Bash realiza o particionamento e a instalação após revisão do plano e duas confirmações. O terminal de progresso permanece dentro da janela do instalador.

## Modos de instalação

| Opção | Efeito principal |
|---|---|
| **Apagar disco inteiro** | Recria o particionamento do disco escolhido. Todos os dados desse disco são eliminados. Permite ajustar o espaço de `/` e de `/home` separada. |
| **Particionamento manual** | Usa as partições preparadas pelo usuário, com atalho para GParted e atualização do inventário de discos. Cada partição recebe função e política de formatação explícitas. |
| **Reutilizar partições** | Formata a partição raiz e preserva a EFI e `/home` separada de acordo com o plano. Pode eliminar dotfiles da pasta pessoal após apresentar a prévia. |

Antes de confirmar, confira com atenção **qual disco e quais partições serão alterados**. Para uma nova instalação com informações importantes, realize backup externo. As três modalidades foram testadas pelo mantenedor com sucesso; isso não garante compatibilidade com todas as topologias de armazenamento. A interface padrão dá suporte aos cenários simples; RAID, criptografia e certas configurações LVM/multidisco requerem procedimento especializado e não devem ser improvisadas.

## Primeiros passos — gerar ISO

No Arch Linux, extraia o DevKit e abra o diretório:

```bash
cd wolf-linux-devkit-2.1.1
./preparar_ambiente_wolf_linux.sh
```

O preparador instala/verifica ferramentas do Archiso, gera o perfil e executa verificações. Se o projeto já estiver preparado, é possível executar os testes e o build diretamente:

```bash
bash tests/wolf-smoke-test.sh
bash tests/wolf-build-iso.sh
```

A ISO será gravada em `out/` (o nome concreto depende da data e do Archiso). Os arquivos de trabalho `work/`, `out/`, `iso-profile/` e `vm/` são gerados no ambiente de build e não fazem parte do código-fonte do DevKit.

## Instalação

1. Inicie o computador pela mídia Live Wolf Linux.
2. Escolha e teste o layout do teclado. O padrão inicial é **Português brasileiro ABNT2**.
3. Selecione **uma** modalidade de instalação. Nenhuma modalidade vem escolhida.
4. Defina usuário, nome do computador e perfil (**Minimal, Test ou Full**). A escolha do perfil é obrigatória.
5. Confira a lista de operações, os avisos de espaço e os dispositivos de destino.
6. Confirme as operações nos dois diálogos e acompanhe o terminal integrado.
7. Reinicie quando a instalação terminar e verifique o sistema instalado.

### Espaço da partição raiz `/`

O instalador indica referências de capacidade: **Minimal 25–35 GiB**, **Test 40–60 GiB** e **Full 75–110 GiB**. Esses números são **estimativas, não exigências garantidas**: instalações e atualizações podem consumir mais espaço. O perfil Full contém ferramentas de desenvolvimento, jogos e Android/Flutter; reserve espaço adicional conforme o uso.

### Drivers gráficos

O instalador seleciona os provedores Vulkan de acordo com a GPU detectada (Intel, AMD, NVIDIA compatível ou GPU virtual) antes de instalar aplicações opcionais que exigem `vulkan-driver`. A detecção não elimina a necessidade de conferir compatibilidade da placa e firmware.

### Falhas de ferramentas opcionais

Flutter e alguns pacotes de terceiros podem falhar por conexão, indisponibilidade ou armazenamento. O instalador permite tentar novamente ou pular etapas opcionais, registrando pendências em `/var/log/wolf-optional-failures.log` no sistema instalado. Erros nas etapas essenciais **não** são ignorados.

## Sistema instalado

- Desktop principal: KDE Plasma / Wayland.
- Áudio: PipeWire.
- Gerenciador de inicialização: GRUB (BIOS/UEFI conforme o computador).
- Repositórios: Arch oficial → Chaotic-AUR → AUR direto somente quando necessário.
- Gerenciador gráfico: Wolf Package Manager 0.3.3 (repositórios + yay/AUR; bandeja KDE, checagem de atualizações a cada 2 horas ajustável).
- Utilitários: Wolf Control Center, comandos `wolf-helper`, Wolf Rescue na mídia Live.
- Versão: arquivo `VERSION` no DevKit e identificação `Wolf Linux 2.1` no sistema instalado.

## Manutenção e diagnóstico

```bash
# Versão do DevKit
cat VERSION

# Verificação de integridade do código
bash tests/wolf-smoke-test.sh

# Inspeção de boot UEFI a partir da Live
sudo wolf-boot-diagnose
```

A identidade dos discos é conferida novamente pelo executor antes das alterações. Evite interromper o instalador ou reiniciar enquanto houver operações em andamento.

## Histórico de desenvolvimento

A sequência alpha10–alpha59 e os documentos de testes históricos permanecem preservados em `docs/historico-alphas/`. A prévia 2.1.0-rc1 está arquivada em `docs/historico-releases/`. Essas anotações **não descrevem o comportamento atual de todas as funções**. Para a versão final, consulte este README e `RELEASE-NOTES-2.1.0.md` (e notas estáveis 2.0.0 para referência).

### Terminal integrado e configuração do Baloo

Barras de progresso do pacman e do pacstrap que usam `\r` agora redesenham a última linha em vez de acumular texto embaralhado. Esta revisão não modifica o executor Bash, as operações de armazenamento, o GRUB ou o conteúdo da atualização.

### Baloo no KDE Plasma / Wayland

A instalação configura `/etc/systemd/user/kde-baloo.service.d/override.conf`
com `Environment=QT_QPA_PLATFORM=offscreen`. O ajuste aplica-se **somente**
ao indexador de arquivos e extratores lançados pelo serviço Baloo, não à sessão
Plasma ou a outros aplicativos Qt. No hardware de referência, esse ajuste
interrompeu crashes repetidos do `baloo_file_extractor` após reinicialização
e permitiu a indexação continuar.

A configuração não apaga índices nem desativa a indexação. Para verificá-la:

```bash
systemctl --user show -p Environment kde-baloo.service
balooctl6 status
```

### Escopo da 2.1.1

A 2.1.1 mantém as rotinas de particionamento, LVM, EFI, GRUB e perfis da
2.1.1-rc2. O upgrade do Package Manager 0.3.2 corrige detecção de atualizações
concorrentes. A validação da nova ISO depende de sua geração em ambiente Arch
com `archiso` e teste real de boot.
