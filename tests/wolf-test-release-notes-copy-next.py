#!/usr/bin/env python3
"""Release-notes copy regression: avoid stale preview names, missing/duplicate docs."""
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess
import shutil

root = Path(__file__).resolve().parents[1]
script = (root / 'preparar_ambiente_wolf_linux.sh').read_text()
candidates = list(root.glob('RELEASE-CANDIDATE-2.2.0-NEXT-PREVIEW*.md'))
assert len(candidates) == 1, candidates
assert candidates[0].name == 'RELEASE-CANDIDATE-2.2.0-NEXT-PREVIEW7.md'
assert 'RELEASE-CANDIDATE-2.2.0-NEXT-PREVIEW1.md' not in script
assert 'RELEASE_CANDIDATES=(' in script
assert script.index('RELEASE_CANDIDATES=(') < script.index('rm -rf -- "$PROJECT"')
assert 'install -m 0644 "$RELEASE_CANDIDATE_SRC" "$PROJECT/$RELEASE_CANDIDATE_NAME"' in script
assert 'cmp -s "$RELEASE_CANDIDATE_SRC" "$PROJECT/$RELEASE_CANDIDATE_NAME"' in script

# Execute the exact preflight and copy blocks extracted from the real preparer.
start = script.index('shopt -s nullglob\nRELEASE_CANDIDATES=')
end = script.index('\nif (( SKIP_DEPS', start)
preflight = script[start:end]
start = script.index('install -m 0644 "$RELEASE_CANDIDATE_SRC"')
end = script.index('\ncp -f "$SELF_DIR/CHANGELOG.md"', start)
copy_block = script[start:end]

with TemporaryDirectory() as d:
    folder = Path(d); source = folder / 'devkit'; source.mkdir()
    project = folder / 'project'; project.mkdir()
    note = source / candidates[0].name
    shutil.copy2(candidates[0], note)
    sentinel = project / 'preexisting-file'; sentinel.write_text('preservar')
    run = """set -Eeuo pipefail
SELF_DIR="$1"; PROJECT="$2"
err(){ echo "[ERRO] $*" >&2; exit 1; }
""" + preflight + '\n' + copy_block
    def invoke():
        return subprocess.run(['bash','-c',run,'wolf',str(source),str(project)],capture_output=True,text=True)
    r = invoke(); assert r.returncode == 0, (r.stdout,r.stderr)
    assert (project / note.name).read_bytes() == note.read_bytes()
    note.unlink()
    r = invoke(); assert r.returncode != 0, (r.stdout,r.stderr)
    assert sentinel.read_text() == 'preservar'
    note.write_text('preview 3')
    (source / 'RELEASE-CANDIDATE-2.2.0-NEXT-PREVIEW2.md').write_text('stale')
    r = invoke(); assert r.returncode != 0, (r.stdout,r.stderr)
    assert sentinel.read_text() == 'preservar'

print('[OK] Notas de release: cópia correta, falha segura quando ausente ou duplicada')
