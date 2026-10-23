# Wolf Linux DevKit 2.1.3-rc1 — kernel CachyOS + recuperação LTS

**Data:** 22 de outubro de 2026. **Tipo:** prévia para validação em VM.
**Base preservada:** versão 2.1.2, incluindo Package Manager 0.3.3,
segurança multidisco/LVM, KDE Plasma/Wayland e proteção existente do Baloo.

## Mudanças

1. `BASE_PACKAGES`: usa `linux-lts` e `linux-lts-headers` provenientes
   dos repositórios oficiais no `pacstrap` inicial. Não inclui linux-zen.
2. `CACHYOS_KERNEL_PACKAGES`: `linux-cachyos` e seus headers. Instalados
   explicitamente via `chaotic-aur/...` após registro e sincronização do Chaotic.
3. Minimal, Basic, Test e Full: Chaotic-AUR + kernel CachyOS são obrigatórios;
   resolver pacotes AUR direto permanece condicional às stacks selecionadas.
4. GRUB UEFI/BIOS: `GRUB_DEFAULT=0`, `GRUB_TOP_LEVEL` para CachyOS,
   menu visível 5 segundos, duas entradas de kernel e dois initramfs
   verificados antes de declarar instalação finalizada.
5. Driver NVIDIA moderno: `nvidia-open-dkms`; teste `modinfo -k` nos dois
   releases instalados antes da etapa final de boot.
6. Suporte gamepad: helper interativo reconhece `*-cachyos` e seleciona
   `linux-cachyos-headers`. Driver `hid-xpadneo` permanece na stack Gaming.
7. Inspeção/ensaio de topologia multidisco: sequência de estágios atualizada.

## Notas e limites

- A versão 7.3.0-2 do kernel CachyOS foi validada no desktop RTX 4060 do
  usuário (NVIDIA 615.78.08). Isto não é homologação para todo hardware.
- O kernel da **mídia Live** continua o do releng oficial do Archiso. Só o
  **sistema instalado** usa linux-cachyos como kernel principal.
- Chaotic-AUR precisa de conexão válida durante a instalação, inclusive Minimal;
  a etapa essencial falha de modo explícito se o kernel não estiver disponível.
- O Baloo mantém o tratamento já existente; a atualização de kernel não
  comprova correção dos crashes do baloo_file_extractor ou do task manager.
- Sem alterações nas políticas de preservação EFI, partições Windows,
  PVs/LVs de /home, backup/dotfiles e prompts de confirmação.
- Este ambiente de preparação não é Arch Linux e não dispõe de `mkarchiso`,
  `pacman` ou permissões de construção da ISO: código atualizado e verificado
  estaticamente, mas **nenhuma ISO foi produzida ou testada em VM aqui**.

## Pré-validação recomendada (após gerar ISO no Arch)

```bash
bash tests/wolf-smoke-test.sh
python3 tests/wolf-test-kernel-2.1.3.py
./tests/wolf-build-iso.sh
./tests/wolf-test-iso.sh uefi "$(find out -maxdepth 1 -name '*.iso' | head -n1)" --fresh
# Rodar também BIOS em disco virtual separado, nunca na instalação física.
```

Durante a instalação na VM, validar que ambas as imagens existam,
`dkms status` indique módulos em ambos os kernels na máquina com NVIDIA,
e GRUB inicie no CachyOS com LTS nas opções avançadas.
