# Wolf Linux DevKit 2.1.3 — lançamento estável (23/10/2026)

**Base promovida:** `2.1.3-rc5`, após confirmação do mantenedor de que a instalação da ISO foi concluída e validada. Esta promoção não altera os procedimentos de particionamento, EFI, LVM, layout KDE/Wayland ou a lógica de instalação aprovada na RC5.

## Destaques

- `linux-cachyos` do Chaotic-AUR preferencial para o sistema instalado; `linux-lts` oficial permanece instalado como alternativa confiável. `linux-zen` deixa de ser provisionado em novas instalações.
- `nvidia-open-dkms` e headers para os kernels efetivamente instalados; controle DKMS do driver NVIDIA e `hid-xpadneo` quando aplicável.
- GRUB dá prioridade ao CachyOS se presente e utiliza o LTS caso não esteja; sem selecionar uma imagem de kernel inexistente. O Windows/UEFI continua detectável conforme o hardware e a configuração de boot.
- Falhas de chave, bootstrap, sincronização ou download do Chaotic-AUR permitem repetir ou continuar com o LTS; pendências ficam registradas, sem desabilitar verificação de assinaturas.
- Powerlevel10k ausente não é fatal. `.zshrc` carrega o tema somente se disponível e oferece prompt simples, mantendo os plugins instalados; fontes em `assets` e `branding-assets` sincronizadas.
- Wolf Package Manager **0.3.4**, com opção **Atualizar sistema (N)** no menu da bandeja KDE (após verificação completa, quando houver atualizações), reutilizando confirmação e o fluxo de atualização existente.
- Mantidas as modalidades Apagar/Manual/Reutilizar, os perfis Minimal/Basic/Test/Full, a limpeza opcional de dotfiles e as proteções EFI/multidisco/LVM, além do tratamento atual do Baloo.

## Validação e limites

- A instalação da imagem RC5 foi validada pelo mantenedor e autorizada para promoção.
- Smoke test completo do **código-fonte da 2.1.3 estável** passou com código de saída 0 em 23/10/2026. Este ambiente executou as verificações Bash/Python; o ShellCheck estava indisponível aqui.
- A promoção estável consiste em identificação, documentação e empacotamento da mesma base; o DevKit contém **fontes e scripts**, não uma ISO pré-compilada.
- Um `smoke test` estático não equivale a validação de todos os tipos de hardware. Testes de instalação em hardware adicional, BIOS, UEFI e fallback de repositório continuam recomendados.
- A ISO Live utiliza o kernel padrão do perfil Archiso; `linux-cachyos` + `linux-lts` são instalados no **sistema de destino**.

## Compilação no Arch Linux

```bash
cd wolf-linux-devkit-2.1.3
./gerar-iso-2.1.3.sh
```

O diretório padrão de build é `~/wolf-linux-2.1.3` e a saída fica em `~/wolf-linux-2.1.3/out/`; a rotina não apaga automaticamente projetos de builds anteriores.

Histórico das prévias: `RELEASE-NOTES-2.1.3-rc1.md` até `RELEASE-NOTES-2.1.3-rc5.md`.

## Reempacotamento de smoke test (23/10/2026)

Corrigida a validação de identidade em `tests/wolf-test-stable-2.1.3.py` para considerar os layouts distintos do pacote DevKit e do projeto de construção gerado pelo preparador. A versão do sistema instalado permanece `2.1.3`, sem mudanças funcionais no instalador.
