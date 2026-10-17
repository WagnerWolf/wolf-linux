# Wolf Linux DevKit 2.1.2-rc1 — SmokeFix 1

Correção pontual do aviso **ShellCheck SC2016** em `install/wolf-install.sh`, dentro de `prepare_user_cache()`.

A expansão de `$1` e `$p` precisa acontecer no `/bin/sh` iniciado com `runuser` dentro do `arch-chroot`. A instrução `# shellcheck disable=SC2016` documenta a intenção apenas para este comando.

**Nenhuma alteração funcional** na instalação, permissões, LVM, EFI, boot ou perfis. Identificação da distribuição continua `2.1.2-rc1`.

## Aplicação rápida no projeto preparado

Extraia o ZIP **patch** diretamente na raiz do projeto, preservando `install/wolf-install.sh`:

```bash
cd ~/wolf-linux
unzip -o ~/Downloads/wolf-linux-devkit-2.1.2-rc1-smokefix1-patch.zip -d .
bash -n install/wolf-install.sh
shellcheck install/wolf-install.sh
bash tests/wolf-smoke-test.sh
```

Gere a ISO somente depois da aprovação do smoke test no Arch Linux.
