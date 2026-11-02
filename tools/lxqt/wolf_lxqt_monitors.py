#!/usr/bin/env python3
"""Wolf LXQt/X11: reconcilia painéis com os monitores ativos, sem watcher.

Não depende de seções panel2 preservadas pelo LXQt. Não altera layouts XRandR.
Execução manual (`--apply`) ou uma vez no login (`--session`).
"""
from __future__ import annotations
import argparse
import configparser
from datetime import datetime
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import sys

PANEL = Path.home() / '.config/lxqt/panel.conf'
MAX_PANELS = 8


def monitor_indices(out=None):
    if out is None:
        if not os.environ.get('DISPLAY'):
            return None
        try:
            p = subprocess.run(['xrandr', '--listmonitors'], capture_output=True,
                               text=True, check=False, timeout=8)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if p.returncode:
            return None
        out = p.stdout
    ids = []
    primary = None
    for line in out.splitlines():
        match = re.match(r'^\s*(\d+):\s+(\S+)', line)
        if match:
            idx = int(match[1]); ids.append(idx)
            if '*' in match[2]: primary = idx
    if not ids:
        return None
    if primary not in ids: primary = ids[0]
    # O principal primeiro, demais na ordem XRandR.
    return tuple([primary] + [i for i in ids if i != primary])


def monitors(out=None):
    """Compatibilidade com as primeiras versões do helper (2 telas)."""
    indices = monitor_indices(out)
    if indices is None: return None
    return indices[0], indices[1] if len(indices)>1 else None


def root_panels_entries(text):
    """Valores reais do INI, antes da primeira seção; QSettings usa o último.

    configparser(strict=False) sozinho encobre chaves duplicadas e faz a
    verificação dizer `sincronizados` com o LXQt carregando somente panel1.
    """
    root_lines = []
    for line in text.splitlines():
        if re.match(r'^\s*\[', line):
            break
        if re.match(r'^\s*panels\s*=', line):
            root_lines.append(line.split('=', 1)[1].strip())
    return root_lines


def check_panel_list(text, ids):
    expected = ','.join(f'panel{i}' for i in range(1, len(ids) + 1))
    values = root_panels_entries(text)
    # A lista canônica deve existir UMA única vez para o LXQt/QSettings.
    return values == [expected]


def _parse(text):
    cp = configparser.RawConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    cp.read_string('[DEFAULT]\n' + text if not text.startswith('[DEFAULT]') else text)
    return cp



def _qt_panels(panel):
    """Consulta o valor QSettings REAL, não só a representação textual do INI."""
    from PySide6.QtCore import QSettings
    conf = QSettings(str(panel), QSettings.IniFormat)
    conf.sync()
    if conf.status() != QSettings.NoError:
        raise RuntimeError(f'Qt não conseguiu ler {panel}: {conf.status()}')
    value = conf.value('panels')
    if isinstance(value, (list, tuple)):
        return [str(x) for x in value], type(value).__name__
    return [x.strip() for x in str(value or '').split(',') if x.strip()], type(value).__name__


def _qt_write_panels(panel, ids):
    """Fix5 homologado: setValue(QStringList), sync e verificação independente."""
    from PySide6.QtCore import QSettings
    expected = [f'panel{i}' for i in range(1, len(ids) + 1)]
    conf = QSettings(str(panel), QSettings.IniFormat)
    conf.setValue('panels', expected)
    conf.sync()
    if conf.status() != QSettings.NoError:
        raise RuntimeError(f'QSettings não gravou lista de painéis: {conf.status()}')
    value, typ = _qt_panels(panel)
    if value != expected or (len(ids) > 1 and typ not in ('list','tuple')):
        raise RuntimeError('Qt não carregou a lista completa de painéis.')
    # Ler de um segundo processo: evita resultados falsos do cache de QSettings.
    script = ("import sys\nfrom PySide6.QtCore import QSettings\n"
              "s=QSettings(sys.argv[1],QSettings.IniFormat);s.sync()\n"
              "v=s.value('panels');print('|'.join(v) if isinstance(v,(list,tuple)) else str(v))\n"
              "print(type(v).__name__);print(s.status())\n")
    proc = subprocess.run([sys.executable, '-c', script, str(panel)],
                          text=True, capture_output=True, timeout=12, check=False)
    lines = proc.stdout.splitlines()
    if (proc.returncode or len(lines) < 3 or lines[0].split('|') != expected
            or (len(ids) > 1 and lines[1] not in ('list', 'tuple'))
            or 'NoError' not in lines[2]):
        raise RuntimeError('Validação QSettings em novo processo falhou: '+(proc.stderr or proc.stdout))
    print(f'[QT] Painéis registrados como QStringList: {expected}')


def _backup(panel: Path):
    root = panel.parents[2] / 'wolf-backups/lxqt-panels'
    root.mkdir(parents=True, exist_ok=True)
    folder = root / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    folder.mkdir(mode=0o700)
    shutil.copy2(panel, folder / 'panel.conf')
    return folder / 'panel.conf'


def _add_plugin(cp, name: str, kind: str, template: str | None = None):
    if not cp.has_section(name):
        cp.add_section(name)
        if template and cp.has_section(template):
            for k, v in cp.items(template):
                if k not in cp.defaults(): cp.set(name, k, v)
    if not cp.has_option(name, 'type'):
        cp.set(name, 'type', kind)


def _ensure_panel(cp, index: int, desktop: int):
    name = f'panel{index}'
    if not cp.has_section(name):
        cp.add_section(name)
        for k, v in dict(position='Bottom', panelSize='38', iconSize='24',
                         width='100', lineCount='1').items():
            cp.set(name, k, v)
    plugins = ['menu','quick','tasks']
    if index == 1: plugins += ['status','tray','volume']
    plugins += ['clock','showdesktop']
    current = [x.strip() for x in cp.get(name, 'plugins', fallback='').split(',') if x.strip()]
    required = [p + str(index) for p in plugins]
    for widget in required:
        if widget not in current: current.append(widget)
    cp.set(name, 'plugins', ','.join(current))
    cp.set(name, 'desktop', str(desktop))
    for short, kind in [('menu','fancymenu'),('quick','quicklaunch'),
                        ('tasks','taskbar'),('clock','worldclock'),
                        ('showdesktop','showdesktop')]:
        _add_plugin(cp, f'{short}{index}', kind, f'{short}1' if index != 1 else None)
    if index == 1:
        for short, kind in [('status','statusnotifier'),('tray','tray'),('volume','volume')]:
            _add_plugin(cp, f'{short}1', kind)
    # O painel secundário nunca deve mostrar tarefas de outra tela.
    if not cp.has_option(f'tasks{index}', 'showOnlyCurrentScreenTasks'):
        cp.set(f'tasks{index}', 'showOnlyCurrentScreenTasks', 'true')


def _targets(counts):
    if counts is None: return None
    vals = list(counts)
    if len(vals) == 2 and vals[1] is None: vals = vals[:1]
    vals = [x for x in vals if x is not None]
    if not vals or len(vals) > MAX_PANELS or len(set(vals)) != len(vals):
        raise ValueError('Quantidade ou índices de monitores não suportados.')
    if any(not isinstance(x, int) or x < 0 for x in vals):
        raise ValueError('Índice de monitor inválido.')
    return vals


def adjust(text, primary, secondary=None, extra=()):
    ids = _targets([primary, secondary, *extra])
    cp = _parse(text)
    # A sessão LXQt pode descartar seções de painéis inativos; recriá-las.
    for index, desktop in enumerate(ids, 1):
        _ensure_panel(cp, index, desktop)
    cp['DEFAULT']['panels'] = ','.join(f'panel{i}' for i in range(1, len(ids) + 1))
    buff = io.StringIO(); cp.write(buff, space_around_delimiters=False)
    result = buff.getvalue().replace('[DEFAULT]\n', '', 1)
    if not check_panel_list(result, ids):
        raise ValueError('A escrita do panel.conf produziu chaves panels duplicadas.')
    return result


def _matches(text, ids):
    cp = _parse(text)
    return (check_panel_list(text, ids)
            and all(cp.has_section(f'panel{i}') and
                    cp.get(f'panel{i}', 'desktop', fallback='') == str(d) and
                    all(cp.has_section(f'{p}{i}') and f'{p}{i}' in
                            [x.strip() for x in cp.get(f'panel{i}','plugins',fallback='').split(',')]
                            for p in (('menu','quick','tasks','status','tray','volume','clock','showdesktop')
                                      if i == 1 else ('menu','quick','tasks','clock','showdesktop')))
                    for i, d in enumerate(ids, 1)))


def _sections_match(text, ids):
    """Verifica os widgets independentemente da serialização Qt de 'panels'."""
    cp = _parse(text)
    return all(cp.has_section(f'panel{i}') and
               cp.get(f'panel{i}', 'desktop', fallback='') == str(d) and
               all(cp.has_section(f'{w}{i}') and f'{w}{i}' in
                   [a.strip() for a in cp.get(f'panel{i}','plugins',fallback='').split(',')]
                   for w in (('menu','quick','tasks','status','tray','volume','clock','showdesktop')
                             if i == 1 else ('menu','quick','tasks','clock','showdesktop')))
               for i, d in enumerate(ids, 1))


def status(panel=PANEL, counts=None):
    ids = _targets(counts if counts is not None else monitor_indices())
    if ids is None:
        return 'Monitores indisponíveis: verifique a sessão X11 e o DISPLAY.'
    if not panel.is_file(): return f'Painel ausente: {panel}'
    try:
        data = panel.read_text(encoding='utf-8')
        cp = _parse(data)
        entries = root_panels_entries(data)
        configured = ', '.join(entries) if entries else 'não definido'
        valid = _sections_match(data, ids)
        # Fix5: mesmo com linha textual correta, o Qt pode ler só panel1.
        try:
            actual, typ = _qt_panels(panel)
            expect = [f'panel{i}' for i in range(1, len(ids)+1)]
            valid = valid and actual == expect and (len(ids) == 1 or typ in ('list','tuple'))
            qt_info = f'; QSettings={actual} ({typ})'
        except (ImportError, RuntimeError) as exc:
            valid = False
            qt_info = f'; QSettings indisponível: {exc}'
    except (OSError, configparser.Error) as exc:
        return f'Configuração do painel inválida: {exc}'
    return (f'Monitores ativos: {len(ids)} (índices XRandR: {ids}); '
            f'painéis configurados: {configured}; '
            f'declarações panels={len(entries)}; '
            f'{"sincronizados" if valid else "necessário aplicar/reconstruir"}.')


def apply(panel=PANEL, counts=None, refresh=False, force=False):
    ids = _targets(counts if counts is not None else monitor_indices())
    if ids is None:
        print('[AVISO] Monitores indisponíveis; configuração preservada.')
        return False
    if not panel.is_file() or panel.is_symlink():
        print('[ERRO] panel.conf ausente ou link simbólico; nenhuma alteração feita.')
        return False
    try:
        original = panel.read_text(encoding='utf-8')
        try:
            qt_names, qt_type = _qt_panels(panel)
        except (ImportError, RuntimeError) as exc:
            print(f'[ERRO] Não foi possível consultar QSettings: {exc}')
            return False
        expected_qt = [f'panel{i}' for i in range(1, len(ids)+1)]
        qt_valid = qt_names == expected_qt and (len(ids) == 1 or qt_type in ('list','tuple'))
        if _sections_match(original, ids) and qt_valid and not force:
            print('[OK] Arquivo e QSettings sincronizados.')
            return False
        updated = adjust(original, ids[0], ids[1] if len(ids)>1 else None, ids[2:])
    except (configparser.Error, ValueError, OSError) as exc:
        print(f'[ERRO] Configuração inválida, nada alterado: {exc}')
        return False
    if original == updated and not force: return False
    # Salvar a configuração ANTES de parar o painel: falha de backup não pode
    # deixar o usuário sem barra de tarefas.
    try:
        backup = _backup(panel)
    except OSError as exc:
        print(f'[ERRO] Backup não pôde ser criado; painel preservado: {exc}')
        return False
    running = False
    if refresh and os.environ.get('DISPLAY'):
        try:
            running = subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', 'lxqt-panel'],
                                     capture_output=True, check=False).returncode == 0
            if running:
                subprocess.run(['pkill','-TERM','-u',str(os.getuid()),'-x','lxqt-panel'], check=False)
                for _ in range(40):
                    if subprocess.run(['pgrep','-u',str(os.getuid()),'-x','lxqt-panel'],
                                      capture_output=True, check=False).returncode != 0: break
                    time.sleep(0.1)
                else:
                    print('[ERRO] LXQt Panel não encerrou; arquivo preservado.')
                    return False
        except OSError as exc:
            print(f'[ERRO] Não foi possível encerrar o painel: {exc}')
            return False
    temp = panel.with_name(panel.name + '.wolf-tmp')
    try:
        temp.write_text(updated, encoding='utf-8')
        temp.chmod(panel.stat().st_mode & 0o777)
        temp.replace(panel)
        _qt_write_panels(panel, ids)
    except (OSError, RuntimeError, ImportError, subprocess.TimeoutExpired) as exc:
        print(f'[ERRO] Ajuste Qt falhou; restaurando o backup: {exc}')
        try:
            shutil.copy2(backup, panel)
        except OSError as restore_exc:
            print(f'[ERRO] Restauração manual necessária: {backup} ({restore_exc})')
        if running:
            subprocess.Popen(['lxqt-panel'], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        return False
    finally:
        temp.unlink(missing_ok=True)
    print(f'[OK] Painéis sincronizados e verificados no Qt para {len(ids)} monitor(es); backup: {backup}')
    if refresh and os.environ.get('DISPLAY'):
        # O LXQt Session pode reiniciar o painel automaticamente. Conferir o
        # processo após o ajuste, em vez de presumir sucesso apenas pelo arquivo.
        time.sleep(0.7)
        alive = subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', 'lxqt-panel'],
                               capture_output=True, check=False).returncode == 0
        if not alive:
            try:
                subprocess.Popen(['lxqt-panel'], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
                time.sleep(1)
            except OSError as exc:
                print(f'[ERRO] Configuração salva, mas painel não inicia: {exc}')
                return False
        if not _sections_match(panel.read_text(encoding='utf-8'), ids) or _qt_panels(panel)[0] != [f'panel{i}' for i in range(1,len(ids)+1)]:
            print('[ERRO] O painel ou a sessão sobrescreveu o arquivo após o reinício; '
                  'consulte --diagnose antes de tentar novamente.')
            return False
    return True


def diagnose(panel=PANEL):
    print('[DIAGNÓSTICO] DISPLAY=' + os.environ.get('DISPLAY', '<ausente>'))
    print('[DIAGNÓSTICO] sessão=' + os.environ.get('XDG_CURRENT_DESKTOP','<ausente>'))
    try:
        p = subprocess.run(['xrandr','--listmonitors'], capture_output=True,
                           text=True, timeout=8)
        print('[DIAGNÓSTICO] xrandr --listmonitors (rc=%s):\n%s' % (p.returncode,p.stdout or p.stderr))
    except (OSError, subprocess.TimeoutExpired) as exc:
        print('[DIAGNÓSTICO] xrandr indisponível:', exc)
    try:
        from PySide6.QtGui import QGuiApplication
        app = QGuiApplication.instance() or QGuiApplication([])
        screens = list(app.screens())
        for index, screen in enumerate(screens):
            print(f'[DIAGNÓSTICO] Qt screen {index}: {screen.name()} '
                  f'geometry={screen.geometry().getRect()} '
                  f'primary={screen is app.primaryScreen()}')
    except Exception as exc:
        print('[DIAGNÓSTICO] Qt screens indisponíveis:', exc)
    print('[DIAGNÓSTICO] ' + status(panel))
    if panel.is_file():
        raw = panel.read_text(encoding='utf-8')
        print('[DIAGNÓSTICO] declarações panels no nível raiz:', root_panels_entries(raw))
        cp = _parse(raw)
        for name in cp.defaults().get('panels','').split(','):
            name=name.strip()
            if name:
                print(f'[DIAGNÓSTICO] {name}: desktop={cp.get(name,"desktop",fallback="?")} '
                      f'plugins={cp.get(name,"plugins",fallback="?")}')
    p = subprocess.run(['pgrep','-a','-u',str(os.getuid()),'-x','lxqt-panel'],
                       capture_output=True, text=True, check=False)
    print('[DIAGNÓSTICO] processo lxqt-panel: ' + (p.stdout.strip() or '<ausente>'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', action='store_true', help='Sincroniza uma vez no login X11')
    parser.add_argument('--no-restart', action='store_true', help='Não recarrega o lxqt-panel')
    parser.add_argument('--status', action='store_true', help='Somente diagnóstico')
    parser.add_argument('--apply', action='store_true', help='Aplica/reconstrói painéis agora')
    parser.add_argument('--force', action='store_true', help='Reaplica mesmo quando panel.conf já parece correto')
    parser.add_argument('--diagnose', action='store_true', help='Mostra XRandR, Qt screens, processo e painéis')
    args = parser.parse_args()
    if args.session:
        # Aguarda os monitores físicos aparecerem; não instala watcher.
        time.sleep(2)
        for attempt in range(5):
            ids = monitor_indices()
            if ids and len(ids) > 1: break
            if attempt < 4: time.sleep(2)
    if args.diagnose:
        diagnose()
        return
    if args.status:
        print(status())
    else:
        changed = apply(refresh=not args.no_restart, force=args.force)
        if not changed:
            # A idempotência é sucesso; falha real é sinalizada com exit code.
            details = status()
            if 'sincronizados' not in details:
                parser.exit(1, '[ERRO] ' + details + '\n')


if __name__ == '__main__':
    main()
