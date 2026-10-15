# Wolf Linux DevKit 2.0.0-alpha49

## Interface física simplificada
- Esconde da interface pública os controles históricos de VM/QEMU, modos de instalação que não têm suporte físico e assistente exclusivo de desmontagem de VM. O backend/testes de laboratório são mantidos sem alterações e podem ser exibidos apenas com `WOLF_SHOW_VM_LAB=1`.
- O fluxo visível é reutilização de instalação detectada por UUID, com EFI e /home LVM preservados. **Não amplia** o contrato: requer Live UEFI, dois NVMe, raiz em um SSD, EFI no outro e /home em LV com dois PVs.
- Mensagens de diagnóstico e revisão atualizadas para remover alertas de bloqueio físico históricos.

## Limpeza seletiva do /home preservado
- Botão de prévia real, em `ext4 ro,noload`, apresenta diretórios/arquivos ocultos por tamanho estimado e seleção individual; inclui itens em `.local/share/` sem selecionar automaticamente Steam.
- Nenhum item é marcado por padrão. `Backup` é opcional e desmarcado por padrão; quando solicitado, exige espaço suficiente e copia todos os itens com `cp -a` antes de iniciar as exclusões. Backup gerado em `/home/.wolf-linux-backups/` (raiz do volume preservado, fora das pastas selecionadas).
- Proteção contra `..`, caminhos absolutos, links simbólicos no caminho, submontagens, itens duplicados/sobrepostos e troca de plano após consentimento.
- Plano JSON validado de modo estrito, preflight físico independente, confirmação textual `LIMPAR SELECIONADOS` **antes da formatação da raiz**, aplicação na etapa 22 após verificação da origem do volume.
- **Atenção:** a execução física desta nova opção ainda não foi validada em hardware real. Antes da próxima instalação destrutiva, testar em mídia descartável/ambiente isolado que reproduza o fluxo físico.

## Itens fora do escopo
- Não altera ordem de instalação do Flutter nem introduz timeout nesta revisão. O problema do GitHub/Flutter continuará previsto para uma atualização posterior.
