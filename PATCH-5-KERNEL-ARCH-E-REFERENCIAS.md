# Patch 5 — kernels oficiais do Arch e revisão de referências antigas

Base: Patch 4 (rede LXQt). Este ZIP contém o DevKit, **não uma ISO compilada**.

## Política do Wolf Linux 2.2

- Principal: `linux` + `linux-headers` dos repositórios oficiais do Arch.
- Reserva: `linux-lts` + `linux-lts-headers` dos repositórios oficiais.
- GRUB: linux definido como primeira entrada; LTS presente para contingência.
- NVIDIA moderna: `nvidia-open-dkms`, verificação por kernel antes da conclusão.
- Chaotic-AUR: repositório opcional para pacotes de terceiros; pode ser ignorado quando sem rede/chaves/CDN/mirror. O kernel principal nunca muda por causa disso.
- Desktop: LXQt/Openbox/PCManFM-Qt; gerenciadores de rede e mídia dos Patches 3/4 preservados.

## Correções

1. Removidos do fluxo ativo o instalador de kernel CachyOS, os prompts de LTS provisório, as variáveis relacionadas e o arquivo antigo `cachyos-pending.txt`. Falhas Chaotic são registradas em `chaotic-aur-pending.txt`.
2. Configuração Chaotic independe do kernel; se falhar e optar por 2, preserva `[core]` e `[extra]`, retira apenas `[chaotic-aur]` e continua com fallback AUR quando necessário.
3. Ensaio físico multidisco passou a descrever os estágios reais, inclusive `63a-kernel-arch`, `69c2-lxqt-base`, `69d2-wolf-lxqt`.
4. Removidos os manifestos antigos do CachyOS e do desktop KDE/Plasma (não utilizados). Os aplicativos Kate, Konsole, Gwenview, Okular etc. permanecem.
5. Preferências compartilhadas do LXQt não criam mais `kwinrc`, `kcminputrc` ou autostart Plasma; preferências úteis de MIME, Konsole e Zsh são preservadas.
6. A instalação ativa não instala o helper first-login do Plasma nem configura Baloo. Mensagem da bandeja do Package Manager corrigida para LXQt.
7. Testes novos para política de kernels, Chaotic e compatibilidade das etapas, incluídos no smoke test.
8. README atual resumido e documentação antiga movida para histórico específico.

## Histórico preservado propositalmente

Notas de release antigas e testes específicos de versões 2.1.x e módulos de compatibilidade MATE/XFCE/Plasma não acionados pela instalação LXQt permanecem no projeto. São referência histórica, não evidência da política atual. Identificadores `org.kde.*` continuam válidos para aplicativos KDE usados no LXQt.

## Validação

`./tests/wolf-smoke-test.sh` foi executado sem falhas. **Não houve build ISO, instalação em VM nem validação em hardware real.** Antes de homologar, verificar instalação com Chaotic disponível e sem ele, GRUB com `linux` e `linux-lts` e DKMS NVIDIA nos dois kernels.
