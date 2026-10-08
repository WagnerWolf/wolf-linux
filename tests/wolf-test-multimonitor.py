#!/usr/bin/env python3
"""Regression tests for layout/script and post-restore manual reconciliation."""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "tools/experimental/wolf-plasma-multimonitor-0.3.sh"
SOURCE = HELPER.read_text(encoding="utf-8")
m = re.search(r"read -r -d '' js <<'JS' \|\| true\n(.*?)\nJS\n", SOURCE, re.S)
if not m:
    raise AssertionError("JS embedded in helper not found")
JS = m.group(1)

NODE = r'''
const fs = require('fs');
const vm = require('vm');
const script = fs.readFileSync(process.argv[2], 'utf8');
function run(caseName, screens, originalPanels, expectedCount, expectedNew, expectError = false) {
  let logs = [];
  let allPanels = [];
  let ids = 0;
  let oldKickoffIcons = [];
  const makeWidget = (type, icon) => ({
    type, currentConfigGroup: [], config: icon ? {icon} : {},
    writeConfig(k,v) { this.config[k] = v; },
    readConfig(k) { return this.config[k] ?? ''; },
    reloadConfig() {}
  });
  for (let p of originalPanels) {
    let widgets = [makeWidget('org.kde.plasma.kickoff', p.icon || '/tmp/custom-wolf.svg'),
                   makeWidget('org.kde.plasma.icontasks')];
    oldKickoffIcons.push(widgets[0].readConfig('icon'));
    allPanels.push({ screen:p.screen, widgets:()=>widgets, addWidget(t) {const w=makeWidget(t); widgets.push(w); return w;} });
  }
  let initialCount = allPanels.length;
  function Panel() {
    const widgets=[];
    this.screen=-1;
    this.widgets=()=>widgets;
    this.addWidget=t=>{const w=makeWidget(t); widgets.push(w);return w;};
    allPanels.push(this);
  }
  const ctx={
    desktops: () => screens.map(screen=>({screen})),
    panels: () => allPanels,
    Panel, gridUnit:10, print: t=>logs.push(String(t)),
    Math
  };
  vm.runInNewContext(script,ctx);
  const gotError=logs.some(t=>t.includes('WOLF_MM_ERROR'));
  if(gotError !== expectError) throw new Error(`${caseName}: unexpected error status: ${logs}`);
  if(allPanels.length !== expectedCount || allPanels.length-initialCount !== expectedNew)
    throw new Error(`${caseName}: unexpected panels: ${allPanels.length} expected ${expectedCount}, new ${allPanels.length-initialCount}`);
  for(let i=0;i<originalPanels.length;i++) {
    if(allPanels[i].widgets()[0].readConfig('icon')!==oldKickoffIcons[i])
      throw new Error(`${caseName}: existing kickoff icon changed`);
  }
  if(!expectError) {
    for(const p of allPanels) {
      const task=p.widgets().find(w=>w.type==='org.kde.plasma.icontasks');
      if(task && task.readConfig('showOnlyCurrentScreen')!==true)
        throw new Error(`${caseName}: task manager is not screen-local`);
    }
  }
  return allPanels;
}
run('single normal', [0], [{screen:0}], 1, 0);
run('single screen temporarily unassigned panel', [0], [{screen:-1}], 1, 0);
run('single ID mismatch', [0], [{screen:3}], 1, 0);
run('single desktop blank', [0], [], 1, 1);
run('single with prior duplicate (never delete)', [0], [{screen:0},{screen:0}], 2, 0);
run('two existing', [0,1], [{screen:0},{screen:1}], 2, 0);
const created=run('two one missing', [0,1], [{screen:0,icon:'/tmp/kept.svg'}], 2, 1);
if(created[1].widgets()[0].readConfig('icon')!=='/tmp/kept.svg')
   throw new Error('new panel failed to inherit existing kickoff icon');
run('two transitional unassigned panel', [0,1], [{screen:-1}], 1, 0, true);
run('two ID mismatch', [0,1], [{screen:2}], 1, 0, true);
run('no screens', [], [{screen:0}], 1, 0, true);
console.log('PASS: 10 JavaScript Plasma panel scenarios');
'''
with tempfile.TemporaryDirectory(prefix="wolf-mm-") as tmp:
    js = Path(tmp)/'script.js'
    runner=Path(tmp)/'test.js'
    js.write_text(JS)
    runner.write_text(NODE)
    subprocess.run(['node',str(runner),str(js)],check=True)
    home=Path(tmp)/'home'
    (home/'.config/wolf-linux').mkdir(parents=True)
    (home/'.local/state').mkdir(parents=True)
    (home/'.config/plasma-org.kde.plasma.desktop-appletsrc').write_text('test=panel-state\n')
    (home/'.config/wolf-linux/plasma-multimonitor.disabled').touch()
    bin_dir=Path(tmp)/'bin'
    bin_dir.mkdir()
    qdbus=bin_dir/'qdbus6'
    qdbus.write_text('#!/bin/sh\nprintf "WOLF_MM_OK: mock\\n"\n')
    qdbus.chmod(0o755)
    env=os.environ.copy()
    env.update({'HOME':str(home),'XDG_CURRENT_DESKTOP':'KDE','XDG_CONFIG_HOME':str(home/'.config'),
                'XDG_STATE_HOME':str(home/'.local/state'),'PATH':str(bin_dir)+':'+env.get('PATH','')})
    p=subprocess.run(['bash',str(HELPER),'apply'],env=env,capture_output=True,text=True)
    assert p.returncode == 3, f'apply while disabled should fail, got {p.returncode} {p.stderr}'
    assert 'desativada' in p.stderr
    p=subprocess.run(['bash',str(HELPER),'reconcile'],env=env,capture_output=True,text=True)
    assert p.returncode == 0, (p.stdout,p.stderr)
    assert 'manual concluída' in p.stdout
    assert (home/'.config/wolf-linux/plasma-multimonitor.disabled').exists()
    latest=(home/'.local/state/wolf-linux/plasma-multimonitor/latest').read_text().strip()
    assert (Path(latest)/'plasma-org.kde.plasma.desktop-appletsrc').is_file()
    print('PASS: manual reconcile works while automatic policy remains disabled and saves backup')
