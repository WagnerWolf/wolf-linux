# Wolf Linux DevKit 2.0.0

**Versão final 2.0.0 — KDE Plasma / Wayland, base Arch Linux.**

O Wolf Linux 2.0 utiliza uma interface gráfica própria na mídia Live para instalar o sistema em máquinas BIOS/Legacy ou UEFI. A interface é o instalador principal: o executor Bash realiza o particionamento e a instalação após revisão do plano e duas confirmações. O terminal de progresso permanece dentro da janela do instalador.

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
cd wolf-linux-devkit-2.0.0
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
- Utilitários: Wolf Control Center, comandos `wolf-helper`, Wolf Rescue na mídia Live.
- Versão: arquivo `VERSION` no DevKit e identificação `Wolf Linux 2.0` no sistema instalado.

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

A sequência alpha10–alpha59 e os documentos de testes históricos permanecem preservados em `docs/historico-alphas/`. Essas anotações **não descrevem o comportamento atual de todas as funções**. Para a versão final, consulte este README e `RELEASE-NOTES-2.0.0.md`.
