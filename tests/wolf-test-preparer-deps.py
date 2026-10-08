#!/usr/bin/env python3
"""Teste seguro do preflight sem pacman real e sem tocar no ~/wolf-linux."""
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import subprocess

PREPARER = Path(__file__).resolve().parents[1] / 'preparar_ambiente_wolf_linux.sh'


def main() -> None:
    with TemporaryDirectory(prefix='wolf-preflight-') as td:
        root = Path(td)
        proj = root / 'do-not-delete'
        proj.mkdir()
        marker = proj / 'important.txt'
        marker.write_text('preserve', encoding='utf-8')
        mockbin = root / 'mock-bin'
        mockbin.mkdir()
        called = root / 'sudo-invoked'
        sudo = mockbin / 'sudo'
        sudo.write_text('#!/bin/sh\nprintf "yes" > "$WOLF_PREFLIGHT_CALLED"\nexit 39\n', encoding='utf-8')
        sudo.chmod(0o755)
        env = os.environ.copy()
        env.update({'WOLF_RELENG': str(root / 'missing-releng'),
                    'WOLF_PREFLIGHT_CALLED': str(called),
                    'PATH': str(mockbin) + os.pathsep + env['PATH']})
        args = ['bash', str(PREPARER), '--force', '--project', str(proj), '--no-smoke']
        response = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
        assert response.returncode != 0, 'Mock sudo deve bloquear instalação de dependências'
        assert called.is_file(), 'Preparador não tentou instalar dependências antes de testar releng'
        assert marker.read_text() == 'preserve', 'Projeto foi removido antes das dependências'
        called.unlink()
        response = subprocess.run(args + ['--skip-deps'], env=env, capture_output=True, text=True, timeout=15)
        assert response.returncode != 0, '--skip-deps não pode ignorar releng ausente'
        assert 'Retire --skip-deps' in response.stderr, 'Erro de skip-deps pouco claro'
        assert not called.exists(), '--skip-deps não pode chamar sudo'
        assert marker.read_text() == 'preserve', '--skip-deps apagou projeto anterior'
    print('[OK] Preflight: tenta instalar archiso antes de verificar releng; skip-deps seguro; projeto preservado')


if __name__ == '__main__':
    main()
