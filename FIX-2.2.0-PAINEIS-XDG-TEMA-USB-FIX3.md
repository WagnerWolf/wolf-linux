# Wolf Linux 2.2.0 — Fix3 experimental para validação física

Este pacote mantém 2.2.0; não é uma nova release homologada. A versão de instalação física anterior foi validada, mas as alterações abaixo ainda não passaram em hardware real.

## Correções e limitações

- Painéis: botão **Aplicar painéis aos monitores** agora força a regravação e a tentativa de reinício do `lxqt-panel`, mesmo quando o arquivo já parece correto. O botão **Diagnóstico detalhado** mostra XRandR, Qt e configurações para investigar falhas reais. Não há garantia de que isso resolva todas as divergências de mapeamento de telas.
- Pastas XDG: união recursiva de subpastas homônimas sem sobrescrever arquivos. Com conflitos remanescentes, o comando sai com status 2 e mantém o diretório XDG apontando para a pasta que ainda contém arquivos.
- Aparência: botão **Reaplicar Wolf-dark (LXQt + GTK)**. Blueman é GTK e requer Breeze-Dark + reinício da aplicação; escolher Wolf-dark somente em configurações LXQt não basta.
- Formatação: utilitário **Formatar unidade USB (Wolf Linux)** com interface própria, exFAT/FAT32/ext4 e confirmação dupla, também no menu de contexto de raiz de unidade USB montada no PCManFM-Qt. Formata apenas partições USB, não discos inteiros. A confirmação e a autorização de UDisks2 são obrigatórias. **Nunca testar com dispositivo que contenha dados importantes.** A rotina foi testada apenas com chamadas simuladas e ainda não foi validada com USB real.
- GNOME Disks permanece disponível com o nome original para operações avançadas. O antigo atalho “Discos e mídias (Wolf)” foi retirado.
- Udiskie: preferir idioma `pt_BR:pt` no autostart. O resultado depende de o pacote conter a tradução: a alteração NÃO fabrica uma tradução ausente.

## Testar no sistema atual

```bash
bash atualizar-paineis-pastas-control-center.sh --check
bash atualizar-paineis-pastas-control-center.sh --apply
```

Feche e reabra o Control Center. Antes de aplicar painéis, use **Diagnóstico detalhado das telas e painéis** e guarde a saída. Após aplicar, execute novamente o diagnóstico para comparação. Aplique a migração de diretórios pelo botão da página Sistema e o tema pela página Aparência e atalhos. Reinicie Blueman e a sessão LXQt para validar os temas e o udiskie.

Formatador: abra **Formatar unidade USB (Wolf Linux)** no menu de aplicativos para ver a lista sem iniciar formatação. O menu de contexto do PCManFM-Qt se aplica à raiz de unidades já montadas, **não necessariamente ao ícone do dispositivo na barra lateral**. A formatação real é destrutiva; testar apenas com pendrive descartável.

## Diagnóstico do painel, se continuar ausente

```bash
wolf-lxqt-monitors --diagnose
xrandr --listmonitors
```

As rotinas de particionamento, GRUB, kernels Arch/LTS e NVIDIA não foram modificadas neste patch.
