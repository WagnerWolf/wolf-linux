#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

DESKTOP="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
case "$DESKTOP" in *XFCE*|*Xfce*) ;; *) exit 0 ;; esac

set_default() {
    local desktop="$1"; shift
    [[ -r "/usr/share/applications/$desktop" ]] || return 0
    local mime
    for mime in "$@"; do
        [[ -n "$mime" ]] || continue
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
        if command -v gio >/dev/null 2>&1; then
            gio mime "$mime" "$desktop" >/dev/null 2>&1 || true
        fi
    done
}

set_from_desktop() {
    local desktop="$1" filter="${2:-}" prefix=""
    [[ -r "/usr/share/applications/$desktop" ]] || return 0

    if [[ -n "$filter" && "${filter: -2}" == '/*' ]]; then
        prefix="${filter::-1}"
    fi

    while IFS= read -r mime; do
        [[ -n "$mime" ]] || continue
        if [[ -n "$filter" ]]; then
            if [[ -n "$prefix" ]]; then
                [[ "$mime" == "$prefix"* ]] || continue
            else
                [[ "$mime" == "$filter" ]] || continue
            fi
        fi
        set_default "$desktop" "$mime"
    done < <(sed -n 's/^MimeType=//p' "/usr/share/applications/$desktop" | tr ';' '\n' | sed '/^$/d')
}

# Helpers nativos do XFCE.
mkdir -p "$HOME/.config/xfce4"
cat > "$HOME/.config/xfce4/helpers.rc" <<'HELPERS'
WebBrowser=custom-WebBrowser
FileManager=Thunar
TerminalEmulator=xfce4-terminal
HELPERS

mkdir -p "$HOME/.local/share/xfce4/helpers"
cat > "$HOME/.local/share/xfce4/helpers/custom-WebBrowser.desktop" <<'BROWSER'
[Desktop Entry]
NoDisplay=true
Version=1.0
Encoding=UTF-8
Type=X-XFCE-Helper
X-XFCE-Category=WebBrowser
X-XFCE-CommandsWithParameter=/usr/bin/google-chrome-stable "%s"
Icon=google-chrome
Name=Google Chrome
X-XFCE-Commands=/usr/bin/google-chrome-stable
BROWSER

# Pastas.
set_default thunar.desktop inode/directory

# Web.
set_default google-chrome.desktop \
    text/html application/xhtml+xml \
    x-scheme-handler/http x-scheme-handler/https \
    x-scheme-handler/about x-scheme-handler/unknown

# Imagens: usa todos os MIME types anunciados pelo Ristretto.
set_from_desktop org.xfce.ristretto.desktop 'image/*'
set_default org.xfce.ristretto.desktop \
    image/jpeg image/png image/gif image/webp image/bmp image/tiff image/svg+xml image/avif image/heif image/heic

# PDFs/documentos de leitura.
set_from_desktop xreader.desktop
set_default xreader.desktop application/pdf application/postscript application/epub+zip application/x-cbr application/x-cbz

# Texto/código simples.
set_from_desktop org.xfce.mousepad.desktop 'text/*'
set_default org.xfce.mousepad.desktop application/json application/xml application/x-shellscript

# Vídeo e áudio.
set_from_desktop io.github.mpc_qt.mpc-qt.desktop 'video/*'
set_default io.github.mpc_qt.mpc-qt.desktop application/x-matroska
set_from_desktop audacious.desktop 'audio/*'
set_default audacious.desktop application/xspf+xml

# Compactados.
set_from_desktop xarchiver.desktop

# Torrents/magnet.
set_from_desktop transmission-qt.desktop
set_default transmission-qt.desktop application/x-bittorrent x-scheme-handler/magnet

# Escritório.
set_from_desktop libreoffice-writer.desktop
set_from_desktop libreoffice-calc.desktop
set_from_desktop libreoffice-impress.desktop

# LibreOffice anuncia text/plain entre os MIME types possíveis. Como o bloco
# de escritório roda depois do Mousepad, reafirme explicitamente o editor de
# texto simples por último para que .txt nunca caia no Writer.
set_default org.xfce.mousepad.desktop text/plain

# Reforça navegador padrão também pela API do xdg-settings.
xdg-settings set default-web-browser google-chrome.desktop >/dev/null 2>&1 || true
