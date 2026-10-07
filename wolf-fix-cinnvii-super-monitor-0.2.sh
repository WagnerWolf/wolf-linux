#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

VERSION="0.2"
UUID="CinnVIIStarkMenu@NikoKrause"
APPLET_DIR="${1:-$HOME/.local/share/cinnamon/applets/$UUID}"

log()  { printf '\033[1;34m[Wolf CinnVII]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 não encontrado."
[[ -d "$APPLET_DIR" ]] || die "CinnVIIStarkMenu não encontrado em: $APPLET_DIR"

log "Wolf CinnVII v${VERSION}: aplicando roteamento da tecla Super pelo monitor do ponteiro..."

python3 - "$APPLET_DIR" <<'PY'
from pathlib import Path
import re
import shutil
import sys

root = Path(sys.argv[1])
files = sorted(root.rglob("applet.js"))
if not files:
    print("ERRO: nenhum applet.js encontrado", file=sys.stderr)
    raise SystemExit(2)

# O CinnVII é multiversão. As árvores 3.2/3.4/4.2 têm pequenas diferenças
# de formatação; por exemplo, 3.2 omite ';' no removeHotKey(). Não podemos
# depender de substituições literais de uma única revisão do applet.
old_add_re = re.compile(
    r'Main\.keybindingManager\.addHotKey\(\s*'
    r'"overlay-key-"\s*\+\s*this\.instance_id\s*,\s*'
    r'this\.overlayKey\s*,\s*Lang\.bind\(this,\s*function\(\)\s*\{'
)
old_remove_re = re.compile(
    r'Main\.keybindingManager\.removeHotKey\(\s*'
    r'"overlay-key-"\s*\+\s*this\.instance_id\s*\)[ \t]*;?'
)
new_add_re = re.compile(
    r'Main\.keybindingManager\.addXletHotKey\(\s*this\s*,\s*'
    r'"overlay-key"\s*,\s*this\.overlayKey\s*,\s*'
    r'Lang\.bind\(this,\s*function\(\)\s*\{'
)
new_remove_re = re.compile(
    r'Main\.keybindingManager\.removeXletHotKey\(\s*this\s*,\s*'
    r'"overlay-key"\s*\)[ \t]*;?'
)

new_add = 'Main.keybindingManager.addXletHotKey(this, "overlay-key", this.overlayKey, Lang.bind(this, function() {'
new_remove = 'Main.keybindingManager.removeXletHotKey(this, "overlay-key");'

supported = 0
changed = 0
for path in files:
    text = path.read_text(encoding="utf-8")

    has_old_add = bool(old_add_re.search(text))
    has_old_remove = bool(old_remove_re.search(text))
    has_new_add = bool(new_add_re.search(text))
    has_new_remove = bool(new_remove_re.search(text))

    # Arquivos de outras revisões que não possuem esse hotkey são ignorados.
    if not any((has_old_add, has_old_remove, has_new_add, has_new_remove)):
        continue

    supported += 1

    updated = text
    add_count = 0
    remove_count = 0
    if has_old_add:
        updated, add_count = old_add_re.subn(new_add, updated)
    if has_old_remove:
        updated, remove_count = old_remove_re.subn(new_remove, updated)

    # Aceita também estado parcialmente corrigido por uma execução antiga.
    final_add = bool(new_add_re.search(updated))
    final_remove = bool(new_remove_re.search(updated))
    if not (final_add and final_remove):
        print(
            f"ERRO: não consegui completar o patch em {path} "
            f"(add={final_add}, remove={final_remove})",
            file=sys.stderr,
        )
        raise SystemExit(3)

    if updated == text:
        print(f"OK: {path} já está corrigido")
        continue

    backup = path.with_name(path.name + ".wolf-before-monitor-hotkey.bak")
    if not backup.exists():
        shutil.copy2(path, backup)

    path.write_text(updated, encoding="utf-8")
    changed += 1
    print(f"PATCH: {path} (add={add_count}, remove={remove_count})")

if supported == 0:
    print("ERRO: nenhuma versão compatível do CinnVII foi encontrada", file=sys.stderr)
    raise SystemExit(4)

print(f"RESULT supported={supported} changed={changed}")
PY

ok "CinnVII configurado para usar o hotkey multi-instância nativo do Cinnamon."
echo
printf '%s\n' \
    "A tecla Super agora é encaminhada pelo Cinnamon para a instância do" \
    "CinnVII que estiver no monitor atual (monitor do ponteiro do mouse)."
echo
printf '%s\n' \
    "Para ativar a alteração nesta sessão do Cinnamon X11:" \
    "  Alt+F2  ->  r  ->  Enter" \
    "ou faça logout/login."
