# Wolf Linux DevKit 2.0.0-alpha50

## Limpeza do /home — fluxo simplificado
- Substitui seleção individual dos itens ocultos por **uma única caixa de seleção**: remover todas as entradas ocultas imediatas de `/home/USUARIO`.
- A prévia em somente leitura lista os nomes e tamanhos; backup é opcional e vem desligado. Confirmação adicional **LIMPAR** no terminal antes de formatar a raiz.
- Inclui `.local`, `.steam`, `.ssh`, `.gnupg`, perfis de navegadores e arquivos ocultos como `.bashrc`: jogos, chaves e perfis podem ser perdidos. Arquivos e diretórios **visíveis** e o **volume LVM** são preservados.
- Com backup ativado, copia antes de apagar para `/home/.wolf-linux-backups/alpha50-*`; checa espaço e margem de segurança.
- A lista da prévia autorizada fica em manifesto privado (modo 0600), validado novamente imediatamente antes da limpeza; qualquer adição ou remoção de nomes impede a exclusão. Protege symlinks de entrada, submontagens e origem do `/home`.
- O contrato legado de seleção alpha49 permanece apenas para compatibilidade técnica/testes, mas deixa de ser oferecido na GUI.

## Fora do escopo
- Restaurar as telas de **Apagar disco** e **Particionamento manual**: previsto para o refinamento posterior da interface; os controles não foram reativados agora.
- Timeout e recuperação do Flutter: permanecem pendentes.
- Homologação física destrutiva da nova limpeza: **pendente**. Testes automatizados não equivalem à execução real.
