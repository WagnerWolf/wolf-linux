#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" == *MATE* ]] || {
    echo "[ERRO] Execute dentro da sessão MATE."
    exit 1
}

[[ "${XDG_SESSION_TYPE:-}" == "x11" ]] || {
    echo "[ERRO] Este fix foi projetado para MATE/X11."
    exit 1
}

echo "============================================================"
echo "        WOLF LINUX - FINAL POLISH v0.37"
echo "============================================================"

sudo pacman -S --needed --noconfirm \
    gnome-keyring libsecret fastfetch libxfixes xorg-xrandr \
    xorg-xinput xf86-input-libinput

echo
echo "[1/4] GNOME Keyring..."
systemctl --user enable --now gnome-keyring-daemon.socket >/dev/null 2>&1 || true
echo "[OK] Secret Service configurado."

echo
echo "[2/4] Fastfetch Wolf Linux..."
sudo install -d /usr/share/wolf-linux/fastfetch
install -d "$HOME/.config/fastfetch"

sudo tee /usr/share/wolf-linux/fastfetch/wolf-linux.txt >/dev/null <<'EOF'
             ⣀ ⣠ ⢀
         ⣀⠄  ⢧⡀⢩⢀⡼  ⠠⣀
       ⣠⠞⠁⣀⣤⢶⣾⣿⠟⣿⣿⣶⣦⣀ ⠙⢦⡀
     ⢠⡾⠁⣠⠞⣿⠟⢛⣿⣿⣿⣿⣿⣿⣿⢿⣷⣄⠈⢻⣄
    ⢠⣿⠁⣰⠋⡰⣯⣶⣿⣿⣿⣿⣿⡿⣿⣷⡎⣿⣿⣧ ⣿⡆
    ⢻⡏⢠⡯⣤⣿⣿⣟⠻⢿⡿⠋⣴⣻⣿⡿⣠⣿⣟⣿⡆⢸⣿⡀
    ⣼⣇⢸⡇⣕⣿⣿⣿⣠⡟⠁⢰⢿⣿⣿⢣⣿⣿⣿⣿⡇⢸⣿⠁
  ⢀⡌ ⣿⡈⣿⣽⣿⣆⢀⣞⣅⡐⢠⠟⣿⠁⢠⣿⣿⣧⣿⢃⣿⠇⢱⡀
   ⠹⡀⠘⢷⡜⢿⡿⠡⠛⠉⠉⣻⣾ ⠈⠻⣄⢻⣿⣿⢏⣾⠃⢀⡞
    ⠙⣴⠃⠛⠮⠵⢊⣀⣀ ⠙⡟⣷⣦ ⢙⣯⠻⣵⢛⠊⣦⠎
    ⠉⠙⣄⠤⣁⠚⠋⠉⠹⣷⡄ ⢨⢿⣾ ⢹⠃⣈⡠⢢⠏⠉
      ⠚⢧ ⣽⠷⢦⣄ ⠙⣰⠈⠸⢋⡴⠾⣯⠁⡰⠛
        ⠑⠻⣄ ⠙⢷⡀⠹⢀⡼⠛ ⣠⠾⠊
              ⠱ ⠘

              WOLF LINUX
EOF

cat > "$HOME/.config/fastfetch/config.jsonc" <<'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "file-raw",
        "source": "/usr/share/wolf-linux/fastfetch/wolf-linux.txt",
        "padding": { "left": 1, "right": 3 }
    },
    "display": {
        "separator": "  ",
        "color": { "keys": "white", "title": "white" },
        "key": { "width": 11 }
    },
    "modules": [
        "title", "separator", "os", "host", "kernel", "uptime",
        "packages", "shell", "display", "de", "wm", "wmtheme",
        "theme", "icons", "terminal", "cpu", "gpu", "memory",
        "disk", "localip"
    ]
}
EOF

if ! grep -Fq '# Wolf Linux Fastfetch v1' "$HOME/.zshrc" 2>/dev/null; then
cat >> "$HOME/.zshrc" <<'EOF'

# Wolf Linux Fastfetch v1
# Para desativar: export WOLF_FASTFETCH=0
if [[ -o interactive && -t 1 && "${WOLF_FASTFETCH:-1}" != "0" ]] &&
   command -v fastfetch >/dev/null 2>&1; then
    autoload -Uz add-zsh-hook
    _wolf_fastfetch_once() {
        add-zsh-hook -d precmd _wolf_fastfetch_once
        fastfetch
        echo
    }
    add-zsh-hook precmd _wolf_fastfetch_once
fi
EOF
fi
echo "[OK] Fastfetch configurado."

echo
echo "[3/4] Mouse sem aceleração..."
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

sudo tee /usr/local/bin/wolf-disable-mouse-accel.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -u
sleep 2
command -v xinput >/dev/null 2>&1 || exit 0

while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    props="$(xinput list-props "$id" 2>/dev/null || true)"
    grep -q 'libinput Tapping Enabled' <<<"$props" && continue

    if grep -q 'libinput Accel Profile Enabled' <<<"$props"; then
        profile_line="$(grep -m1 'libinput Accel Profile Enabled (' <<<"$props" || true)"
        values="${profile_line##*:}"
        values="$(tr -d '[:space:]' <<<"$values")"

        case "$values" in
            *,*,*) xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 0 >/dev/null 2>&1 || true ;;
            *,*)   xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1   >/dev/null 2>&1 || true ;;
        esac
    fi

    if grep -q 'libinput Accel Speed' <<<"$props"; then
        xinput set-prop "$id" 'libinput Accel Speed' 0 >/dev/null 2>&1 || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
EOF
sudo chmod 755 /usr/local/bin/wolf-disable-mouse-accel.sh

sudo tee /etc/xdg/autostart/wolf-disable-mouse-accel.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Mouse sem aceleração
Comment=Força perfil flat do libinput para mice no MATE/X11
Exec=/usr/local/bin/wolf-disable-mouse-accel.sh
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

while IFS= read -r id; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    props="$(xinput list-props "$id" 2>/dev/null || true)"
    grep -q 'libinput Tapping Enabled' <<<"$props" && continue
    if grep -q 'libinput Accel Profile Enabled' <<<"$props"; then
        profile_line="$(grep -m1 'libinput Accel Profile Enabled (' <<<"$props" || true)"
        values="${profile_line##*:}"
        values="$(tr -d '[:space:]' <<<"$values")"

        case "$values" in
            *,*,*) xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1 0 >/dev/null 2>&1 || true ;;
            *,*)   xinput set-prop "$id" 'libinput Accel Profile Enabled' 0 1   >/dev/null 2>&1 || true ;;
        esac
    fi
    if grep -q 'libinput Accel Speed' <<<"$props"; then
        xinput set-prop "$id" 'libinput Accel Speed' 0 >/dev/null 2>&1 || true
    fi
done < <(xinput list --id-only 2>/dev/null || true)
echo "[OK] AccelProfile=flat e AccelSpeed=0."

echo
echo "[4/4] Edge Barrier topo + base..."
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

            int top_end = overlap_top + barrier_size;

            if (top_end > overlap_bottom) {
                top_end = overlap_bottom;
            }

            if (top_end > overlap_top) {
                if (*barrier_count >= MAX_BARRIERS) {
                    fprintf(stderr, "wolf-edge-barrier: limite de barreiras atingido\n");
                    XSync(display, False);
                    return;
                }

                barriers[*barrier_count] = XFixesCreatePointerBarrier(
                    display,
                    root,
                    boundary_x,
                    overlap_top,
                    boundary_x,
                    top_end,
                    0,
                    0,
                    NULL
                );
                (*barrier_count)++;
            }

            int bottom_start = overlap_bottom - barrier_size;

            if (bottom_start < top_end) {
                bottom_start = top_end;
            }

            if (bottom_start < overlap_bottom) {
                if (*barrier_count >= MAX_BARRIERS) {
                    fprintf(stderr, "wolf-edge-barrier: limite de barreiras atingido\n");
                    XSync(display, False);
                    return;
                }

                barriers[*barrier_count] = XFixesCreatePointerBarrier(
                    display,
                    root,
                    boundary_x,
                    bottom_start,
                    boundary_x,
                    overlap_bottom,
                    0,
                    0,
                    NULL
                );
                (*barrier_count)++;
            }
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

sudo cc -O2 -Wall -Wextra -std=c11 "$tmp_c" \
    -o /usr/local/bin/wolf-edge-barrier -lX11 -lXfixes
sudo chmod 755 /usr/local/bin/wolf-edge-barrier

sudo tee /etc/xdg/autostart/wolf-edge-barrier.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Barreira entre monitores
Comment=Protege os cantos superiores e inferiores entre monitores no MATE/X11
Exec=/usr/local/bin/wolf-edge-barrier --size 36
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

sudo install -d /etc/wolf-linux
sudo tee /etc/wolf-linux/edge-barrier.conf >/dev/null <<'EOF'
TOP_BARRIER_PIXELS=36
BOTTOM_BARRIER_PIXELS=36
EOF

pkill -x wolf-edge-barrier 2>/dev/null || true
mkdir -p "$HOME/.cache"
nohup /usr/local/bin/wolf-edge-barrier --size 36 \
    >"$HOME/.cache/wolf-edge-barrier.log" 2>&1 &
disown || true

echo "[OK] Barreiras superior e inferior ativas."

echo
echo "Abra um NOVO terminal para ver o Fastfetch Wolf Linux."
echo "A regra persistente do mouse entra com certeza no próximo login."
