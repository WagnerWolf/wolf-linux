# Wolf Linux DevKit 2.1.1 — correção do smoke test (2026-10-16)

O pacote original 2.1.1 podia falhar no teste `tests/wolf-test-control-center.py`
com `AssertionError` ao verificar `Autostart ainda não configurado` em uma máquina
que já possuía `/etc/xdg/autostart/wolf-package-manager.desktop`.

O teste era dependente do host. A correção move o caminho do autostart global
para uma constante do backend (que mantém `/etc/xdg/autostart` em produção)
e substitui a constante por um diretório temporário somente durante o teste.
Foram incluídos testes para autostart global, ausência de autostart e override
local de desativação. Não desabilite o autostart real para fazer o teste passar.

## Para um projeto já preparado

Extraia `wolf-linux-devkit-2.1.1-smokefix1-patch.zip` sobre a raiz
de `/home/wolf/wolf-linux`, de forma a substituir:

- `tools/control-center/backend.py`
- `tests/wolf-test-control-center.py`

Execute `bash tests/wolf-smoke-test.sh` a partir do projeto.
O patch não altera o sistema instalado nem os arquivos de geração da ISO.

## Para preparação limpa

Utilize o pacote completo `wolf-linux-devkit-2.1.1-smokefix1.zip`
com o preparador habitual e só compile a ISO após o smoke retornar 0.

O número da versão instalada permanece 2.1.1; `smokefix1` identifica
somente a revisão do pacote DevKit.
