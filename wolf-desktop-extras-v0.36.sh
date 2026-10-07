#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute este script dentro da sessão MATE."
    exit 1
fi

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
    echo "[ERRO] Wolf Edge Barrier exige sessão X11."
    echo "Sessão atual: ${XDG_SESSION_TYPE:-desconhecida}"
    exit 1
fi

echo "============================================================"
echo "       WOLF LINUX - DESKTOP EXTRAS v0.36"
echo "============================================================"
echo
echo "Será configurado:"
echo "  - resistência no topo da divisa entre monitores"
echo "  - Abrir pasta no VS Code no Caja"
echo "  - SMPlayer como vídeo padrão"
echo "  - Audacious como áudio padrão"
echo "  - thumbnails de vídeo, áudio, WebP, HEIF/AVIF, RAW,"
echo "    EPUB/MOBI, ODF, PDF e executáveis Windows/Wine"
echo

sudo pacman -S --needed --noconfirm \
    python-caja \
    libxfixes \
    xorg-xrandr \
    ffmpegthumbnailer \
    webp-pixbuf-loader \
    glycin \
    libheif \
    libopenraw \
    libwmf \
    gnome-epub-thumbnailer \
    libgsf \
    poppler-glib \
    icoextract \
    python-pillow \
    freetype2

echo
echo "[1/5] Instalando Wolf Edge Barrier..."

tmp_c="$(mktemp --suffix=.c)"
trap 'rm -f "$tmp_c"' EXIT

cat > "$tmp_c" <<'C'
#define _POSIX_C_SOURCE 200809L

#include <X11/Xlib.h>
#include <X11/extensions/Xfixes.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_MONITORS 16
#define MAX_BARRIERS 128

typedef struct {
    int x;
    int y;
    int w;
    int h;
} Monitor;

static volatile sig_atomic_t keep_running = 1;

static void handle_signal(int sig) {
    (void)sig;
    keep_running = 0;
}

static int read_monitors(Monitor *out, int max_count) {
    FILE *fp = popen("xrandr --query 2>/dev/null", "r");
    if (!fp) {
        return 0;
    }

    char line[2048];
    int count = 0;

    while (fgets(line, sizeof(line), fp) && count < max_count) {
        if (strstr(line, " connected ") == NULL) {
            continue;
        }

        char copy[2048];
        snprintf(copy, sizeof(copy), "%s", line);

        char *save = NULL;
        char *token = strtok_r(copy, " \t\r\n", &save);

        while (token) {
            char *end = NULL;
            char *next = NULL;

            long w = strtol(token, &end, 10);

            if (end == token || *end != 'x') {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            long h = strtol(end + 1, &next, 10);

            if (next == end + 1 || (*next != '+' && *next != '-')) {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            long x = strtol(next, &end, 10);

            if (end == next || (*end != '+' && *end != '-')) {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            long y = strtol(end, &next, 10);

            if (next == end || *next != '\0') {
                token = strtok_r(NULL, " \t\r\n", &save);
                continue;
            }

            out[count].x = (int)x;
            out[count].y = (int)y;
            out[count].w = (int)w;
            out[count].h = (int)h;
            count++;
            break;
        }
    }

    pclose(fp);
    return count;
}

static int monitors_equal(const Monitor *a, int na, const Monitor *b, int nb) {
    if (na != nb) {
        return 0;
    }

    for (int i = 0; i < na; i++) {
        if (
            a[i].x != b[i].x ||
            a[i].y != b[i].y ||
            a[i].w != b[i].w ||
            a[i].h != b[i].h
        ) {
            return 0;
        }
    }

    return 1;
}

static void destroy_barriers(
    Display *display,
    PointerBarrier *barriers,
    int *barrier_count
) {
    for (int i = 0; i < *barrier_count; i++) {
        XFixesDestroyPointerBarrier(display, barriers[i]);
    }

    *barrier_count = 0;
    XSync(display, False);
}

static void rebuild_barriers(
    Display *display,
    Window root,
    const Monitor *monitors,
    int monitor_count,
    int barrier_size,
    PointerBarrier *barriers,
    int *barrier_count
) {
    destroy_barriers(display, barriers, barrier_count);

    if (monitor_count < 2 || barrier_size <= 0) {
        return;
    }

    for (int i = 0; i < monitor_count; i++) {
        for (int j = i + 1; j < monitor_count; j++) {
            int boundary_x = 0;
            int adjacent = 0;

            if (monitors[i].x + monitors[i].w == monitors[j].x) {
                boundary_x = monitors[j].x;
                adjacent = 1;
            } else if (monitors[j].x + monitors[j].w == monitors[i].x) {
                boundary_x = monitors[i].x;
                adjacent = 1;
            }

            if (!adjacent) {
                continue;
            }

            int overlap_top =
                monitors[i].y > monitors[j].y
                    ? monitors[i].y
                    : monitors[j].y;

            int bottom_i = monitors[i].y + monitors[i].h;
            int bottom_j = monitors[j].y + monitors[j].h;

            int overlap_bottom =
                bottom_i < bottom_j
                    ? bottom_i
                    : bottom_j;

            if (overlap_bottom <= overlap_top) {
                continue;
            }

            int barrier_bottom = overlap_top + barrier_size;

            if (barrier_bottom > overlap_bottom) {
                barrier_bottom = overlap_bottom;
            }

            if (barrier_bottom <= overlap_top) {
                continue;
            }

            if (*barrier_count >= MAX_BARRIERS) {
                fprintf(stderr, "wolf-edge-barrier: limite de barreiras atingido\n");
                XSync(display, False);
                return;
            }

            /*
             * directions=0 bloqueia a travessia nos dois sentidos.
             * A barreira cobre apenas o topo da divisa; abaixo dela,
             * a passagem entre monitores continua completamente normal.
             */
            barriers[*barrier_count] = XFixesCreatePointerBarrier(
                display,
                root,
                boundary_x,
                overlap_top,
                boundary_x,
                barrier_bottom,
                0,
                0,
                NULL
            );

            (*barrier_count)++;
        }
    }

    XSync(display, False);
}

int main(int argc, char **argv) {
    int barrier_size = 36;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--size") == 0 && i + 1 < argc) {
            barrier_size = atoi(argv[++i]);

            if (barrier_size < 0 || barrier_size > 300) {
                fprintf(stderr, "wolf-edge-barrier: --size deve estar entre 0 e 300\n");
                return 2;
            }
        } else if (strcmp(argv[i], "--help") == 0) {
            printf("Uso: wolf-edge-barrier [--size PIXELS]\n");
            return 0;
        }
    }

    Display *display = XOpenDisplay(NULL);

    if (!display) {
        fprintf(stderr, "wolf-edge-barrier: não foi possível abrir DISPLAY\n");
        return 1;
    }

    int event_base = 0;
    int error_base = 0;

    if (!XFixesQueryExtension(display, &event_base, &error_base)) {
        fprintf(stderr, "wolf-edge-barrier: XFixes não disponível\n");
        XCloseDisplay(display);
        return 1;
    }

    int major = 5;
    int minor = 0;

    if (!XFixesQueryVersion(display, &major, &minor) || major < 5) {
        fprintf(stderr, "wolf-edge-barrier: XFixes >= 5 necessário\n");
        XCloseDisplay(display);
        return 1;
    }

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGHUP, handle_signal);

    Window root = DefaultRootWindow(display);

    Monitor previous[MAX_MONITORS];
    Monitor current[MAX_MONITORS];
    int previous_count = -1;

    PointerBarrier barriers[MAX_BARRIERS];
    int barrier_count = 0;

    while (keep_running) {
        int current_count = read_monitors(current, MAX_MONITORS);

        if (!monitors_equal(previous, previous_count, current, current_count)) {
            rebuild_barriers(
                display,
                root,
                current,
                current_count,
                barrier_size,
                barriers,
                &barrier_count
            );

            memcpy(previous, current, sizeof(current));
            previous_count = current_count;
        }

        sleep(2);
    }

    destroy_barriers(display, barriers, &barrier_count);
    XCloseDisplay(display);
    return 0;
}
C

sudo cc \
    -O2 \
    -Wall \
    -Wextra \
    -std=c11 \
    "$tmp_c" \
    -o /usr/local/bin/wolf-edge-barrier \
    -lX11 \
    -lXfixes

sudo chmod 755 /usr/local/bin/wolf-edge-barrier
sudo install -d /etc/xdg/autostart /etc/wolf-linux

sudo tee /etc/xdg/autostart/wolf-edge-barrier.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Barreira entre monitores
Comment=Protege os cantos superiores entre monitores no MATE/X11
Exec=/usr/local/bin/wolf-edge-barrier --size 36
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

sudo tee /etc/wolf-linux/edge-barrier.conf >/dev/null <<'EOF'
TOP_BARRIER_PIXELS=36
EOF

pkill -x wolf-edge-barrier 2>/dev/null || true
nohup /usr/local/bin/wolf-edge-barrier --size 36 \
    >"$HOME/.cache/wolf-edge-barrier.log" 2>&1 &
disown || true

echo "[OK] Barreiras de 36 px ativadas nas divisas superiores."

echo
echo "[2/5] Integrando VS Code ao Caja..."

sudo install -d /usr/share/caja-python/extensions

sudo tee /usr/share/caja-python/extensions/wolf_vscode.py >/dev/null <<'PY'
import shutil
import subprocess

from gi.repository import Caja, GObject


class WolfVSCodeExtension(GObject.GObject, Caja.MenuProvider):
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

    def _selected_activate(self, menu, file_info):
        self._open(file_info)

    def _background_activate(self, menu, file_info):
        self._open(file_info)

    def get_file_items(self, window, files):
        if not self._code_available() or len(files) != 1:
            return

        file_info = files[0]
        if not file_info.is_directory() or file_info.get_uri_scheme() != "file":
            return

        item = Caja.MenuItem(
            name="WolfLinux::VSCodeFolder",
            label="Abrir pasta no VS Code",
            tip="Abrir esta pasta em uma nova janela do Visual Studio Code",
        )
        item.connect("activate", self._selected_activate, file_info)
        return [item]

    def get_background_items(self, window, current_folder):
        if not self._code_available() or current_folder.get_uri_scheme() != "file":
            return

        item = Caja.MenuItem(
            name="WolfLinux::VSCodeCurrentFolder",
            label="Abrir esta pasta no VS Code",
            tip="Abrir a pasta atual em uma nova janela do Visual Studio Code",
        )
        item.connect("activate", self._background_activate, current_folder)
        return [item]
PY

echo "[OK] Extensão do Caja instalada."

echo
echo "[3/5] Configurando aplicativos padrão..."

set_default() {
    local desktop="$1"
    shift
    local mime

    for mime in "$@"; do
        xdg-mime default "$desktop" "$mime" >/dev/null 2>&1 || true
    done
}

set_default smplayer.desktop \
    video/mp4 video/x-matroska video/webm video/mpeg video/quicktime \
    video/x-msvideo video/x-ms-wmv video/x-flv video/ogg application/x-matroska

set_default audacious.desktop \
    audio/mpeg audio/mp4 audio/aac audio/flac audio/x-flac audio/ogg \
    audio/vorbis audio/x-vorbis+ogg audio/x-wav audio/wav \
    audio/x-mpegurl audio/x-scpls application/xspf+xml \
    application/vnd.apple.mpegurl

if [[ -r /usr/share/applications/smplayer.desktop ]]; then
    while IFS= read -r mime; do
        [[ "$mime" == video/* ]] || continue
        xdg-mime default smplayer.desktop "$mime" >/dev/null 2>&1 || true
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/smplayer.desktop \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

if [[ -r /usr/share/applications/audacious.desktop ]]; then
    while IFS= read -r mime; do
        [[ "$mime" == audio/* ]] || continue
        xdg-mime default audacious.desktop "$mime" >/dev/null 2>&1 || true
    done < <(
        sed -n 's/^MimeType=//p' /usr/share/applications/audacious.desktop \
            | tr ';' '\n' \
            | sed '/^$/d'
    )
fi

echo "Vídeo MP4 ....: $(xdg-mime query default video/mp4 || true)"
echo "Áudio MPEG ...: $(xdg-mime query default audio/mpeg || true)"

echo
echo "[4/5] Configurando previews do Caja..."

if gsettings list-schemas | grep -Fxq 'org.mate.caja.preferences'; then
    if gsettings list-keys org.mate.caja.preferences | grep -Fxq 'show-image-thumbnails'; then
        gsettings set org.mate.caja.preferences show-image-thumbnails 'always'
    fi

    if gsettings list-keys org.mate.caja.preferences | grep -Fxq 'thumbnail-limit'; then
        gsettings set org.mate.caja.preferences thumbnail-limit 68719476736
    fi
fi

rm -rf -- "$HOME/.cache/thumbnails"
mkdir -p "$HOME/.cache/thumbnails"

echo
echo "[5/5] Reiniciando Caja..."
caja -q 2>/dev/null || true
sleep 2
caja --no-default-window >/dev/null 2>&1 &
disown || true

echo
echo "============================================================"
echo "                  CONFIGURAÇÃO CONCLUÍDA"
echo "============================================================"
echo
echo "Teste agora:"
echo "  1. arraste o mouse ao canto superior entre os monitores;"
echo "  2. clique com botão direito numa pasta no Caja;"
echo "  3. clique com botão direito no fundo de uma pasta;"
echo "  4. abra um vídeo e um áudio pelo Caja;"
echo "  5. entre numa pasta com vídeos/EXEs para regenerar miniaturas."
echo
echo "Log do edge barrier:"
echo "  $HOME/.cache/wolf-edge-barrier.log"
echo
echo "Para desativar temporariamente a barreira:"
echo "  pkill wolf-edge-barrier"
