"""Regra independente do Qt para a ação de atualização na bandeja."""
from __future__ import annotations
from typing import NamedTuple


class TrayUpgradeState(NamedTuple):
    label: str
    enabled: bool
    tooltip: str


def tray_upgrade_state(count: int, complete: bool, busy: bool) -> TrayUpgradeState:
    """Uma checagem incompleta ou operação ativa nunca libera a transação."""
    if busy:
        return TrayUpgradeState('Atualizar sistema', False,
                                'Há uma operação ou verificação em andamento.')
    if not complete:
        return TrayUpgradeState('Atualizar sistema', False,
                                'Verifique as atualizações; a última consulta não foi concluída.')
    if count <= 0:
        return TrayUpgradeState('Atualizar sistema', False,
                                'Nenhuma atualização disponível na última consulta.')
    return TrayUpgradeState(f'Atualizar sistema ({count})', True,
                            'Atualizar Arch/Chaotic-AUR e AUR após confirmação.')
