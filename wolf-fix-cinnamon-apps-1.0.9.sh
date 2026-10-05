#!/usr/bin/env bash
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"

case "$DESKTOP" in
    *X-Cinnamon*|*Cinnamon*) ;;
    *)
        echo "[ERRO] Execute este fix dentro de uma sessão Cinnamon."
        exit 1
        ;;
esac

echo "============================================================"
echo "       WOLF LINUX - CINNAMON APPS FIX 1.0.9"
echo "============================================================"
echo

sudo pacman -S --needed --noconfirm \
    xed \
    xreader \
    xviewer \
    galculator \
    gnome-keyring \
    libsecret

set_default() {
    local desktop="$1"
    shift
    local mime

    for mime in "$@"; do
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true

        if command -v gio >/dev/null 2>&1; then
            gio mime "$mime" "$desktop" >/dev/null 2>&1 || true
        fi
    done
}

XED_DESKTOP="org.x.editor.desktop"

if [[ ! -f "/usr/share/applications/$XED_DESKTOP" ]]; then
    echo "[ERRO] Desktop file do Xed não encontrado: $XED_DESKTOP"
    exit 1
fi

# Tipos básicos.
set_default "$XED_DESKTOP" \
    text/plain \
    text/markdown \
    text/x-readme \
    text/x-log \
    application/x-shellscript \
    application/json \
    application/xml \
    text/xml \
    text/x-python \
    text/x-csrc \
    text/x-c++src \
    text/x-java \
    text/x-cmake

# Tudo que o Xed declara saber abrir.
while IFS= read -r mime; do
    [[ -n "$mime" ]] || continue
    set_default "$XED_DESKTOP" "$mime"
done < <(
    sed -n 's/^MimeType=//p' "/usr/share/applications/$XED_DESKTOP" \
        | tr ';' '\n' \
        | sed '/^$/d'
)

# Xviewer para imagens.
if [[ -r /usr/share/applications/xviewer.desktop ]]; then
    while IFS= read -r mime; do
        [[ "$mime" == image/* ]] || continue
        set_default xviewer.desktop "$mime"
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/xviewer.desktop \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

# Calculadora preferida do Cinnamon.
if gsettings list-schemas 2>/dev/null \
    | grep -Fxq 'org.cinnamon.desktop.default-applications.calculator'; then

    gsettings set \
        org.cinnamon.desktop.default-applications.calculator \
        exec \
        'galculator' \
        2>/dev/null || true
fi

# gnome-keyring instalado no meio da sessão não foi iniciado pelo XDG
# autostart; tentamos ativar o Secret Service agora e recomendamos relogin.
systemctl --user start gnome-keyring-daemon.socket >/dev/null 2>&1 || true
gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1 || true

echo
echo "============================================================"
echo "                    RESULTADO"
echo "============================================================"
echo

echo -n "text/plain ....: "
xdg-mime query default text/plain || true

echo -n "text/x-csrc ...: "
xdg-mime query default text/x-csrc || true

echo -n "image/png .....: "
xdg-mime query default image/png || true

echo -n "calculadora ...: "
gsettings get \
    org.cinnamon.desktop.default-applications.calculator \
    exec \
    2>/dev/null || echo "(schema indisponível)"

echo
echo "[OK] Xed, Xviewer, Galculator e GNOME Keyring configurados."
echo "[INFO] Faça logout/login uma vez para o GNOME Keyring entrar"
echo "       normalmente no ciclo de sessão do Cinnamon."
