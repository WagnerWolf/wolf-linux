#!/usr/bin/env bash
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
SESSION="${XDG_SESSION_TYPE:-unknown}"

case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*) ;;
    *)
        echo "[ERRO] Execute dentro de uma sessão Cinnamon."
        exit 1
        ;;
esac

echo "============================================================"
echo "       WOLF LINUX - CINNAMON POLISH FIX 1.0.17"
echo "============================================================"
echo "Sessão atual: $SESSION"
echo

sudo pacman -S --needed --noconfirm \
    vlc \
    vlc-plugins-all \
    xarchiver \
    flameshot \
    gnome-keyring \
    libsecret \
    seahorse \
    xdg-desktop-portal \
    xdg-desktop-portal-xapp \
    xdg-desktop-portal-gtk \
    xorg-xinput \
    gnome-disk-utility

echo "[1/8] VLC como player de vídeo..."

set_default() {
    local desktop="$1"
    shift
    local mime

    for mime in "$@"; do
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
        gio mime "$mime" "$desktop" >/dev/null 2>&1 || true
    done
}

set_default vlc.desktop \
    video/mp4 \
    video/x-matroska \
    video/webm \
    video/mpeg \
    video/quicktime \
    video/x-msvideo \
    video/x-ms-wmv \
    video/x-flv \
    video/ogg \
    application/x-matroska

if [[ -r /usr/share/applications/vlc.desktop ]]; then
    while IFS= read -r mime; do
        case "$mime" in
            video/*|application/x-matroska)
                set_default vlc.desktop "$mime"
                ;;
        esac
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/vlc.desktop \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

echo "[2/8] Xarchiver como gerenciador de arquivos compactados..."

if [[ -r /usr/share/applications/xarchiver.desktop ]]; then
    while IFS= read -r mime; do
        [[ -n "$mime" ]] || continue
        set_default xarchiver.desktop "$mime"
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/xarchiver.desktop \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

echo "[3/8] Dark mode / portal..."

sudo install -d /etc/xdg/xdg-desktop-portal

sudo tee /etc/xdg/xdg-desktop-portal/x-cinnamon-portals.conf >/dev/null <<'EOF'
[preferred]
default=xapp;gtk;
org.freedesktop.impl.portal.Settings=xapp;gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
EOF

gsettings set org.x.apps.portal color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
gsettings set org.cinnamon.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true

systemctl --user restart \
    xdg-desktop-portal-xapp.service \
    xdg-desktop-portal-gtk.service \
    xdg-desktop-portal.service \
    >/dev/null 2>&1 || true

sleep 1

echo -n "Portal color-scheme: "
gdbus call --session \
    --dest org.freedesktop.portal.Desktop \
    --object-path /org/freedesktop/portal/desktop \
    --method org.freedesktop.portal.Settings.Read \
    org.freedesktop.appearance \
    color-scheme \
    2>/dev/null || echo "(não foi possível consultar)"

echo "[4/8] GNOME Keyring / VS Code..."

# O pacote SDDM do Arch já traz integração PAM com GNOME Keyring.
# A 1.0.14 procurava apenas linhas sem o prefixo '-' e, por isso, podia
# acrescentar duplicatas às linhas nativas do pacote. Removemos apenas as
# duplicatas exatas que a versão anterior criava quando as linhas nativas
# já estão presentes.
if [[ -f /etc/pam.d/sddm ]]; then
    sudo cp -an /etc/pam.d/sddm /etc/pam.d/sddm.wolf-backup || true

    if grep -Eq '^-auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so([[:space:]]|$)' /etc/pam.d/sddm; then
        sudo sed -i '/^auth optional pam_gnome_keyring\.so$/d' /etc/pam.d/sddm
    fi

    if grep -Eq '^-session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so[[:space:]]+auto_start([[:space:]]|$)' /etc/pam.d/sddm; then
        sudo sed -i '/^session optional pam_gnome_keyring\.so auto_start$/d' /etc/pam.d/sddm
    fi

    # Fallback apenas para instalações cujo SDDM realmente não forneça
    # integração com GNOME Keyring. Aceitamos tanto linhas com '-' quanto
    # sem '-' para não duplicar configurações válidas.
    grep -Eq '^-?auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so([[:space:]]|$)' /etc/pam.d/sddm \
        || printf '\n-auth optional pam_gnome_keyring.so\n' \
            | sudo tee -a /etc/pam.d/sddm >/dev/null

    grep -Eq '^-?session[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so[[:space:]]+auto_start([[:space:]]|$)' /etc/pam.d/sddm \
        || printf -- '-session optional pam_gnome_keyring.so auto_start\n' \
            | sudo tee -a /etc/pam.d/sddm >/dev/null
fi

# Sincroniza a senha do keyring quando a senha UNIX for alterada.
if [[ -f /etc/pam.d/passwd ]]; then
    grep -Eq '^-?password[[:space:]]+optional[[:space:]]+pam_gnome_keyring\.so([[:space:]]|$)' /etc/pam.d/passwd \
        || printf '\npassword optional pam_gnome_keyring.so\n' \
            | sudo tee -a /etc/pam.d/passwd >/dev/null
fi

# O pacote Arch do gnome-keyring já inclui Cinnamon no autostart nativo do
# Secret Service. Removemos um eventual launcher experimental da 1.0.15 e
# só criamos fallback local se uma versão futura do pacote não listar
# Cinnamon no OnlyShowIn.
sudo rm -f /etc/xdg/autostart/wolf-gnome-keyring-secrets.desktop

KEYRING_AUTOSTART=/etc/xdg/autostart/gnome-keyring-secrets.desktop
if [[ -r "$KEYRING_AUTOSTART" ]]; then
    if grep -Eq '^OnlyShowIn=.*Cinnamon' "$KEYRING_AUTOSTART"; then
        rm -f "$HOME/.config/autostart/wolf-gnome-keyring-secrets.desktop"
    else
        mkdir -p "$HOME/.config/autostart"
        cp -f "$KEYRING_AUTOSTART" \
            "$HOME/.config/autostart/wolf-gnome-keyring-secrets.desktop"
        sed -i '/^OnlyShowIn=/d' \
            "$HOME/.config/autostart/wolf-gnome-keyring-secrets.desktop"
    fi
fi

dbus-update-activation-environment --systemd \
    DISPLAY \
    XAUTHORITY \
    WAYLAND_DISPLAY \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE \
    >/dev/null 2>&1 || true

# Não iniciamos socket nem daemon manualmente. No Arch/Cinnamon o fluxo
# nativo é SDDM/PAM + autostart do próprio pacote gnome-keyring.

mkdir -p "$HOME/.vscode"

python - "$HOME/.vscode/argv.json" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
value = '"password-store": "gnome-libsecret"'

if not path.exists():
    path.write_text(
        "{\n  " + value + "\n}\n",
        encoding="utf-8",
    )
    raise SystemExit(0)

text = path.read_text(encoding="utf-8")

# argv.json é JSONC (aceita comentários), então não usamos json.loads aqui.
# Se a chave já existir, apenas trocamos seu valor e preservamos todo o resto.
pattern = re.compile(r'"password-store"\s*:\s*"[^"]*"')
if pattern.search(text):
    text = pattern.sub(value, text, count=1)
else:
    opening = text.find("{")
    closing = text.rfind("}")

    if opening == -1 or closing <= opening:
        text = "{\n  " + value + "\n}\n"
    else:
        body = text[opening + 1:closing]
        has_other_property = bool(re.search(r'"[^"]+"\s*:', body))
        suffix = "," if has_other_property else ""
        insertion = "\n  " + value + suffix + "\n"
        text = text[:opening + 1] + insertion + text[opening + 1:]

path.write_text(text, encoding="utf-8")
PY

echo "[5/8] Flameshot sem tray + Print..."

mkdir -p "$HOME/.config/flameshot"

python - "$HOME/.config/flameshot/flameshot.ini" <<'PY'
from configparser import ConfigParser
from pathlib import Path
import sys

path = Path(sys.argv[1])

def new_parser():
    parser = ConfigParser(interpolation=None)
    # ConfigParser converte nomes de opções para minúsculas por padrão.
    # Flameshot diferencia maiúsculas/minúsculas (contrastOpacity,
    # disabledTrayIcon, etc.), então precisamos preservar o case original.
    parser.optionxform = str
    return parser

cfg = new_parser()

if path.exists():
    try:
        cfg.read(path, encoding="utf-8")
    except Exception:
        cfg = new_parser()

if not cfg.has_section("General"):
    cfg.add_section("General")

# 1.0.14 gravava estas chaves em minúsculas. A 1.0.15 passou a
# preservar o case, mas mantinha as entradas antigas no arquivo.
# Flameshot 14 reconhece somente os nomes camelCase, então removemos
# explicitamente os aliases inválidos deixados pelas versões anteriores.
legacy_lowercase = {
    "contrastopacity",
    "autocloseidledaemon",
    "disabledtrayicon",
    "showstartuplaunchmessage",
}
for key in list(cfg["General"].keys()):
    if key in legacy_lowercase:
        cfg.remove_option("General", key)

# Mantemos valores válidos e explícitos. contrastOpacity usa o padrão
# oficial do Flameshot quando não havia uma versão camelCase prévia.
if not cfg.has_option("General", "contrastOpacity"):
    cfg.set("General", "contrastOpacity", "190")
cfg.set("General", "disabledTrayIcon", "true")
cfg.set("General", "autoCloseIdleDaemon", "true")
cfg.set("General", "showStartupLaunchMessage", "false")

with path.open("w", encoding="utf-8") as f:
    cfg.write(f, space_around_delimiters=False)
PY

pkill -x flameshot >/dev/null 2>&1 || true

for key in \
    screenshot \
    screenshot-clip \
    area-screenshot \
    area-screenshot-clip \
    window-screenshot \
    window-screenshot-clip
do
    if gsettings list-keys \
        org.cinnamon.desktop.keybindings.media-keys \
        2>/dev/null \
        | grep -Fxq "$key"; then

        gsettings set \
            org.cinnamon.desktop.keybindings.media-keys \
            "$key" \
            "[]" \
            2>/dev/null || true
    fi
done

CUSTOM_SCHEMA='org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/wolf-flameshot/'

gsettings set "$CUSTOM_SCHEMA" name 'Flameshot'
gsettings set "$CUSTOM_SCHEMA" command '/usr/bin/flameshot gui'
gsettings set "$CUSTOM_SCHEMA" binding "['Print']"

python - <<'PY'
import ast
import subprocess

schema = "org.cinnamon.desktop.keybindings"
raw = subprocess.run(
    ["gsettings", "get", schema, "custom-list"],
    capture_output=True,
    text=True,
).stdout.strip()

if raw.startswith("@as "):
    raw = raw[4:]

try:
    items = ast.literal_eval(raw)
except Exception:
    items = []

if not isinstance(items, list):
    items = []

if "wolf-flameshot" not in items:
    items.append("wolf-flameshot")

value = "[" + ", ".join(repr(x) for x in items) + "]"
subprocess.run(["gsettings", "set", schema, "custom-list", value])
PY

echo "[6/8] Mouse flat + Cinnamon X11..."

gsettings set org.cinnamon.desktop.peripherals.mouse accel-profile 'flat'
gsettings set org.cinnamon.desktop.peripherals.mouse speed 0.0
gsettings set org.nemo.preferences click-policy 'double' 2>/dev/null || true

sudo install -d /etc/X11/xorg.conf.d

sudo tee /etc/X11/xorg.conf.d/50-wolf-mouse-no-accel.conf >/dev/null <<'EOF'
Section "InputClass"
    Identifier "Wolf Linux - Mouse sem aceleracao"
    MatchIsPointer "on"
    MatchIsTouchpad "off"
    MatchDriver "libinput"

    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
EndSection
EOF

if [[ "$SESSION" == "x11" ]] && command -v xinput >/dev/null 2>&1; then
    while IFS= read -r id; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue

        props="$(xinput list-props "$id" 2>/dev/null || true)"

        if grep -q 'libinput Tapping Enabled' <<<"$props"; then
            continue
        fi

        line="$(grep -m1 'libinput Accel Profile Enabled (' <<<"$props" || true)"

        if [[ -n "$line" ]]; then
            values="${line##*:}"
            values="$(tr -d '[:space:]' <<<"$values")"

            case "$values" in
                *,*,*)
                    xinput set-prop "$id" \
                        'libinput Accel Profile Enabled' \
                        0 1 0 >/dev/null 2>&1 || true
                    ;;
                *,*)
                    xinput set-prop "$id" \
                        'libinput Accel Profile Enabled' \
                        0 1 >/dev/null 2>&1 || true
                    ;;
            esac
        fi

        grep -q 'libinput Accel Speed (' <<<"$props" \
            && xinput set-prop "$id" 'libinput Accel Speed' 0 \
                >/dev/null 2>&1 || true
    done < <(xinput list --id-only 2>/dev/null || true)
fi

# Wolf Linux oferece apenas a sessão Cinnamon X11. Remove as entradas
# Wayland atuais e instala um hook para removê-las novamente após upgrades.
sudo install -d /usr/local/sbin /etc/pacman.d/hooks

sudo tee /usr/local/sbin/wolf-disable-cinnamon-wayland >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

for entry in /usr/share/wayland-sessions/cinnamon*.desktop; do
    rm -f -- "$entry"
done
EOF
sudo chmod 755 /usr/local/sbin/wolf-disable-cinnamon-wayland

sudo tee /etc/pacman.d/hooks/wolf-cinnamon-x11-only.hook >/dev/null <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = cinnamon

[Action]
Description = Wolf Linux: mantendo Cinnamon somente em X11...
When = PostTransaction
Exec = /usr/local/sbin/wolf-disable-cinnamon-wayland
EOF

sudo /usr/local/sbin/wolf-disable-cinnamon-wayland

if [[ -f /usr/share/xsessions/cinnamon.desktop ]]; then
    sudo install -d -o sddm -g sddm /var/lib/sddm

    sudo tee /var/lib/sddm/state.conf >/dev/null <<EOF
[Last]
Session=cinnamon.desktop
User=$USER
EOF

    sudo chown sddm:sddm /var/lib/sddm/state.conf
fi

echo "[7/8] Atalhos do Nemo..."

xdg-user-dirs-update >/dev/null 2>&1 || true
mkdir -p "$HOME/.config/gtk-3.0"
touch "$HOME/.config/gtk-3.0/bookmarks"

add_bookmark() {
    local path="$1"
    local label="$2"
    local line

    [[ -n "$path" && -d "$path" ]] || return 0

    line="file://$path $label"

    grep -Fxq "$line" "$HOME/.config/gtk-3.0/bookmarks" 2>/dev/null \
        || printf '%s\n' "$line" >> "$HOME/.config/gtk-3.0/bookmarks"
}

add_bookmark "$(xdg-user-dir DOCUMENTS 2>/dev/null || true)" "Documentos"
add_bookmark "$(xdg-user-dir DOWNLOAD 2>/dev/null || true)" "Downloads"
add_bookmark "$(xdg-user-dir MUSIC 2>/dev/null || true)" "Música"
add_bookmark "$(xdg-user-dir PICTURES 2>/dev/null || true)" "Imagens"
add_bookmark "$(xdg-user-dir VIDEOS 2>/dev/null || true)" "Vídeos"

echo "[8/8] Verificações..."

echo -n "Sessão atual ........: "
echo "$SESSION"

echo -n "Cinnamon Wayland ....: "
if compgen -G '/usr/share/wayland-sessions/cinnamon*.desktop' >/dev/null; then
    echo "AINDA PRESENTE"
else
    echo "removido (X11-only)"
fi

echo -n "Mouse profile .......: "
gsettings get org.cinnamon.desktop.peripherals.mouse accel-profile || true

echo -n "VLC vídeo/mp4 .......: "
xdg-mime query default video/mp4 || true

echo -n "Archive ZIP .........: "
xdg-mime query default application/zip || true

echo -n "Secret Service ......: "
if busctl --user --no-pager status org.freedesktop.secrets \
    >/dev/null 2>&1; then
    echo "ativo"
else
    echo "não detectado nesta sessão"
fi

echo -n "Login keyring .......: "
if state="$(
    busctl --user get-property \
        org.freedesktop.secrets \
        /org/freedesktop/secrets/collection/login \
        org.freedesktop.Secret.Collection \
        Locked \
        2>/dev/null
)"; then
    case "$state" in
        *false) echo "desbloqueado" ;;
        *true)  echo "BLOQUEADO" ;;
        *)      echo "$state" ;;
    esac
else
    echo "AUSENTE — faça logout/login; se persistir, abra Seahorse e crie o chaveiro Login"
fi

echo -n "VS Code store .......: "
python - "$HOME/.vscode/argv.json" <<'PY'
from pathlib import Path
import json
import sys

try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
print(data.get("password-store", "não configurado"))
PY

echo
echo "============================================================"
echo "                    CONCLUÍDO"
echo "============================================================"
echo
echo "O Wolf Linux agora usa Cinnamon somente em X11."
echo
echo "A entrada Cinnamon Wayland foi removida do SDDM e será removida"
echo "novamente após futuras atualizações do pacote cinnamon."
echo
echo "FAÇA LOGOUT e entre novamente na sessão Cinnamon."
echo
echo "Depois do login X11, teste:"
echo "  echo \$XDG_SESSION_TYPE        # x11"
echo "  tecla Print                   # Flameshot"
echo "  gnome-disks                   # escuro"
echo "  code                          # login persistente"
echo "  xarchiver                     # drag-and-drop"
echo
echo "Se o Chrome continuar piscando mesmo em X11, aí investigamos"
echo "o Chrome/NVIDIA separadamente."
