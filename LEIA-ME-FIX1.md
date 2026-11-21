# Wolf Linux 2.3.0 KDE — Preview 1 Fix1

Correção pontual do erro **Permissão negada** em `tests/wolf-customize-iso-profile.sh` durante `./gerar-iso-2.3.0-rc1.sh`.

## Causa

O arquivo customizador e os três scripts de staging/build foram empacotados com permissões 0644. O preparador executava esses scripts diretamente e parava no primeiro com `EACCES`.

## Alterações

- Os quatro scripts necessários ao build agora estão empacotados com modo **0755**.
- A cadeia `gerar-iso`, `preparar_ambiente`, `customize` e `wolf-build-iso` invoca os scripts auxiliares usando `bash` explicitamente.
- O preparador normaliza o modo dos quatro scripts no novo projeto.
- O teste KDE verifica permissões e a chamada do build.
- Incluído `corrigir-build-interrompido.sh`: repara **somente os quatro scripts** dentro de um projeto que já foi criado e interrompido; não apaga nem substitui o restante do projeto.

## Recuperar o projeto interrompido (recomendado)

Extraia este Fix1 para uma pasta separada e rode:

```bash
cd /caminho/para/wolf-linux-devkit-2.3.0-kde-preview1-fix1
bash corrigir-build-interrompido.sh "$HOME/wolf-linux-2.3.0-rc1"
cd "$HOME/wolf-linux-2.3.0-rc1"
python3 tests/wolf-test-kde-2.3.0-rc1.py .
bash tests/wolf-build-iso.sh
```

O build pode usar `sudo` para o Archiso e limpa o **diretório `work/` do projeto** como já fazia na versão anterior. Não apaga o projeto nem as instalações existentes.

## Alternativa sem baixar nada

```bash
cd "$HOME/wolf-linux-2.3.0-rc1"
chmod +x tests/wolf-customize-iso-profile.sh tests/wolf-stage-live-ssh.sh \
  tests/wolf-stage-live-desktop.sh tests/wolf-build-iso.sh
python3 tests/wolf-test-kde-2.3.0-rc1.py .
./tests/wolf-build-iso.sh
```

Isso resolve a falta de permissões no projeto existente sem alterar a lógica dos scripts originais.

## Estado de validação

`bash -n`, teste estático KDE e inspeção dos bits de execução do ZIP: aprovados. **ISO ainda não construída nem validada em VM ou na RTX 4060.**
