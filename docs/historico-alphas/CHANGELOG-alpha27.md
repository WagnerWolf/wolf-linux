# Wolf Linux 2.0.0-alpha27 — corretivo da execução experimental em VM

- Corrigido o parâmetro inválido `wipefs --no-headings` para a opção real do util-linux, `--noheadings` (somente leitura com `--no-act`). A alpha26 recusava inclusive discos VirtIO completamente vazios por erro de sintaxe do comando.
- Diagnósticos separados: assinatura realmente encontrada, erro técnico do wipefs e indisponibilidade/timeout. O backend continua recusando discos com partições, assinaturas, arquivos montados ou identidade alterada.
- Confirmação de apagamento da GUI 0.7 reforçada com janela modal independente e necessidade de digitar `APAGAR /dev/vdX` para abrir o terminal. A confirmação separada no Bash permanece obrigatória.
- Testes sem escrita em discos: saída vazia válida, assinatura GPT recusada, falha da ferramenta recusada, ferramenta indisponível recusada, teste sobre arquivo temporário limpo, e verificações estáticas da janela visual.
- A alpha18 estável e a alpha25 planejadora são preservadas. Instalação real continua experimental e restrita a VM QEMU/KVM com disco VirtIO descartável.

**Não executamos uma instalação real nem validamos uma sessão Qt nesta máquina de desenvolvimento.**
