# Wolf Linux DevKit 2.1.2-rc1 — SmokeFix 2

## Problema corrigido

Em perfis nos quais a stack `extras` não está selecionada (por exemplo, Basic), `collect_selected_stack_packages` terminava retornando 1. O Bash com `set -Eeuo pipefail` propagava o `ERR trap` herdado para a substituição de processo, e as linhas do relatório "FALHA NA INSTALAÇÃO" eram lidas como nomes de pacotes. Isso provocava falsos alvos no `yay`, consultas inválidas e prompts repetidos. A correção vale para todas as variantes de perfis.

## Como atualizar o projeto ainda não instalado

```bash
cd ~/wolf-linux
unzip -o ~/Downloads/wolf-linux-devkit-2.1.2-rc1-smokefix2-patch.zip -d .
python3 tests/wolf-test-aur-stdout-2.1.2.py
bash tests/wolf-smoke-test.sh
bash tests/wolf-build-iso.sh
```

Não é um patch para aplicar à ISO já gerada; exige recompilar a mídia. Não retome uma instalação que já tentou consultar mensagens de erro como pacotes. Comece uma instalação limpa na VM.

## Escopo

Código da etapa de resolução AUR e teste de regressão; não altera partições, LVM/EFI, GRUB, configuração de hardware, seleção do perfil Basic ou pacote Wolf Package Manager.
