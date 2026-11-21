# Wolf Linux KDE 2.3.0 — Preview 1 Fix3 (identidade)

## Causa confirmada

A etapa `61-identidade-wolf` criava `/mnt/etc/os-release` com
`PRETTY_NAME="Wolf Linux 2.3 KDE Preview"`, porém exigia em seguida
`PRETTY_NAME="Wolf Linux 2.2"` no mesmo arquivo. Essa divergência
interrompia a instalação obrigatoriamente após `60-sistema-base`.

## Modificações

- A validação da etapa 61 agora corresponde ao conteúdo 2.3 KDE gravado.
- A comparação de `VERSION_ID` continua vinculada a `WOLF_VERSION`.
- O seletor de perfis em modo texto deixa de citar LXQt.
- O smoke test KDE passa a conferir a igualdade entre os valores
  gravados e os campos exigidos por `configure_wolf_identity`.
- O builder executa o smoke test **antes** do `mkarchiso`, de modo que
  o problema seja detectado antes de gerar a ISO.

## Segurança e recuperação

No fluxo GUI, a instalação **não** deve ser reiniciada sobre os
checkpoints e `/mnt` existentes. A proteção de reentrada impede
formatar novamente por engano e também impede continuação automática.

Para homologar com segurança: aplicar o hotfix ao projeto de build do
host, reconstruir a ISO em saída nova, reiniciar a VM com esta ISO
e iniciar uma nova instalação no disco de teste. Isso voltará a
particionar o disco **de teste** quando explicitamente confirmado.
NÃO aplicar em discos com dados a preservar.

A instalação ainda precisa de validação completa e não está homologada.
