"""Decisões puras de progressão da atualização (testáveis sem Qt)."""

def should_confirm_aur_stage(plan_label: str, stage_index: int, total_stages: int) -> bool:
    """Pedir segunda confirmação somente na etapa oficial de upgrade completo."""
    return plan_label == 'Atualização completa' and stage_index == 0 and total_stages > 1
