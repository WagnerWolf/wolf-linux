#!/usr/bin/env python3
"""Alpha55: launcher real isolado + PTY e fluxo de etapas (sem disco real)."""
from pathlib import Path
import ast, os, re, subprocess, tempfile, time, unittest, sys
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'live-gui'))
from terminal_engine import InstallerPty, ALLOWED_EXECUTION_MODES

class Alpha55(unittest.TestCase):
    def test_live_launcher_really_dispatches_vm_click(self):
        source=(ROOT/'tests/wolf-customize-iso-profile.sh').read_text()
        match=re.search(r'cat > "\$AIROOT/usr/local/bin/wolf-install" <<\'WRAP\'\n(.*?)\nWRAP',source,re.S)
        self.assertIsNotNone(match)
        with tempfile.TemporaryDirectory() as d:
            t=Path(d); exe=t/'wolf-install'; target=t/'fake-backend'
            target.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@"\n')
            target.chmod(0o755)
            exe.write_text(match.group(1).replace('exec /root/wolf-linux/install/wolf-install.sh "$@"','exec "$WOLF_TEST_TARGET" "$@"'))
            exe.chmod(0o755)
            env=dict(os.environ,WOLF_TEST_TARGET=str(target))
            result=subprocess.run([str(exe),'--execute-gui-plan-vm-click','/tmp/plano.json'],env=env,capture_output=True,text=True,timeout=5)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.splitlines(),['--execute-gui-plan-vm-click','/tmp/plano.json'])
            reject=subprocess.run([str(exe),'--execute-gui=plan-vm-click','/tmp/plano.json'],env=env,capture_output=True,text=True,timeout=5)
            self.assertEqual(reject.returncode,2)
    def test_gui_pty_mode_runs_interactively_without_external_qterminal(self):
        self.assertIn('--execute-gui-plan-vm-click',ALLOWED_EXECUTION_MODES)
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); mock=root/'sudo'; plan=root/'plan.json'; plan.write_text('{}')
            mock.write_text('''#!/usr/bin/env bash
[[ "$1" == '-n' && "$2" == 'wolf-install' && "$3" == '--execute-gui-plan-vm-click' && "$4" == "$EXPECTED_PLAN" ]] || exit 93
printf 'Senha de teste: '
read -r answer
[[ "$answer" == 'teste' ]] || exit 94
printf '\\nEXECUTOR-MOCK-OK\\n'
''')
            mock.chmod(0o755)
            oldpath=os.environ.get('PATH',''); oldexp=os.environ.get('EXPECTED_PLAN')
            os.environ['PATH']=str(root)+os.pathsep+oldpath;os.environ['EXPECTED_PLAN']=str(plan)
            e=InstallerPty()
            try:
                e.start(plan,mode='--execute-gui-plan-vm-click')
                text=''; deadline=time.monotonic()+4
                while 'Senha de teste' not in text and time.monotonic()<deadline:
                    new,_=e.read();text+=new;time.sleep(0.02)
                self.assertIn('Senha de teste',text)
                e.send('teste')
                deadline=time.monotonic()+4
                while 'EXECUTOR-MOCK-OK' not in text and time.monotonic()<deadline:
                    new,_=e.read();text+=new;time.sleep(0.02)
                self.assertIn('EXECUTOR-MOCK-OK',text)
                self.assertEqual(e.proc.wait(timeout=5),0)
            finally:
                e.close_read();os.environ['PATH']=oldpath
                if oldexp is None:os.environ.pop('EXPECTED_PLAN',None)
                else:os.environ['EXPECTED_PLAN']=oldexp
    def test_keyboard_first_and_no_preset_mode(self):
        src=(ROOT/'live-gui/preview/app.py').read_text()
        ast.parse(src)
        self.assertIn('self.mode = None',src)
        self.assertNotIn("self.mode_changed('reuse')",src)
        self.assertIn('self.pages.setCurrentIndex(2)  # etapa inicial: teclado',src)
        self.assertIn('Selecione um tipo de instalação à esquerda.',src)
        self.assertIn('self.build_terminal_page()',src)
        self.assertIn("engine.start(plan, mode='--execute-gui-plan-vm-click')",src)
        self.assertNotIn("QProcess.startDetached(terminal, ['-e', wrapper",src)
        self.assertIn('self._pty_timer.start(200)',src)
        self.assertIn('self.terminal_input',src)
    def test_bash_exec_guards_and_two_click_cleanup(self):
        src=(ROOT/'install/wolf-install.sh').read_text()
        self.assertIn('--execute-gui-plan-vm-click)',src)
        self.assertIn('GUI_VM_CLICK_CONFIRMED=1',src)
        self.assertIn('revalidate_gui_vm_target',src)
        self.assertIn('if (( GUI_VM_CLICK_CONFIRMED == 1 )); then\n            # Consentimento GUI',src)
        self.assertIn('cmp -s "$current" "$HOME_CLEAN_LIST_FILE"',src)
        self.assertIn('stage "10-preparar-disco" prepare_erase_disk',src)

if __name__ == '__main__':unittest.main(verbosity=2)
