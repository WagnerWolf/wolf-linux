#!/usr/bin/env bash
set -Eeuo pipefail

ZSHRC="$HOME/.zshrc"

echo "============================================================"
echo "      WOLF LINUX - FASTFETCH STARTUP FIX v0.38"
echo "============================================================"

command -v fastfetch >/dev/null 2>&1 || {
    echo "[INFO] Instalando fastfetch..."
    sudo pacman -S --needed --noconfirm fastfetch
}

[[ -f "$ZSHRC" ]] || {
    echo "[ERRO] $ZSHRC não existe."
    exit 1
}

cp -a "$ZSHRC" "$ZSHRC.wolf-backup-v0.38"

python - "$ZSHRC" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

patterns = [
    r'(?ms)\n?# Wolf Linux Fastfetch v1\n.*?^fi\n?',
    r'(?ms)\n?# Wolf Linux: Fastfetch uma vez antes do primeiro prompt\.\n.*?^fi\n?',
    r'(?ms)\n?# Wolf Linux Fastfetch startup v2\n.*?^fi\n?',
]

for pattern in patterns:
    text = re.sub(pattern, "\n", text, count=1)

block = '''# Wolf Linux Fastfetch startup v2
# Deve ficar antes do instant prompt do Powerlevel10k.
# Para desativar: export WOLF_FASTFETCH=0
if [[ -t 1 && "${WOLF_FASTFETCH:-1}" != "0" ]] &&
   command -v fastfetch >/dev/null 2>&1; then
    fastfetch
    echo
fi

'''

marker = "# Powerlevel10k instant prompt."

if marker in text:
    text = text.replace(marker, block + marker, 1)
else:
    text = block + text

path.write_text(text, encoding="utf-8")
PY

echo
echo "[OK] Fastfetch movido para antes do instant prompt do Powerlevel10k."
echo "Backup: $ZSHRC.wolf-backup-v0.38"
echo
echo "Abra um NOVO terminal para testar."
echo "Ou valide agora com:"
echo "  exec zsh"
