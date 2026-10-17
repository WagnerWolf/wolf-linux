#!/usr/bin/env python3
"""Regressão: ERR trap nunca deve virar nome de pacote no resolver AUR.

Não toca em discos, não consulta repositórios e não instala pacotes reais.
"""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = (ROOT / 'install/wolf-install.sh').read_text(encoding='utf-8')
PACKAGE_CONF = ROOT / 'package-profiles/packages.conf'


def extract(name):
    start = SRC.index(f'{name}() {{\n')
    end = SRC.index('\n}', start) + 2
    return SRC[start:end]


FUNCTIONS = '\n\n'.join(extract(n) for n in (
    'stack_selected', 'collect_selected_official_packages',
    'collect_third_party_packages', 'collect_selected_stack_packages',
    'package_repository', 'record_package_resolution', 'install_selected_stack_packages'
))


class PackageListIsolation(unittest.TestCase):
    def shell(self, script, timeout=15):
        return subprocess.run(['bash', '-c', script], capture_output=True, text=True,
                              timeout=timeout)

    def setup_script(self):
        return f'''set -Eeuo pipefail
trap 'printf "====================================================\\nFALHA NA INSTALAÇÃO\\nEtapa: 64-resolver-stacks\\n"' ERR
source {str(PACKAGE_CONF)!r}
declare -A SELECTED_STACKS=()
{FUNCTIONS}
'''

    def test_producers_never_mix_trap_text_with_packages(self):
        for profile, selected in (
            ('minimal', ()), ('basic', ('daily',)),
            ('test', ('daily', 'gaming', 'development', 'extras')),
            ('full', ('daily', 'gaming', 'development', 'android', 'containers', 'extras')),
        ):
            with self.subTest(profile=profile):
                selects = '\n'.join(f'SELECTED_STACKS[{name}]=1' for name in selected)
                script = self.setup_script() + '\n' + selects + f'\nPROFILE={profile}\n' + '''
for fn in collect_selected_stack_packages collect_selected_official_packages collect_third_party_packages; do
    mapfile -t names < <("$fn")
    for pkg in "${names[@]}"; do
        [[ -z "$pkg" || "$pkg" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]] || exit 67
    done
    if [[ "$fn" == collect_selected_stack_packages ]]; then
        combined=" ${names[*]} "
        case "$PROFILE" in
            minimal) (( ${#names[@]} == 0 )) || exit 60 ;;
            basic)
                [[ "$combined" == *' google-chrome '* && "$combined" != *' docker '* ]] || exit 61 ;;
            test)
                [[ "$combined" == *' google-chrome '* && "$combined" == *' gimp '* && "$combined" != *' docker '* ]] || exit 62 ;;
            full)
                [[ "$combined" == *' docker '* && "$combined" == *' google-chrome '* && "$combined" == *' android-studio '* ]] || exit 63 ;;
        esac
    fi
    printf '%s count=%s\\n' "$fn" "${#names[@]}"
done
'''
                done = self.shell(script)
                self.assertEqual(done.returncode, 0, f'{profile}: {done.stdout}\n{done.stderr}')
                self.assertNotIn('FALHA NA INSTALAÇÃO', done.stdout)
                self.assertNotIn('Etapa:', done.stdout)
                self.assertEqual(len(done.stdout.splitlines()), 3)

    def test_real_resolver_loop_never_sends_diagnostics_to_yay(self):
        with tempfile.TemporaryDirectory() as work:
            from shlex import quote
            script = self.setup_script() + f'''
SELECTED_STACKS[daily]=1
STATE_DIR={quote(work)}
PACKAGE_RESOLUTION_LOG="$STATE_DIR/packages.tsv"
AUR_TEMP_SUDOERS="$STATE_DIR/test-sudoers"
USERNAME_VALUE=wolf
info() {{ printf '[INFO] %s\\n' "$*"; }}
warn() {{ printf '[AVISO] %s\\n' "$*"; }}
ok() {{ printf '[OK] %s\\n' "$*"; }}
die() {{ printf '[ERRO] %s\\n' "$*" >&2; exit 94; }}
ensure_yay() {{ :; }}
arch-chroot() {{
    [[ "$1" == /mnt ]] || return 92
    shift
    if [[ "$1" == pacman && "$2" == -Q ]]; then
        case "${{3:-}}" in
            google-chrome|mpc-qt|zsh-theme-powerlevel10k)
                [[ -e "$STATE_DIR/installed.${{3}}" ]] ;; 
            *) return 0 ;;
        esac
        return $?
    elif [[ "$1" == env && "$2" == LC_ALL=C && "$3" == pacman && "$4" == -Si ]]; then
        return 1
    elif [[ "$1" == runuser ]]; then
        local target="${{@: -1}}"
        printf '%s\\n' "$target" >> "$STATE_DIR/yay-targets"
        : > "$STATE_DIR/installed.$target"
        return 0
    elif [[ "$1" == visudo ]]; then
        return 0
    fi
    echo "Unexpected arch-chroot invocation: $*" >&2
    return 90
}}
install_selected_stack_packages
printf 'YAY_TARGETS_BEGIN\\n'
cat "$STATE_DIR/yay-targets"
'''
            done = self.shell(script)
            self.assertEqual(done.returncode, 0, done.stdout + '\n' + done.stderr)
            self.assertNotIn('FALHA NA INSTALAÇÃO', done.stdout)
            self.assertIn('[AUR 3/3] zsh-theme-powerlevel10k', done.stdout)
            self.assertEqual(done.stdout.split('YAY_TARGETS_BEGIN\n')[-1].splitlines(),
                             ['google-chrome', 'mpc-qt', 'zsh-theme-powerlevel10k'])
            result = Path(work, 'packages.tsv').read_text()
            self.assertNotIn('FALHA NA INSTALAÇÃO', result)
            self.assertNotIn('Etapa:', result)

    def test_invalid_manifest_line_is_rejected_before_any_pacman_call(self):
        with tempfile.TemporaryDirectory() as work:
            from shlex import quote
            script = self.setup_script() + f'''
SELECTED_STACKS[daily]=1
DAILY_PACKAGES+=('FALHA NA INSTALAÇÃO' '64-resolver-stacks')
STATE_DIR={quote(work)}
PACKAGE_RESOLUTION_LOG="$STATE_DIR/packages.tsv"
info() {{ :; }}
die() {{ printf 'REJECTED: %s\\n' "$*" >&2; exit 96; }}
arch-chroot() {{ printf 'UNSAFE_CHROOT_CALL\\n' >> "$STATE_DIR/unsafe"; return 0; }}
install_selected_stack_packages
'''
            done = self.shell(script)
            self.assertEqual(done.returncode, 96, done.stdout + done.stderr)
            self.assertIn('REJECTED:', done.stderr)
            self.assertFalse(Path(work, 'unsafe').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
