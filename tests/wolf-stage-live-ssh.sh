#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
PROFILE="${WOLF_ISO_PROFILE:-$PROJECT/iso-profile}"
AIROOT="$PROFILE/airootfs"
PACKAGES_FILE="$PROFILE/packages.x86_64"
PROFILEDEF="$PROFILE/profiledef.sh"
SSH_SRC="$PROJECT/tests/wolf-enable-ssh-live.sh"

[[ -d "$PROFILE" ]] || { echo "[ERRO] Perfil Archiso não encontrado: $PROFILE" >&2; exit 1; }
[[ -f "$SSH_SRC" ]] || { echo "[ERRO] Helper SSH fonte ausente: $SSH_SRC" >&2; exit 1; }
[[ -f "$PACKAGES_FILE" ]] || { echo "[ERRO] packages.x86_64 ausente: $PACKAGES_FILE" >&2; exit 1; }
[[ -f "$PROFILEDEF" ]] || { echo "[ERRO] profiledef.sh ausente: $PROFILEDEF" >&2; exit 1; }

mkdir -p \
    "$AIROOT/usr/local/bin" \
    "$AIROOT/root/wolf-linux/tests"

install -m 0755 "$SSH_SRC" "$AIROOT/usr/local/bin/wolf-enable-ssh-live"
install -m 0755 "$SSH_SRC" "$AIROOT/root/wolf-linux/tests/wolf-enable-ssh-live.sh"
ln -sfn wolf-enable-ssh-live "$AIROOT/usr/local/bin/wolf-ssh"

grep -Fxq openssh "$PACKAGES_FILE" || printf '%s\n' openssh >> "$PACKAGES_FILE"

python - "$PROFILEDEF" <<'PYCODE'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text()
required = {
    '/usr/local/bin/wolf-enable-ssh-live': '0:0:755',
    '/root/wolf-linux/tests/wolf-enable-ssh-live.sh': '0:0:755',
}
m = re.search(r'file_permissions=\(\s*(.*?)\s*\)', t, flags=re.S)
if m:
    block = m.group(0)
    for path, mode in required.items():
        pattern = re.compile(rf'^\s*\["{re.escape(path)}"\]="[^"]*"\s*$', flags=re.M)
        entry = f'  ["{path}"]="{mode}"'
        if pattern.search(block):
            block = pattern.sub(entry, block)
        else:
            block = block[:-1].rstrip() + '\n' + entry + '\n)'
    t = t[:m.start()] + block + t[m.end():]
else:
    t += '\nfile_permissions=(\n'
    for path, mode in required.items():
        t += f'  ["{path}"]="{mode}"\n'
    t += ')\n'
p.write_text(t)
PYCODE

[[ -x "$AIROOT/usr/local/bin/wolf-enable-ssh-live" ]] || {
    echo "[ERRO] Staging SSH: executável não foi criado no airootfs." >&2
    exit 1
}
[[ -L "$AIROOT/usr/local/bin/wolf-ssh" ]] || {
    echo "[ERRO] Staging SSH: alias wolf-ssh não foi criado." >&2
    exit 1
}
grep -Fxq openssh "$PACKAGES_FILE" || {
    echo "[ERRO] Staging SSH: openssh não entrou em packages.x86_64." >&2
    exit 1
}

printf '[OK] SSH live staged: %s\n' "$AIROOT/usr/local/bin/wolf-enable-ssh-live"
