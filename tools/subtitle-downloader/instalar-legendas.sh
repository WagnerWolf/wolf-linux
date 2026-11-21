#!/usr/bin/env bash
set -euo pipefail
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if (( EUID == 0 )); then echo '[ERRO] Execute como usuario normal, sem sudo.' >&2; exit 1; fi
case "${1:---install}" in
 --status) exec /usr/bin/python3 "$SELF/legendas/deploy.py" --status ;;
 --undo)
   read -r -p 'Restaurar a integracao de legendas anterior? [s/N] ' res
   [[ "$res" == [sS] ]] || exit 0
   exec /usr/bin/python3 "$SELF/legendas/deploy.py" --undo ;;
 --install) ;;
 *) echo 'Uso: ./instalar-legendas.sh [--status|--install|--undo]' >&2; exit 2 ;;
esac
command -v pacman >/dev/null 2>&1 || { echo '[ERRO] Requer Arch Linux / Wolf Linux.'; exit 1; }
echo 'Wolf Subtitle Downloader — restauracao 0.3 + menus KDE/Wayland'
echo 'Dependencias oficiais e, se necessario, Subliminal 2.8.0 do PyPI (ambiente isolado).'
read -r -p 'Instalar e ativar no Dolphin? [s/N] ' res
[[ "$res" == [sS] ]] || exit 0
needed=(python pyside6 mediainfo libnotify libsecret gnome-keyring)
missing=()
for pkg in "${needed[@]}"; do
  pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if (( ${#missing[@]} )); then
  echo "[DEPENDENCIAS] Requer pacman -S --needed ${missing[*]}"
  sudo pacman -S --needed "${missing[@]}"
fi
/usr/bin/python3 -c 'from PySide6.QtWidgets import QApplication' || {
  echo '[ERRO] PySide6 ausente apesar da instalacao.' >&2; exit 1;
}
command -v secret-tool >/dev/null || { echo '[ERRO] libsecret/secret-tool indisponivel.' >&2; exit 1; }
APPDIR="$HOME/.local/share/wolf-subtitle-downloader"
if [[ -L "$APPDIR" ]]; then echo '[ERRO] Caminho do aplicativo nao pode ser link simbolico.' >&2; exit 1; fi
mkdir -p "$APPDIR"
if [[ ! -x "$APPDIR/.venv/bin/python" ]]; then
  /usr/bin/python3 -m venv "$APPDIR/.venv"
fi
VENV_PY="$APPDIR/.venv/bin/python"
if ! "$VENV_PY" -c 'from importlib.metadata import version; assert version("subliminal")=="2.8.0"; import subliminal; from babelfish import Language; Language.fromietf("pt-BR")' >/dev/null 2>&1; then
  echo '[PYPI] Instalando Subliminal 2.8.0 no ambiente isolado, como usuario comum...'
  "$VENV_PY" -m pip install --disable-pip-version-check 'subliminal==2.8.0'
fi
"$VENV_PY" -c 'import subliminal; from babelfish import Language; print("[OK] Subliminal instalado |", Language.fromietf("pt-BR"))'
/usr/bin/python3 "$SELF/legendas/deploy.py" --install
if command -v kbuildsycoca6 >/dev/null 2>&1; then kbuildsycoca6 >/dev/null 2>&1 || true; fi
