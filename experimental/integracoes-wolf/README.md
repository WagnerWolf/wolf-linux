# Integrações Wolf · Preview 1

A base Wolf Linux **2.2.0 não é modificada automaticamente**. Esta prévia altera apenas o **Wolf Package Manager** (se você escolher instalá-lo localmente) e disponibiliza um hook **opcional** de auditoria. Nenhuma biblioteca é recompilada, substituída ou atualizada.

## O que está implementado

- Aba **Integrações Wolf** no Package Manager `0.3.6-integ-preview1`, com verificações em thread separada.
- CLI `tools/package-manager/wolf-integrations-check.py` (somente leitura, sem dependência de PySide6).
- Auditoria da presença do formatador Wolf, Wolf Control Center e extensão experimental do menu USB.
- A extensão do `libfm-qt` **ainda não foi construída**. O estado inicial será **Pendente**; isso é correto.
- Reconhecimento conservador de manifesto *futuro* instalado junto com `libfm-qt`: só considera validada quando versão exata, marca explícita de build validada e propriedade do manifesto pelo pacote coincidem, **e não existe aviso de transação ALPM pendente**.
- Hook do Pacman **opcional** para registrar instalação, atualização ou remoção de `libfm-qt` sem operar dentro do gerenciador de pacotes.

## Como testar a seção no sistema atual

Abra terminal na pasta `wolf-linux-devkit-2.2.0` extraída:

```sh
python3 tools/package-manager/wolf-integrations-check.py
cd tools/package-manager
python3 main.py
```

Na janela, clique em **Integrações Wolf → Verificar integrações**. Isso inicia o gerenciador pela pasta de testes e não substitui sua instalação atual. Não execute simultaneamente duas instâncias de gerenciamento ativo; feche sua instância antiga para conferir o tray, se necessário.

Para optar por atualizar o gerenciador instalado apenas no seu usuário:

```sh
cd tools/package-manager
bash install-local.sh
```

Esse instalador existente pode atualizar seus atalhos/autostart pessoais e não altera pacotes do Pacman.

## Hook opcional de monitoramento

```sh
bash experimental/integracoes-wolf/instalar-monitor-hook.sh --check
bash experimental/integracoes-wolf/instalar-monitor-hook.sh --install
```

O hook executa **apenas** `/usr/bin/python3 /usr/local/lib/wolf-linux/integrations/wolf_integration_hook.py`, que grava `/var/lib/wolf-linux/integrations/libfm-qt.changed` quando o ALPM altera `libfm-qt`. Não usa `makepkg`, `pacman -S`, acesso à rede, serviços de monitoramento nem reinicia processos. A verificação da aba não apaga esse registro. Para remover o hook:

```sh
bash experimental/integracoes-wolf/instalar-monitor-hook.sh --remove
```

## Próxima etapa (não entregue neste preview)

Obter o código-fonte **exato** da versão `libfm-qt` instalada, implementar o menu de dispositivos de `PlacesView`, gerar e testar um pacote Pacman experimental, com marcação de versão/ABI/build e mecanismo de rollback. Só depois dessa validação, distribuir via Wolf Package Manager com checagem de compatibilidade. Não bloquear as atualizações oficiais indefinidamente. O formatador atual permanece como alternativa até homologação da extensão.

**Segurança:** um manifesto declarado pelo pacote e uma consulta de versão são sinais de validação, não garantem compatibilidade binária ou ausência de bugs. A etapa experimental deverá usar testes funcionais e um repositório Wolf assinado antes da distribuição automática.
