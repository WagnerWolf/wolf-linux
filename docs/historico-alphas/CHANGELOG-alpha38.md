# Wolf Linux 2.0.0-alpha38 — Rescue 0.2 e refinamento GUI

## Wolf Rescue 0.2
- Padronização de Qt Fusion com paleta escura e contraste alto; sem texto claro em fundo branco.
- Área de diagnóstico completo com quebra de linha e ações reorganizadas em grade.
- Nova aba **Mapa de volumes**: lê `etc/fstab` selecionado pelo usuário, consulta `lsblk` em JSON e correlaciona pontos `/`, `/boot/efi`, `/home` por UUID/PARTUUID.
- Reconstrói discos físicos ancestrais e preserva todos os PVs de LVs LVM repetidos sob discos distintos.
- Destaca quando EFI e raiz estão em SSDs distintos, quando um LV depende de diversos PVs ou quando UUID não é encontrado.
- O mapa usa **somente leitura** e não realiza montagem, formatação, reparos ou alteração de entradas UEFI.
- Comentários `# /dev/...` no fstab não são utilizados como fonte de identidade: a correlação usa a coluna de dispositivo do fstab.

## Wolf Installer GUI 1.8
- Janela inicial redimensionada conforme a área útil do monitor.
- Layout com linhas quebradas e tabs que permitem navegação quando a tela é estreita.
- Páginas configuradas sem rolagem horizontal; inventário de discos usa largura elástica.
- Rótulos da tela de boas-vindas encurtados, sem remover ferramentas.
- Motor Bash, confirmações destrutivas e limites de execução **exclusiva em VM** preservados.

## Validação
- Teste específico do mapa com EFI e raiz em discos distintos e LV espalhado em 2 PVs.
- Contrato de inventário recusando UUID ausente/incompatível.
- Smoke test do DevKit e testes de regressão da GUI aprovados.
- Staging simulado repetido, confirmando transporte do novo módulo à Live.
- Ainda requer build real e validação visual em hardware físico.
