#!/usr/bin/env python3
"""Regressão independente do Qt para a obrigatoriedade do perfil."""
from pathlib import Path
import ast
root = Path(__file__).resolve().parent.parent
src = (root / 'live-gui/preview/app.py').read_text()
qt = (root / 'tests/wolf_test_alpha52_ui.py').read_text()
ast.parse(src)
ast.parse(qt)
assert "self.preset_combo.addItem('Escolha Minimal, Test ou Full...', None)" in src
assert 'self.preset_combo.currentData() is None' in src
assert "self.assertFalse(w.continue_button.isEnabled())" in qt
assert "w.preset_combo.setCurrentIndex(w.preset_combo.findData('minimal'))" in qt
assert 'def test_profile_required_before_review' in qt
print('[OK] alpha57: teste Qt atualizado para exigir seleção explícita do perfil')
