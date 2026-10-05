#!/usr/bin/env bash
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*) ;;
    *)
        echo "[ERRO] Execute dentro de uma sessão Cinnamon."
        exit 1
        ;;
esac

echo "============================================================"
echo "       WOLF LINUX - NEMO INTEGRATIONS FIX 1.0.10"
echo "============================================================"
echo

sudo pacman -S --needed --noconfirm \
    nemo-python \
    gnome-disk-utility

sudo install -d /usr/share/nemo-python/extensions

sudo tee /usr/share/nemo-python/extensions/wolf_vscode.py >/dev/null <<'PY'
import shutil
import subprocess

from gi.repository import Nemo, GObject


class WolfVSCodeExtension(GObject.GObject, Nemo.MenuProvider):
    def _code_available(self):
        return shutil.which("code") is not None

    def _open(self, file_info):
        if not self._code_available():
            return

        location = file_info.get_location()
        if location is None:
            return

        path = location.get_path()
        if not path:
            return

        subprocess.Popen(
            ["code", "--new-window", path],
            cwd=path,
            start_new_session=True,
        )

    def get_file_items(self, window, files):
        if not self._code_available() or len(files) != 1:
            return

        file_info = files[0]

        if not file_info.is_directory() or file_info.get_uri_scheme() != "file":
            return

        item = Nemo.MenuItem(
            name="WolfLinux::VSCodeFolder",
            label="Abrir pasta no VS Code",
            tip="Abrir esta pasta em uma nova janela do Visual Studio Code",
        )
        item.connect("activate", lambda *_: self._open(file_info))
        return [item]

    def get_background_items(self, window, current_folder):
        if not self._code_available():
            return

        if current_folder.get_uri_scheme() != "file":
            return

        item = Nemo.MenuItem(
            name="WolfLinux::VSCodeCurrentFolder",
            label="Abrir esta pasta no VS Code",
            tip="Abrir a pasta atual em uma nova janela do Visual Studio Code",
        )
        item.connect("activate", lambda *_: self._open(current_folder))
        return [item]
PY

sudo tee /usr/local/bin/wolf-format-removable >/dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

resolve_device() {
    local input="$1"
    local real_path source target real_target parent disk rm_flag transport

    real_path="$(readlink -f -- "$input" 2>/dev/null || true)"
    [[ -n "$real_path" && -d "$real_path" ]] || return 1

    source="$(findmnt -n -o SOURCE --target "$real_path" 2>/dev/null | head -n1 | xargs)"
    target="$(findmnt -n -o TARGET --target "$real_path" 2>/dev/null | head -n1 | xargs)"

    [[ -n "$source" && -n "$target" ]] || return 1
    source="${source%%\\[*}"
    [[ "$source" == /dev/* ]] || return 1

    real_target="$(readlink -f -- "$target" 2>/dev/null || true)"
    [[ "$real_path" == "$real_target" ]] || return 1

    parent="$(lsblk -n -o PKNAME "$source" 2>/dev/null | head -n1 | xargs)"
    [[ -n "$parent" ]] && disk="/dev/$parent" || disk="$source"

    rm_flag="$(lsblk -dn -o RM "$disk" 2>/dev/null | head -n1 | xargs)"
    transport="$(lsblk -dn -o TRAN "$disk" 2>/dev/null | head -n1 | xargs)"

    case "$transport" in
        usb|mmc) ;;
        *) [[ "$rm_flag" == "1" ]] || return 1 ;;
    esac

    printf '%s\n' "$source"
}

[[ $# -eq 2 ]] || exit 2
device="$(resolve_device "$2")" || exit 1

case "$1" in
    --check)
        printf '%s\n' "$device"
        ;;
    --format)
        exec gnome-disks --block-device "$device" --format-device
        ;;
    *)
        exit 2
        ;;
esac
EOF

sudo chmod 755 /usr/local/bin/wolf-format-removable

sudo tee /usr/share/nemo-python/extensions/wolf_removable_media.py >/dev/null <<'PY'
import os
import subprocess

from gi.repository import Nemo, GObject

HELPER = "/usr/local/bin/wolf-format-removable"


class WolfRemovableMediaExtension(GObject.GObject, Nemo.MenuProvider):
    def _path(self, file_info):
        if file_info is None or file_info.get_uri_scheme() != "file":
            return None

        location = file_info.get_location()
        if location is None:
            return None

        path = location.get_path()
        if not path or not os.path.isdir(path):
            return None

        return path

    def _is_removable_root(self, path):
        try:
            return subprocess.run(
                [HELPER, "--check", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=1.5,
                check=False,
            ).returncode == 0
        except Exception:
            return False

    def _format(self, _menu, path):
        subprocess.Popen([HELPER, "--format", path], start_new_session=True)

    def _item(self, path):
        item = Nemo.MenuItem(
            name="WolfLinux::FormatRemovable",
            label="Formatar mídia removível…",
            tip="Abrir o diálogo seguro de formatação para esta mídia",
        )
        item.connect("activate", self._format, path)
        return item

    def get_file_items(self, window, files):
        if len(files) != 1:
            return
        path = self._path(files[0])
        if self._is_removable_root(path):
            return [self._item(path)]

    def get_background_items(self, window, current_folder):
        path = self._path(current_folder)
        if self._is_removable_root(path):
            return [self._item(path)]
PY

pkill -x nemo 2>/dev/null || true
sleep 1
nohup nemo-desktop >/dev/null 2>&1 &
nohup nemo >/dev/null 2>&1 &
disown || true

echo "[OK] Nemo: VS Code + formatação de mídia configurados."
echo "[INFO] Ejeção/desmontagem continua pelo applet nativo do Cinnamon."
