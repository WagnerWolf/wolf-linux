#!/usr/bin/env python3
"""Wolf Linux LXQt: diagnóstico e reparo experimental do valor 'panels' no QSettings.

Uso (usuário normal, dentro da sessão LXQt/X11):
  python3 wolf-painel-qt-fix5-teste.py --check
  python3 wolf-painel-qt-fix5-teste.py --apply

Não reconstrói os painéis; altera apenas a lista de painéis no QSettings.
Em caso de falha, restaura um backup e reinicia o LXQt Panel.
"""
from __future__ import annotations
import argparse
import ast
from datetime import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

PANEL = Path.home() / '.config/lxqt/panel.conf'


def qt():
    try:
        from PySide6.QtCore import QSettings
        return QSettings
    except ImportError as exc:
        raise RuntimeError('PySide6 não está disponível neste Python.') from exc


def active_monitors():
    cp = subprocess.run(['xrandr', '--listmonitors'], capture_output=True, text=True, timeout=8)
    if cp.returncode:
        raise RuntimeError('xrandr falhou: ' + cp.stderr.strip())
    screens = re.findall(r'^\s*\d+:\s+', cp.stdout, re.MULTILINE)
    if not 1 <= len(screens) <= 8:
        raise RuntimeError('Quantidade de monitores inválida: ' + str(len(screens)))
    return len(screens)


def qt_value(path):
    QSettings = qt()
    settings = QSettings(str(path), QSettings.IniFormat)
    settings.sync()
    value = settings.value('panels')
    if isinstance(value, (tuple, list)):
        names = [str(v).strip() for v in value if str(v).strip()]
    elif value is None:
        names = []
    else:
        names = [v.strip() for v in str(value).split(',') if v.strip()]
    return names, settings.status(), type(value).__name__


def declarations(text):
    current = '<raiz>'
    found = []
    for line_num, line in enumerate(text.splitlines(), 1):
        section = re.match(r'^\s*\[([^\]]+)\]\s*$', line)
        if section:
            current = section.group(1)
            continue
        if re.match(r'^\s*panels\s*=', line, re.I):
            found.append((line_num, current, line.strip().split('=', 1)[1].strip()))
    return found


def panel_running():
    proc = subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', 'lxqt-panel'],
                          capture_output=True, text=True, check=False)
    return proc.returncode == 0


def start_panel():
    if panel_running():
        return
    subprocess.Popen(['lxqt-panel'], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(1.5)
    if not panel_running():
        raise RuntimeError('lxqt-panel não reiniciou.')


def stop_panel():
    if not panel_running():
        return
    subprocess.run(['pkill', '-TERM', '-u', str(os.getuid()), '-x', 'lxqt-panel'],
                   check=False, timeout=6)
    for _ in range(40):
        if not panel_running():
            return
        time.sleep(.15)
    raise RuntimeError('lxqt-panel não encerrou; nenhuma configuração será escrita.')


def set_panels(path, expected):
    QSettings = qt()
    settings = QSettings(str(path), QSettings.IniFormat)
    settings.setValue('panels', expected)  # QStringList, como o lxqt-panel espera
    settings.sync()
    if settings.status() != QSettings.NoError:
        raise RuntimeError('QSettings não conseguiu salvar: ' + str(settings.status()))


def read_fresh(path):
    """Uma segunda instância do Python evita aceitar só o cache do processo atual."""
    script = ('import sys\nfrom PySide6.QtCore import QSettings\n'
              's=QSettings(sys.argv[1],QSettings.IniFormat);s.sync()\n'
              'v=s.value("panels");print(repr(v));print(str(s.status()))\n')
    cp = subprocess.run([sys.executable, '-c', script, str(path)], text=True,
                        capture_output=True, timeout=10)
    if cp.returncode:
        raise RuntimeError('Leitura independente do Qt falhou: ' + cp.stderr.strip())
    return cp.stdout.strip().splitlines()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--check', action='store_true')
    group.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error('Execute com seu usuário normal, sem sudo.')
    if not os.environ.get('DISPLAY') or os.environ.get('XDG_SESSION_TYPE', 'x11').lower() != 'x11':
        parser.error('Execute na sessão gráfica LXQt/X11 (DISPLAY disponível).')
    if not PANEL.is_file() or PANEL.is_symlink():
        parser.error('panel.conf não encontrado ou é link simbólico: ' + str(PANEL))
    try:
        n = active_monitors()
        expected = [f'panel{i}' for i in range(1, n + 1)]
        original = PANEL.read_bytes()
        text = original.decode('utf-8')
        for name in expected:
            if not re.search(r'^\s*\[' + re.escape(name) + r'\]\s*$', text, re.M):
                parser.error(f'Falta [{name}] no panel.conf. Não é seguro alterar apenas a lista.')
        before, status, typ = qt_value(PANEL)
        print('[XRANDR] Monitores detectados:', n)
        print('[QT] Arquivo:', PANEL)
        print('[QT] Valor lido:', before, '(tipo:', typ + ', status:', str(status) + ')')
        print('[QT] Valor esperado:', expected)
        for line, section, value in declarations(text):
            print(f'[INI] Linha {line}, seção {section}: panels={value}')
        if args.check:
            print('[INFO] Somente leitura; nenhuma alteração efetuada.')
            return 0
        if before == expected and (n == 1 or typ in ('list', 'tuple')):
            print('[OK] O Qt já lê a lista completa. Nenhuma mudança necessária.')
            return 0
    except (OSError, ValueError, UnicodeDecodeError, subprocess.SubprocessError, RuntimeError) as exc:
        print('[ERRO]', exc, file=sys.stderr)
        return 1

    # Backup anterior a qualquer alteração. Não apaga backups históricos.
    backupdir = Path.home() / 'wolf-backups' / 'lxqt-panels' / ('qt-fix5-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    try:
        backupdir.mkdir(parents=True, mode=0o700, exist_ok=False)
        shutil.copy2(PANEL, backupdir / 'panel.conf')
        print('[BACKUP]', backupdir / 'panel.conf')
    except OSError as exc:
        print('[ERRO] Não foi possível criar backup:', exc, file=sys.stderr)
        return 1

    was_running = panel_running()
    modified = False
    try:
        stop_panel()
        modified = True  # também restaurar se QSettings escrever parcialmente e falhar
        set_panels(PANEL, expected)
        after, status, typ = qt_value(PANEL)
        print('[QT] Após escrita:', after, '(tipo:', typ + ', status:', str(status) + ')')
        if after != expected or (n > 1 and typ not in ('list', 'tuple')):
            raise RuntimeError('Qt não retornou QStringList completa; correção não confirmada.')
        fresh = read_fresh(PANEL)
        print('[QT] Nova leitura independente:', fresh)
        if not fresh or ast.literal_eval(fresh[0]) != expected:
            raise RuntimeError('Leitura do Qt num processo novo não confirmou o resultado.')
        start_panel()
        print('[OK] Lista registrada pelo Qt. Confira visualmente o segundo painel.')
        return 0
    except (OSError, RuntimeError, ValueError, SyntaxError, subprocess.SubprocessError) as exc:
        print('[ERRO]', exc, file=sys.stderr)
        if modified:
            try:
                shutil.copy2(backupdir / 'panel.conf', PANEL)
                print('[RESTAURADO] Configuração original recuperada.')
            except OSError as restore_exc:
                print('[ERRO] Restauração automática falhou:', restore_exc,
                      'backup em:', backupdir / 'panel.conf', file=sys.stderr)
        try:
            if was_running:
                start_panel()
        except (OSError, RuntimeError) as start_exc:
            print('[ERRO] Falha ao reiniciar painel:', start_exc, file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
