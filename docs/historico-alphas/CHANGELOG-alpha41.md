# Alpha41 — Laboratório QEMU multidisco/LVM

- Script de host `tests/wolf-vm-multidisk.sh` cria, executa e inicia a VM
  UEFI com dois discos qcow2 isolados, identificados por seriais únicos.
- Ferramenta guest `wolf-lab41-particionar` reproduz topologia
  ESP em A, raiz e partição NTFS de teste em B, e `/home` em LVM com dois PVs;
  **somente dentro da Live QEMU, após checagens e confirmação explícita**.
- Ferramenta `wolf-lab41-verificar` confere em modo de leitura arquivos de
  preservação em EFI, LV `/home` e partição extra.
- Teste automático do laboratório: impede sobrescrita de imagens e valida
  guardas de virtualização, sem formatar dispositivos reais.
- Alterações limitadas à mídia Live e aos scripts de VM. KDE instalado,
  interface gráfica e bloqueio de execução física permanecem inalterados.
- Executor multidisco continua não executável nesta revisão.
