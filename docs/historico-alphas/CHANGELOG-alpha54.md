# Wolf Linux DevKit 2.0.0-alpha54

## Correção para homologação em VM

- A GUI alpha53 chamava `wolf_plan.vm_execution_fields(..., check_device=True)` sob usuário Live. No modo **Apagar disco**, isso executa `wipefs --no-act` sem acesso ao dispositivo e termina com `permission denied`.
- Agora a GUI faz uma validação inicial sem abrir o bloco e delega a pré-validação **somente leitura** à entrada existente `sudo -n wolf-install --preflight-gui-plan-vm` com plano temporário 0600 em pasta privada, removida automaticamente. O Bash roda as verificações de assinaturas e dispositivos com privilégios; não particiona, não monta e não formata nesta etapa. Antes da instalação o executor confere tudo novamente.
- Mensagens claras quando sudo/preflight recusa.
- GUI: barra lateral mais larga, apenas rolagem vertical, rótulos transparentes em cartões para eliminar tarjas escuras, menos compressão dos campos. Textos Manual/Reutilizar explicam os limites reais do executor VM de disco único, sem prometer LVM nessa fase.
- Nenhuma alteração no executor de formatação e no fluxo físico homologado. Três modalidades e confirmações são mantidas.

## Verificações

`python3 tests/wolf-test-alpha54.py` testa o comando permitido de preflight, arquivo 0600 em pasta privada, bloqueio fora da Live e erros de pré-validação. Rodar `bash tests/wolf-test-live-desktop.sh` e `bash tests/wolf-smoke-test.sh` na máquina de preparação. A abertura real Qt, geração da ISO e instalação de cada modo seguem pendentes de validação em VM.
- A rolagem por roda do mouse também funciona na barra lateral sem modificar seleções por acidente.
