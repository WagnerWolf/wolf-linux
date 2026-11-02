#!/usr/bin/env python3
"""Wolf Linux XRandR layout editor backend.

Monitor changes only upon explicit Apply; a separate rollback process protects
against lost display / GUI crashes. No privileged commands and no watcher.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

NAME_RE = re.compile(r'^[A-Za-z0-9_.:-]{1,128}$')
MODE_RE = re.compile(r'^(\d{2,5})x(\d{2,5})$')
HEADER_RE = re.compile(r'^([^\s]+) (connected|disconnected)(?: (.*))?$')
GEO_RE = re.compile(r'(?<!\d)(\d{2,5})x(\d{2,5})([+-]\d+)([+-]\d+)')
ROTATIONS = {'normal', 'left', 'right', 'inverted'}


@dataclass
class Mode:
    name: str
    rates: list[str] = field(default_factory=list)
    preferred: bool = False


@dataclass
class Output:
    name: str
    connected: bool
    enabled: bool = False
    primary: bool = False
    mode: str = ''
    rate: str = ''
    x: int = 0
    y: int = 0
    rotation: str = 'normal'
    modes: list[Mode] = field(default_factory=list)

    def dims(self) -> tuple[int, int]:
        match = MODE_RE.fullmatch(self.mode)
        if not match:
            return (0, 0)
        a, b = map(int, match.groups())
        return (b, a) if self.rotation in {'left', 'right'} else (a, b)


def parse_xrandr(text: str) -> list[Output]:
    result: list[Output] = []
    output: Output | None = None
    for line in text.splitlines():
        if not line.startswith((' ', '\t')):
            match = HEADER_RE.match(line)
            if not match or not NAME_RE.fullmatch(match[1]):
                output = None
                continue
            detail = match[3] or ''
            output = Output(name=match[1], connected=match[2] == 'connected')
            output.primary = bool(re.search(r'\bprimary\b', detail))
            geo = GEO_RE.search(detail)
            if output.connected and geo:
                output.enabled = True
                output.mode = f'{geo[1]}x{geo[2]}'
                output.x, output.y = int(geo[3]), int(geo[4])
            rotate = re.search(r'\((normal|left|right|inverted)\b', detail)
            if rotate:
                output.rotation = rotate[1]
            result.append(output)
        elif output and output.connected:
            match = re.match(r'^\s+(\d{2,5}x\d{2,5})\s+(.+)$', line)
            if not match:
                continue
            mode = Mode(match[1])
            for token in match[2].split():
                if re.fullmatch(r'\d+(?:\.\d+)?[+*]*', token):
                    rate = token.rstrip('+*')
                    if rate not in mode.rates:
                        mode.rates.append(rate)
                    if '+' in token:
                        mode.preferred = True
                    if '*' in token and output.mode == mode.name:
                        output.rate = rate
            if mode.rates:
                output.modes.append(mode)
    for o in result:
        if o.enabled and not o.rate:
            m = next((m for m in o.modes if m.name == o.mode), None)
            if m and m.rates:
                o.rate = m.rates[0]
        if o.connected and not o.mode and o.modes:
            preferred = next((m for m in o.modes if m.preferred), o.modes[0])
            o.mode = preferred.name
            o.rate = preferred.rates[0]
    return result


def read_outputs(*, runner=subprocess.run) -> list[Output]:
    proc = runner(['xrandr', '--query'], capture_output=True, text=True, timeout=6, check=True)
    outputs = parse_xrandr(proc.stdout)
    if not outputs or not any(o.connected for o in outputs):
        raise RuntimeError('XRandR não retornou monitores conectados.')
    if not any(o.primary and o.enabled for o in outputs):
        next((setattr(o, 'primary', True) for o in outputs if o.enabled), None)
    return outputs


def validate(outputs: list[Output]) -> None:
    enabled = [o for o in outputs if o.connected and o.enabled]
    if not enabled:
        raise ValueError('É necessário manter ao menos um monitor ligado.')
    if sum(o.primary for o in enabled) != 1:
        raise ValueError('Escolha exatamente um monitor principal ativo.')
    names = [o.name for o in outputs]
    if len(names) != len(set(names)) or any(not NAME_RE.fullmatch(n) for n in names):
        raise ValueError('Nomes de saída XRandR inválidos.')
    for o in enabled:
        if o.rotation not in ROTATIONS or not MODE_RE.fullmatch(o.mode):
            raise ValueError(f'Modo ou rotação inválida: {o.name}')
        if not any(m.name == o.mode and (not o.rate or o.rate in m.rates) for m in o.modes):
            raise ValueError(f'Modo/frequência não oferecidos por {o.name}: {o.mode} @ {o.rate}')
        if o.x < -32768 or o.y < -32768 or o.x > 32768 or o.y > 32768:
            raise ValueError('Coordenadas de monitor fora do intervalo permitido.')
    # Não aceitamos telas sobrepostas nesta interface (espelhamento não suportado).
    for i, a in enumerate(enabled):
        wa, ha = a.dims()
        for b in enabled[i+1:]:
            wb, hb = b.dims()
            if max(a.x, b.x) < min(a.x+wa, b.x+wb) and max(a.y, b.y) < min(a.y+ha, b.y+hb):
                raise ValueError(f'As telas {a.name} e {b.name} estão sobrepostas. Separe os retângulos.')


def normalized(outputs: list[Output]) -> list[Output]:
    copied = [Output(**{**asdict(o), 'modes': [Mode(**asdict(m)) for m in o.modes]}) for o in outputs]
    active = [o for o in copied if o.connected and o.enabled]
    if active:
        left = min(o.x for o in active)
        top = min(o.y for o in active)
        for o in active:
            o.x -= left
            o.y -= top
    return copied


def xrandr_argv(outputs: list[Output]) -> list[str]:
    validate(outputs)
    argv = ['xrandr']
    for o in outputs:
        if not o.connected:
            continue
        argv.extend(['--output', o.name])
        if not o.enabled:
            argv.append('--off')
            continue
        argv.extend(['--mode', o.mode])
        if o.rate:
            argv.extend(['--rate', o.rate])
        argv.extend(['--pos', f'{o.x}x{o.y}', '--rotate', o.rotation])
        if o.primary:
            argv.append('--primary')
    return argv


def safe_state_dir(home: Path | None = None) -> Path:
    root = (home or Path.home()) / '.local/state/wolf-linux/control-center/monitors'
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    return root


def atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temp = path.with_name('.' + path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with temp.open('x', encoding='utf-8') as f:
            os.chmod(temp, 0o600)
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def create_pending(original: list[Output], requested: list[Output], *, home: Path | None = None) -> Path:
    folder = safe_state_dir(home) / 'pending' / uuid.uuid4().hex
    folder.mkdir(mode=0o700, parents=True)
    atomic_json(folder/'transaction.json', {
        'format': 1,
        'created': datetime.now(timezone.utc).isoformat(),
        'original': xrandr_argv(original),
        'requested': xrandr_argv(requested),
    })
    return folder


def run_xrandr(argv: list[str], *, runner=subprocess.run) -> None:
    if not argv or argv[0] != 'xrandr':
        raise ValueError('Comando XRandR inválido')
    proc = runner(argv, capture_output=True, text=True, timeout=12)
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout or 'XRandR falhou').strip())


def watchdog(folder: Path, *, timeout_seconds: int = 40, runner=subprocess.run) -> int:
    folder = folder.resolve()
    root = (safe_state_dir() / 'pending').resolve()
    if folder.parent != root or not (folder/'transaction.json').is_file():
        return 2
    with (folder/'transaction.json').open(encoding='utf-8') as f:
        data = json.load(f)
    if data.get('format') != 1:
        return 3
    until = time.monotonic() + timeout_seconds
    if (folder/'confirmed').exists():
        return 0
    while time.monotonic() < until:
        if (folder/'confirmed').exists():
            return 0
        time.sleep(0.25)
    try:
        run_xrandr(data['original'], runner=runner)
        (folder/'rollback.log').write_text('Restaurado automaticamente\n', encoding='utf-8')
        return 0
    except Exception as exc:
        try:
            # Último recurso: recuperar ao menos uma tela, se os modos antigos falharem.
            run_xrandr(['xrandr', '--auto'], runner=runner)
            (folder/'rollback.log').write_text('Layout original falhou: ' + str(exc) +
                '\nRecuperação por xrandr --auto executada.\n', encoding='utf-8')
            return 0
        except Exception as second:
            (folder/'rollback.log').write_text('Erro ao restaurar: ' + str(exc) +
                '\nFallback também falhou: ' + str(second) + '\n', encoding='utf-8')
            return 1


def mark_confirmed(folder: Path) -> None:
    (folder/'confirmed').write_text('ok\n', encoding='utf-8')


def can_autostart(saved: list[Output], live: list[Output]) -> bool:
    if {o.name for o in saved if o.connected} != {o.name for o in live if o.connected}:
        return False
    try:
        validate(saved)
    except ValueError:
        return False
    for o in saved:
        if not o.connected or not o.enabled:
            continue
        found = next((x for x in live if x.name == o.name), None)
        if not found or not any(m.name == o.mode and (not o.rate or o.rate in m.rates) for m in found.modes):
            return False
    return True


def save_persistent(outputs: list[Output], *, home: Path | None = None) -> Path:
    home = home or Path.home()
    root = safe_state_dir(home)
    normalized_outputs = normalized(outputs)
    atomic_json(root/'layout.json', {'format': 1, 'outputs': [asdict(o) for o in normalized_outputs]})
    autostart = home/'.config/autostart'
    autostart.mkdir(parents=True, exist_ok=True)
    exec_path = home/'.local/bin/wolf-monitors-apply'
    # Usar o caminho do módulo que realmente está executando: release global
    # (/usr/local/lib) ou uma cópia local (XDG_DATA_HOME), sem assumir ~/.local.
    import shlex
    saved_script = shlex.quote(str(Path(__file__).resolve()))
    content = f'''#!/bin/sh
# Executa uma única vez no login, apenas em LXQt/X11.
[ "$XDG_SESSION_TYPE" = "x11" ] || exit 0
case ":$XDG_CURRENT_DESKTOP:" in *:LXQt:*) ;; *) exit 0;; esac
exec /usr/bin/python3 {saved_script} --apply-saved
'''
    exec_path.parent.mkdir(parents=True, exist_ok=True)
    exec_path.write_text(content, encoding='utf-8')
    exec_path.chmod(0o755)
    # Exec field accepts quoted paths. Escape \ and " according to Desktop Entry specification.
    escaped = str(exec_path).replace('\\', '\\\\').replace('"', '\\"')
    desktop = autostart/'wolf-lxqt-layout-restore.desktop'
    desktop.write_text('[Desktop Entry]\nType=Application\nName=Wolf LXQt Monitor Layout\n'
                       f'Exec="{escaped}"\nOnlyShowIn=LXQt;\nTerminal=false\nX-LXQt-Module=false\n', encoding='utf-8')
    # Migrar somente o atalho legado de restauração, sem apagar o autostart
    # de painéis que também usava o nome wolf-lxqt-monitors.desktop.
    legacy = autostart/'wolf-lxqt-monitors.desktop'
    if legacy.is_file() and not legacy.is_symlink():
        old = legacy.read_text(encoding='utf-8', errors='replace')
        if 'wolf-monitors-apply' in old and 'wolf-lxqt-monitors --session' not in old:
            legacy.unlink()
    return desktop


def disable_persistent(*, home: Path | None = None) -> None:
    home = home or Path.home()
    autostart = home/'.config/autostart'
    files = [autostart/'wolf-lxqt-layout-restore.desktop',
             safe_state_dir(home)/'layout.json']
    legacy = autostart/'wolf-lxqt-monitors.desktop'
    # Nunca remover o autostart de painéis do Wolf.
    if legacy.is_file() and not legacy.is_symlink():
        old = legacy.read_text(encoding='utf-8', errors='replace')
        if 'wolf-monitors-apply' in old and 'wolf-lxqt-monitors --session' not in old:
            files.append(legacy)
    for file in files:
        if file.is_symlink():
            raise RuntimeError(f'Não alterarei um link simbólico: {file}')
        file.unlink(missing_ok=True)


def load_saved(*, home: Path | None = None) -> list[Output] | None:
    layout = safe_state_dir(home) / 'layout.json'
    if not layout.is_file() or layout.is_symlink():
        return None
    try:
        obj = json.loads(layout.read_text(encoding='utf-8'))
        if obj.get('format') != 1:
            return None
        result = []
        for o in obj['outputs']:
            modes = [Mode(**m) for m in o.pop('modes')]
            result.append(Output(**o, modes=modes))
        return result
    except (ValueError, KeyError, TypeError):
        return None


def apply_saved(*, runner=subprocess.run) -> bool:
    if os.environ.get('XDG_SESSION_TYPE') != 'x11' or 'LXQt' not in os.environ.get('XDG_CURRENT_DESKTOP','').split(':'):
        return False
    saved = load_saved()
    if not saved:
        return False
    live = read_outputs(runner=runner)
    if not can_autostart(saved, live):
        return False
    run_xrandr(xrandr_argv(saved), runner=runner)
    # Restaura também os painéis após o XRandR: o autostart de painéis pode
    # ter rodado antes de a segunda saída ficar ativa.
    try:
        subprocess.run(['/usr/local/bin/wolf-lxqt-monitors'], check=False,
                       capture_output=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return True


def cli() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--watchdog', metavar='FOLDER', type=Path)
    parser.add_argument('--apply-saved', action='store_true')
    parser.add_argument('--print', action='store_true')
    args = parser.parse_args()
    if args.watchdog:
        sys.exit(watchdog(args.watchdog))
    if args.apply_saved:
        sys.exit(0 if apply_saved() else 0)  # condição diferente: não alterar monitor
    if args.print:
        for o in read_outputs():
            print(o)


if __name__ == '__main__':
    cli()
