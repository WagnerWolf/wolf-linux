#!/usr/bin/env python3
"""Diagnóstico e ações explícitas do perfil Wolf LXQt. Zero alterações na importação."""
from __future__ import annotations

import configparser
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import os
import re
import shutil
import subprocess

APP_GROUPS: tuple[tuple[str, tuple[str, ...], tuple[str, ...]], ...] = (
    ('Navegador', ('google-chrome.desktop', 'google-chrome-stable.desktop', 'chromium.desktop'),
     ('x-scheme-handler/http', 'x-scheme-handler/https', 'text/html', 'application/xhtml+xml')),
    ('Pastas', ('pcmanfm-qt.desktop',), ('inode/directory',)),
    ('Texto', ('org.kde.kate.desktop', 'kate.desktop'), ('text/plain',)),
    ('Vídeo', ('io.github.mpc_qt.mpc-qt.desktop', 'mpc-qt.desktop', 'mpcqt.desktop'), ('video/mp4', 'video/x-matroska', 'video/webm')),
    ('Áudio', ('audacious.desktop',), ('audio/mpeg', 'audio/flac', 'audio/ogg')),
    ('PDF', ('org.kde.okular.desktop', 'okular.desktop'), ('application/pdf',)),
    ('Arquivos compactados', ('lxqt-archiver.desktop',),
     ('application/zip', 'application/x-zip-compressed', 'application/x-7z-compressed', 'application/vnd.rar')),
)


@dataclass(frozen=True)
class ProfileCheck:
    label: str
    status: str  # OK, AVISO ou INFO
    detail: str

    def render(self) -> str:
        return f'[{self.status}] {self.label}: {self.detail}'


def _load_ini(path: Path) -> configparser.RawConfigParser:
    cfg = configparser.RawConfigParser(interpolation=None, strict=False)
    cfg.optionxform = str
    if path.is_file() and not path.is_symlink():
        data = path.read_text(encoding='utf-8', errors='replace')
        # LXQt usa QSettings INI com panels= no nível raiz.
        if data.lstrip() and not data.lstrip().startswith('['):
            data = '[DEFAULT]\n' + data
        cfg.read_string(data)
    return cfg


def _get(cfg: configparser.RawConfigParser, section: str, key: str, default: str = '') -> str:
    if section == 'DEFAULT':
        return cfg.defaults().get(key, default)
    if not cfg.has_section(section):
        return default
    return cfg.get(section, key, fallback=default)


def panel_checks(home: Path | None = None, *, monitor_count: int | None = None) -> list[ProfileCheck]:
    home = home or Path.home()
    path = home / '.config/lxqt/panel.conf'
    if not path.is_file():
        return [ProfileCheck('Painel LXQt', 'AVISO', 'panel.conf não encontrado')]
    try:
        cfg = _load_ini(path)
    except (OSError, configparser.Error) as exc:
        return [ProfileCheck('Painel LXQt', 'AVISO', f'Erro ao ler configuração: {exc}')]
    panel_ids = [p.strip() for p in _get(cfg, 'DEFAULT', 'panels').split(',') if p.strip()]
    if not panel_ids:
        return [ProfileCheck('Painéis', 'AVISO', 'Nenhum painel definido na chave panels')]
    checks: list[ProfileCheck] = []
    checks.append(ProfileCheck('Painéis ativos', 'OK' if len(panel_ids) >= 1 else 'AVISO',
                               f'{len(panel_ids)}: {", ".join(panel_ids)}'))
    if monitor_count is not None:
        checks.append(ProfileCheck('Painéis x monitores',
                                   'OK' if len(panel_ids) == monitor_count else 'AVISO',
                                   f'{len(panel_ids)} painéis para {monitor_count} monitores detectados'))
    desktops: list[str] = []
    tray_panels: list[str] = []
    for pid in panel_ids:
        desktop = _get(cfg, pid, 'desktop', '?')
        desktops.append(desktop)
        plugins = [x.strip() for x in _get(cfg, pid, 'plugins').split(',') if x.strip()]
        types = {name: _get(cfg, name, 'type', '').lower() for name in plugins}
        quick = [name for name, kind in types.items() if kind == 'quicklaunch']
        tasks = [name for name, kind in types.items() if kind == 'taskbar']
        tray = [name for name, kind in types.items() if kind in {'tray','statusnotifier'}]
        if tray:
            tray_panels.append(pid)
        checks.append(ProfileCheck(f'{pid} na tela', 'OK' if desktop != '?' else 'AVISO',
                                   f'desktop={desktop}'))
        checks.append(ProfileCheck(f'{pid} lançadores', 'OK' if quick else 'AVISO',
                                   ', '.join(quick) if quick else 'quicklaunch ausente'))
        if tasks:
            filtering = all(_get(cfg, name, 'showOnlyCurrentScreenTasks').lower() == 'true' for name in tasks)
            checks.append(ProfileCheck(f'{pid} tarefas por monitor', 'OK' if filtering else 'AVISO',
                                       'filtro ligado' if filtering else 'showOnlyCurrentScreenTasks ausente/desligado'))
        else:
            checks.append(ProfileCheck(f'{pid} tarefas', 'AVISO', 'taskbar ausente'))
    if len(set(desktops)) == len(desktops) and '?' not in desktops:
        checks.append(ProfileCheck('Painéis em telas distintas', 'OK', ', '.join(desktops)))
    else:
        checks.append(ProfileCheck('Painéis em telas distintas', 'AVISO', ', '.join(desktops)))
    checks.append(ProfileCheck('Bandeja principal', 'OK' if len(tray_panels) == 1 else 'AVISO',
                               f'em {", ".join(tray_panels)}' if tray_panels else 'não encontrada'))
    return checks


def xrandr_count(runner=subprocess.run) -> int | None:
    """Consulta estritamente somente leitura; não chama xrandr para aplicar layout."""
    if not os.environ.get('DISPLAY') or not shutil.which('xrandr'):
        return None
    try:
        result = runner(['xrandr', '--listmonitors'], capture_output=True, text=True, timeout=4, check=False)
        match = re.search(r'^Monitors:\s*(\d+)', result.stdout, re.MULTILINE)
        return int(match.group(1)) if result.returncode == 0 and match else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def desktop_dirs(home: Path | None = None) -> tuple[Path, ...]:
    h = home or Path.home()
    data_home = Path(os.environ.get('XDG_DATA_HOME', str(h / '.local/share'))) if home is None else h / '.local/share'
    raw = os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share')
    return tuple([data_home / 'applications'] + [Path(x)/'applications' for x in raw.split(':') if x])


def find_desktop(candidates: tuple[str, ...], dirs: tuple[Path, ...]) -> str | None:
    for desktop in candidates:
        for d in dirs:
            if (d / desktop).is_file():
                return desktop
    return None


def mime_current(mime: str, runner=subprocess.run) -> str:
    try:
        result = runner(['xdg-mime', 'query', 'default', mime], capture_output=True,
                        text=True, timeout=4, check=False)
        return result.stdout.strip() if result.returncode == 0 else ''
    except (OSError, subprocess.TimeoutExpired):
        return ''


def mime_checks(home: Path | None = None, *, dirs: tuple[Path, ...] | None = None,
                runner=subprocess.run) -> list[ProfileCheck]:
    dirs = dirs or desktop_dirs(home)
    checks = []
    for name, candidates, mimes in APP_GROUPS:
        expected = find_desktop(candidates, dirs)
        current = mime_current(mimes[0], runner)
        if expected is None:
            checks.append(ProfileCheck(name, 'AVISO', f'lançador não encontrado; atual: {current or "nenhum"}'))
        elif current in candidates:
            checks.append(ProfileCheck(name, 'OK', current))
        else:
            checks.append(ProfileCheck(name, 'AVISO', f'atual: {current or "nenhum"}; recomendado: {expected}'))
    return checks


def switcher_checks(home: Path | None = None) -> list[ProfileCheck]:
    h = home or Path.home()
    switcher = h / '.local/bin/wolf-alt-tab-monitor'
    rc = h / '.config/openbox/lxqt-rc.xml'
    if not switcher.is_file():
        return [ProfileCheck('Wolf Alt+Tab', 'AVISO', 'executável ausente')]
    if not rc.is_file():
        return [ProfileCheck('Wolf Alt+Tab', 'AVISO', 'configuração Openbox ausente')]
    try:
        import xml.etree.ElementTree as ET
        root = ET.parse(rc).getroot()
        ns = (root.tag.partition('}')[0] + '}') if root.tag.startswith('{') else ''
        kb = root.find(ns + 'keyboard')
        binds = {} if kb is None else {b.get('key', ''): b for b in kb.findall(ns + 'keybind')}
        alt = binds.get('A-Tab')
        commands = [] if alt is None else [x.text or '' for x in alt.iter(ns + 'command')]
        valid = any('wolf-alt-tab-monitor' in command for command in commands)
        return [ProfileCheck('Wolf Alt+Tab padrão', 'OK' if valid else 'AVISO',
                             'Alt+Tab direcionado ao Wolf' if valid else 'atalho não localizado no Openbox')]
    except (OSError, ET.ParseError) as exc:
        return [ProfileCheck('Wolf Alt+Tab', 'AVISO', f'XML inválido: {exc}')]


def profile_report(home: Path | None = None) -> str:
    home = home or Path.home()
    count = xrandr_count()
    lines = ['Wolf LXQt — auditoria do perfil (somente leitura)',
             f'Monitores XRandR: {count if count is not None else "não disponíveis"}',
             f'Sessão: {os.environ.get("XDG_CURRENT_DESKTOP", "?")}/{os.environ.get("XDG_SESSION_TYPE", "?")}',
             '']
    for check in [*panel_checks(home, monitor_count=count), *switcher_checks(home), *mime_checks(home)]:
        lines.append(check.render())
    lines.extend(['', 'Nenhuma configuração foi alterada.'])
    return '\n'.join(lines)


def export_report(home: Path | None = None) -> Path:
    h = home or Path.home()
    root = h / '.local/state/wolf-linux/control-center/reports'
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    target = root / f'lxqt-audit-{stamp}.txt'
    with target.open('x', encoding='utf-8') as stream:
        stream.write(profile_report(h) + '\n')
    target.chmod(0o600)
    return target


def apply_mime_defaults(home: Path | None = None, *, dirs: tuple[Path, ...] | None = None,
                        runner=subprocess.run) -> list[str]:
    """Executa apenas sob pedido explícito; backups são responsabilidade da UI.

    xdg-mime atualiza o mimeapps.list do usuário e não toca nos aplicativos em execução.
    """
    dirs = dirs or desktop_dirs(home)
    results: list[str] = []
    for group, candidates, mimes in APP_GROUPS:
        desktop = find_desktop(candidates, dirs)
        if desktop is None:
            results.append(f'[AVISO] {group}: sem aplicativo instalado; ignorado')
            continue
        for mime in mimes:
            if mime_current(mime, runner) == desktop:
                continue
            try:
                proc = runner(['xdg-mime', 'default', desktop, mime],
                              capture_output=True, text=True, timeout=7, check=False)
                if proc.returncode == 0:
                    results.append(f'[OK] {mime} → {desktop}')
                else:
                    results.append(f'[ERRO] {mime}: {proc.stderr.strip() or proc.returncode}')
            except (OSError, subprocess.TimeoutExpired) as exc:
                results.append(f'[ERRO] {mime}: {exc}')
    return results or ['[OK] Todos os padrões já estavam corretos']


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description='Auditor do perfil Wolf LXQt (não altera nada sem --apply-mime)')
    parser.add_argument('--apply-mime', action='store_true', help='Reaplica aplicativos padrão; opção mutável')
    parser.add_argument('--export', action='store_true', help='Salva relatório de diagnóstico')
    args = parser.parse_args()
    if args.apply_mime:
        if 'LXQT' not in os.environ.get('XDG_CURRENT_DESKTOP', '').upper().split(':'):
            parser.error('Reaplicação só é permitida na sessão LXQt')
        from lxqt_support import create_snapshot
        print('Snapshot prévio:', create_snapshot())
        print('\n'.join(apply_mime_defaults()))
    elif args.export:
        print(export_report())
    else:
        print(profile_report())


if __name__ == '__main__':
    main()
