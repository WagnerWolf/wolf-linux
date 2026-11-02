"""Planejamento seguro de upgrades da libfm-qt Wolf; apenas consultas."""
from dataclasses import dataclass
from pathlib import Path
import subprocess

WOLF_VERSION = '2.4.0-4.1'

@dataclass(frozen=True)
class Protection:
    installed: str | None
    wolf_active: bool
    protected: bool
    available: str | None
    failure: str = ''

    @property
    def safe_for_system_update(self):
        # Fail closed, caso a biblioteca Wolf esteja ativa e sem proteção.
        return not self.failure and (not self.wolf_active or self.protected)


def _run(args):
    try:
        return subprocess.run(args, text=True, capture_output=True, check=False, timeout=12)
    except (OSError, subprocess.TimeoutExpired):
        return None


def probe():
    local = _run(['pacman', '-Q', 'libfm-qt'])
    if local is None or local.returncode != 0:
        return Protection(None, False, False, None, 'Não foi possível consultar libfm-qt.')
    tokens = local.stdout.strip().split()
    if len(tokens) != 2 or tokens[0] != 'libfm-qt':
        return Protection(None, False, False, None, 'Versão local desconhecida.')
    installed = tokens[1]
    # Revisões futuras devem ter manifesto do pacote, não inferir de nomes arbitrários.
    active = installed == WOLF_VERSION
    if not active:
        return Protection(installed, False, False, None)
    protection = _run(['pacman-conf', 'IgnorePkg'])
    if protection is None or protection.returncode != 0:
        return Protection(installed, True, False, None, 'Não foi possível ler IgnorePkg do Pacman.')
    protected = 'libfm-qt' in protection.stdout.split()
    repo = _run(['pacman', '-Si', 'libfm-qt'])
    available = None
    if repo is not None and repo.returncode == 0:
        for line in repo.stdout.splitlines():
            # Pacman pt-BR e en-US; informar a versão apenas se identificada.
            if ':' in line and line.split(':', 1)[0].strip() in ('Version', 'Versão'):
                available = line.split(':', 1)[1].strip() or None
                break
    return Protection(installed, True, protected, available)


def newer_repo_available(state: Protection) -> bool:
    if not state.wolf_active or not state.available or not state.installed:
        return False
    r = _run(['vercmp', state.available, state.installed])
    if r is None or r.returncode != 0:
        return False
    return r.stdout.strip() == '1'


def describe(result: Protection) -> str:
    if not result.wolf_active:
        return 'Biblioteca Wolf personalizada não detectada.'
    title = ('Protegida contra atualização geral' if result.protected
             else 'ALERTA: sem proteção IgnorePkg!')
    return (f'{title}\nlibfm-qt Wolf instalada: {result.installed}\n'
            f'Versão nos repositórios: {result.available or "não verificada"}\n'
            'A integração de formatação USB exige adaptação do patch e testes antes '
            'de trocar a biblioteca. O bloqueio pode impedir upgrades que dependam '
            'de uma nova ABI. Não force atualizações parciais.\n'
            + (result.failure or ''))
