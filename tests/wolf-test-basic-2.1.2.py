#!/usr/bin/env python3
"""Regression tests: Basic (without gaming/dev), tools labels and user cache."""
import ast
from pathlib import Path
import re
import subprocess
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]

class BasicProfile(unittest.TestCase):
    def test_presets_and_gui_contract(self):
        sys.path.insert(0, str(ROOT/'live-gui'))
        import wolf_plan
        self.assertEqual(wolf_plan.PRESETS['basic'], ('daily',))
        self.assertEqual(wolf_plan.PRESETS['minimal'], ())
        self.assertEqual(wolf_plan.PRESETS['test'], ('daily','gaming','development','extras'))
        src=(ROOT/'live-gui/preview/app.py').read_text()
        ast.parse(src)
        self.assertIn("self.preset_combo.addItem('Basic — escritório, navegador e multimídia', 'basic')",src)
        self.assertIn("'basic': (30, 45)",src)
        self.assertIn('"basic"',(ROOT/'live-gui/wolf_plan.py').read_text())
        self.assertIn("'basic'",(ROOT/'live-gui/wolf_discovery.py').read_text())
        self.assertIn('"Basic": ("daily",)',(ROOT/'live-gui/main.py').read_text())

    def test_bash_preset_actual_stack_selection(self):
        src=(ROOT/'install/wolf-install.sh').read_text()
        start=src.index('valid_stack() {')
        end=src.index('choose_stacks_interactive() {', start)
        functions=src[start:end]
        for preset, expected in [('minimal','nenhuma'),('basic','daily'),('test','daily,gaming,development,extras'),('full','daily,gaming,development,android,containers,extras')]:
            script=("set -eu\ndeclare -A SELECTED_STACKS=()\n"
                    "die() { printf '%s\\n' \"$*\" >&2; exit 6; }\n"
                    +functions+f"\napply_preset {preset}\nselected_stacks_text\n")
            cp=subprocess.run(['bash','-c',script],capture_output=True,text=True)
            self.assertEqual(cp.returncode,0,cp.stderr)
            self.assertEqual(cp.stdout.strip(),expected)

    def test_daily_is_lean_and_chrome_present(self):
        script=("source " + str(ROOT/'package-profiles/packages.conf') + "\n"
                "printf 'DAILY:%s\\n' \"${DAILY_PACKAGES[@]}\"\n"
                "printf 'THIRD:%s\\n' \"${DAILY_THIRD_PARTY_PACKAGES[@]}\"\n"
                "printf 'EXTRA:%s\\n' \"${EXTRA_PACKAGES[@]}\"\n"
                "printf 'KDE:%s\\n' \"${KDE_PACKAGES[@]}\"\n")
        proc=subprocess.run(['bash','-c',script],capture_output=True,text=True)
        self.assertEqual(proc.returncode,0,proc.stderr)
        lines=proc.stdout.splitlines()
        groups={prefix: set(x.split(':',1)[1] for x in lines if x.startswith(prefix+':')) for prefix in ('DAILY','THIRD','EXTRA','KDE')}
        self.assertTrue({'libreoffice-fresh','libreoffice-fresh-pt-br','mpv','ffmpeg','audacious'} <= groups['DAILY'])
        self.assertIn('google-chrome',groups['THIRD'])
        self.assertIn('okular',groups['KDE'])
        self.assertFalse({'gimp','obs-studio','steam','lutris','cmake','android-studio'} & groups['DAILY'])
        self.assertTrue({'gimp','obs-studio','transmission-qt'} <= groups['EXTRA'])

    def test_tool_dialog_guarantees_readable_labels(self):
        src=(ROOT/'live-gui/preview/app.py').read_text()
        body=src.split('    def open_utilities(self):',1)[1].split('    def launch_utility(',1)[0]
        self.assertIn('name = QLabel(title, item)',body)
        self.assertIn('name.setMinimumWidth(145)',body)
        self.assertIn('QSizePolicy.Policy.Expanding',body)
        self.assertIn('action.setFixedWidth(125)',body)
        self.assertIn("layout.addWidget(section('Ferramentas da sessão Live'))",body)
        self.assertNotIn('row.addWidget(text_label(title))',body)

    def test_cache_owner_checked_without_recursive_chown(self):
        src=(ROOT/'install/wolf-install.sh').read_text()
        fn=src.split('prepare_user_cache() {',1)[1].split('configure_user_sudo() {',1)[0]
        self.assertIn('[[ ! -L "$dir" ]]',fn)
        self.assertIn('chown --no-dereference "$uid:$gid" -- "$dir"',fn)
        self.assertNotIn('chown -R',fn)
        self.assertIn('install -d -m 0700 -o "$uid" -g "$gid"',fn)
        self.assertIn('runuser -u "$USERNAME_VALUE"',fn)
        self.assertIn('mktemp "$1/.wolf-access.',fn)
        self.assertIn('    prepare_user_cache\n    ok "Usuário e sudo configurados."',src)
        self.assertIn('ensure_yay() {\n    prepare_user_cache',src)
        self.assertIn('stage "62-usuario-sudo" configure_user_sudo',src)

if __name__ == '__main__': unittest.main(verbosity=2)
