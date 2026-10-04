#!/usr/bin/env bash
set -Eeuo pipefail

ZSHRC="$HOME/.zshrc"
FASTFETCH_DIR="$HOME/.config/fastfetch"

echo "============================================================"
echo "          WOLF LINUX - TTY FIX v0.41"
echo "============================================================"
echo
echo "Será configurado:"
echo "  - Terminus no console Linux"
echo "  - logo ASCII específica para TTY"
echo "  - Fastfetch próprio para TTY"
echo "  - prompt Zsh simples no TTY"
echo "  - Powerlevel10k mantido apenas nos terminais gráficos"
echo

sudo pacman -S --needed --noconfirm terminus-font fastfetch

if [[ -f /etc/vconsole.conf ]]; then
    sudo sed -i '/^FONT=/d' /etc/vconsole.conf
else
    echo 'KEYMAP=br-abnt2' | sudo tee /etc/vconsole.conf >/dev/null
fi

echo 'FONT=ter-v16n' | sudo tee -a /etc/vconsole.conf >/dev/null

sudo install -d /usr/share/wolf-linux/fastfetch
install -d "$FASTFETCH_DIR"

sudo tee /usr/share/wolf-linux/fastfetch/wolf-linux-ascii.txt >/dev/null <<'EOF'
             /\        /\
            /  \______/  \
           /              \
          /   /\      /\   \
         |   /  \____/  \   |
         |       _  _        |
         |      / \/ \       |
          \     \_/\_/      /
           \      /\       /
            '._  /  \  _.'
               '-.__.-'

              WOLF LINUX
EOF

cat > "$FASTFETCH_DIR/config-tty.jsonc" <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "file-raw",
        "source": "/usr/share/wolf-linux/fastfetch/wolf-linux-ascii.txt",
        "padding": {
            "left": 1,
            "right": 3
        }
    },
    "display": {
        "separator": " : ",
        "color": {
            "keys": "white",
            "title": "white"
        },
        "key": {
            "width": 10
        }
    },
    "modules": [
        "title",
        "separator",
        "os",
        "host",
        "kernel",
        "uptime",
        "packages",
        "shell",
        "cpu",
        "gpu",
        "memory",
        "disk",
        "localip"
    ]
}
EOF

[[ -f "$ZSHRC" ]] || {
    echo "[ERRO] $ZSHRC não existe."
    exit 1
}

cp -a "$ZSHRC" "$ZSHRC.wolf-backup-v0.41"

python - "$ZSHRC" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = re.sub(
    r'(?ms)^# Wolf Linux TTY profile v1\n.*?^# Wolf Linux TTY profile v1 - END\n\n?',
    '',
    text,
    count=1,
)

block = r'''# Wolf Linux TTY profile v1
# Linux virtual consoles do not use Nerd Fonts. Keep TTY output ASCII-only.
if [[ -z "${DISPLAY:-}" &&
      -z "${WAYLAND_DISPLAY:-}" &&
      "${TTY:-}" == /dev/tty* ]]; then

    export ANDROID_HOME=/opt/android-sdk
    export ANDROID_SDK_ROOT=/opt/android-sdk
    export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:$PATH"

    if [[ -t 1 && "${WOLF_FASTFETCH:-1}" != "0" ]] &&
       command -v fastfetch >/dev/null 2>&1; then
        fastfetch --config "$HOME/.config/fastfetch/config-tty.jsonc"
        echo
    fi

    PROMPT='%F{white}%n@%m%f:%F{cyan}%~%f %# '
    RPROMPT=''
    bindkey -e

    [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
        source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

    [[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] &&
        source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh

    [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
        source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

    return
fi
# Wolf Linux TTY profile v1 - END

'''

markers = [
    "# Wolf Linux Fastfetch startup v2",
    "# Powerlevel10k instant prompt.",
    "# ============================================================\n# Wolf Linux - Zsh",
]

for marker in markers:
    if marker in text:
        text = text.replace(marker, block + marker, 1)
        break
else:
    text = block + text

path.write_text(text, encoding="utf-8")
PY

echo
echo "[OK] Perfil TTY gravado."
echo
echo "Configuração de console:"
cat /etc/vconsole.conf
echo
echo "Teste com Ctrl+Alt+F3 e faça login."
echo "A fonte Terminus será aplicada automaticamente no próximo boot."
echo
echo "Se quiser aplicá-la imediatamente dentro do TTY:"
echo "  sudo setfont ter-v16n"
echo
echo "Backup:"
echo "  $ZSHRC.wolf-backup-v0.41"
