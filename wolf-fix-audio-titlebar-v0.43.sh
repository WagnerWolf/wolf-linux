#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute dentro da sessão MATE."
    exit 1
fi

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
    echo "[ERRO] Este recurso foi feito para MATE/X11."
    exit 1
fi

echo "============================================================"
echo "     WOLF LINUX - AUDIO + TITLEBAR MOVE v0.43"
echo "============================================================"

sudo pacman -S --needed --noconfirm rtkit libxi xorg-xrandr

echo
echo "[1/2] RTKit..."
sudo systemctl start rtkit-daemon.service 2>/dev/null || true

if systemctl is-active rtkit-daemon.service >/dev/null 2>&1; then
    echo "[OK] rtkit-daemon ativo."
else
    echo "[INFO] RTKit instalado; pode ser ativado sob demanda pelo D-Bus."
fi

echo
echo "[2/2] Instalando mover de janelas por barra de título..."

tmp_c="$(mktemp --suffix=.c)"
trap 'rm -f "$tmp_c"' EXIT

cat > "$tmp_c" <<'C'
#define _POSIX_C_SOURCE 200809L

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAX_MONITORS 16
#define MAX_CLIENTS 4096

typedef struct {
    int x;
    int y;
    int w;
    int h;
} Monitor;

typedef struct {
    Window window;
    int frame_x;
    int frame_y;
    int frame_w;
    int frame_h;
} HitWindow;

static volatile sig_atomic_t keep_running = 1;

static void handle_signal(int sig) {
    (void)sig;
    keep_running = 0;
}

static void sleep_ms(long milliseconds) {
    struct timespec req;
    req.tv_sec = milliseconds / 1000;
    req.tv_nsec = (milliseconds % 1000) * 1000000L;

    while (nanosleep(&req, &req) == -1) {
        if (!keep_running) {
            break;
        }
    }
}

static int parse_geometry_token(
    const char *token,
    int *w,
    int *h,
    int *x,
    int *y
) {
    char *end = NULL;
    char *next = NULL;

    long lw = strtol(token, &end, 10);

    if (end == token || *end != 'x') {
        return 0;
    }

    long lh = strtol(end + 1, &next, 10);

    if (next == end + 1 || (*next != '+' && *next != '-')) {
        return 0;
    }

    long lx = strtol(next, &end, 10);

    if (end == next || (*end != '+' && *end != '-')) {
        return 0;
    }

    long ly = strtol(end, &next, 10);

    if (next == end || *next != '\0') {
        return 0;
    }

    *w = (int)lw;
    *h = (int)lh;
    *x = (int)lx;
    *y = (int)ly;

    return 1;
}

static int compare_monitors(const void *a, const void *b) {
    const Monitor *ma = (const Monitor *)a;
    const Monitor *mb = (const Monitor *)b;

    if (ma->x < mb->x) {
        return -1;
    }

    if (ma->x > mb->x) {
        return 1;
    }

    if (ma->y < mb->y) {
        return -1;
    }

    if (ma->y > mb->y) {
        return 1;
    }

    return 0;
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
            int w = 0;
            int h = 0;
            int x = 0;
            int y = 0;

            if (parse_geometry_token(token, &w, &h, &x, &y)) {
                out[count].x = x;
                out[count].y = y;
                out[count].w = w;
                out[count].h = h;
                count++;
                break;
            }

            token = strtok_r(NULL, " \t\r\n", &save);
        }
    }

    pclose(fp);

    qsort(out, (size_t)count, sizeof(Monitor), compare_monitors);
    return count;
}

static int get_frame_extents(
    Display *display,
    Window window,
    unsigned long *left,
    unsigned long *right,
    unsigned long *top,
    unsigned long *bottom
) {
    Atom prop = XInternAtom(display, "_NET_FRAME_EXTENTS", False);

    Atom actual_type = None;
    int actual_format = 0;
    unsigned long nitems = 0;
    unsigned long bytes_after = 0;
    unsigned char *data = NULL;

    int status = XGetWindowProperty(
        display,
        window,
        prop,
        0,
        4,
        False,
        XA_CARDINAL,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &data
    );

    if (
        status != Success ||
        actual_type != XA_CARDINAL ||
        actual_format != 32 ||
        nitems < 4 ||
        data == NULL
    ) {
        if (data) {
            XFree(data);
        }
        return 0;
    }

    unsigned long *values = (unsigned long *)data;

    *left = values[0];
    *right = values[1];
    *top = values[2];
    *bottom = values[3];

    XFree(data);
    return 1;
}

static int get_client_stack(
    Display *display,
    Window root,
    Window **windows,
    unsigned long *count
) {
    Atom prop = XInternAtom(display, "_NET_CLIENT_LIST_STACKING", False);

    Atom actual_type = None;
    int actual_format = 0;
    unsigned long nitems = 0;
    unsigned long bytes_after = 0;
    unsigned char *data = NULL;

    int status = XGetWindowProperty(
        display,
        root,
        prop,
        0,
        MAX_CLIENTS,
        False,
        XA_WINDOW,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &data
    );

    if (
        status != Success ||
        actual_type != XA_WINDOW ||
        actual_format != 32 ||
        data == NULL
    ) {
        if (data) {
            XFree(data);
        }
        return 0;
    }

    *windows = (Window *)data;
    *count = nitems;
    return 1;
}

static int find_titlebar_window(
    Display *display,
    Window root,
    int pointer_x,
    int pointer_y,
    HitWindow *hit
) {
    Window *clients = NULL;
    unsigned long count = 0;

    if (!get_client_stack(display, root, &clients, &count)) {
        return 0;
    }

    for (long i = (long)count - 1; i >= 0; i--) {
        Window window = clients[i];
        XWindowAttributes attr;

        if (!XGetWindowAttributes(display, window, &attr)) {
            continue;
        }

        if (attr.map_state != IsViewable) {
            continue;
        }

        unsigned long left = 0;
        unsigned long right = 0;
        unsigned long top = 0;
        unsigned long bottom = 0;

        if (!get_frame_extents(
            display,
            window,
            &left,
            &right,
            &top,
            &bottom
        )) {
            continue;
        }

        /*
         * Uma janela CSD costuma não ter barra adicionada pelo Marco.
         * Ignoramos top==0 para não interpretar toolbar da aplicação
         * como barra de título.
         */
        if (top == 0) {
            continue;
        }

        int client_x = 0;
        int client_y = 0;
        Window child = None;

        if (!XTranslateCoordinates(
            display,
            window,
            root,
            0,
            0,
            &client_x,
            &client_y,
            &child
        )) {
            continue;
        }

        int frame_x = client_x - (int)left;
        int frame_y = client_y - (int)top;
        int frame_w = attr.width + (int)left + (int)right;
        int frame_h = attr.height + (int)top + (int)bottom;

        if (
            pointer_x >= frame_x &&
            pointer_x < frame_x + frame_w &&
            pointer_y >= frame_y &&
            pointer_y < client_y
        ) {
            hit->window = window;
            hit->frame_x = frame_x;
            hit->frame_y = frame_y;
            hit->frame_w = frame_w;
            hit->frame_h = frame_h;

            XFree(clients);
            return 1;
        }
    }

    XFree(clients);
    return 0;
}

static long intersection_area(
    int ax,
    int ay,
    int aw,
    int ah,
    const Monitor *m
) {
    int x1 = ax > m->x ? ax : m->x;
    int y1 = ay > m->y ? ay : m->y;

    int ax2 = ax + aw;
    int ay2 = ay + ah;
    int mx2 = m->x + m->w;
    int my2 = m->y + m->h;

    int x2 = ax2 < mx2 ? ax2 : mx2;
    int y2 = ay2 < my2 ? ay2 : my2;

    if (x2 <= x1 || y2 <= y1) {
        return 0;
    }

    return (long)(x2 - x1) * (long)(y2 - y1);
}

static int find_source_monitor(
    const Monitor *monitors,
    int count,
    const HitWindow *hit
) {
    long best_area = -1;
    int best = 0;

    for (int i = 0; i < count; i++) {
        long area = intersection_area(
            hit->frame_x,
            hit->frame_y,
            hit->frame_w,
            hit->frame_h,
            &monitors[i]
        );

        if (area > best_area) {
            best_area = area;
            best = i;
        }
    }

    return best;
}

static int clamp_int(int value, int minimum, int maximum) {
    if (maximum < minimum) {
        return minimum;
    }

    if (value < minimum) {
        return minimum;
    }

    if (value > maximum) {
        return maximum;
    }

    return value;
}

static int project_axis(
    int position,
    int source_origin,
    int source_size,
    int target_origin,
    int target_size,
    int window_size
) {
    int source_available = source_size - window_size;
    int target_available = target_size - window_size;

    if (target_available <= 0) {
        return target_origin;
    }

    if (source_available <= 0) {
        return target_origin + target_available / 2;
    }

    int relative = position - source_origin;
    relative = clamp_int(relative, 0, source_available);

    long projected =
        (long)relative * (long)target_available / (long)source_available;

    return target_origin + (int)projected;
}

static int window_has_state(
    Display *display,
    Window window,
    Atom wanted
) {
    Atom state_prop = XInternAtom(display, "_NET_WM_STATE", False);

    Atom actual_type = None;
    int actual_format = 0;
    unsigned long nitems = 0;
    unsigned long bytes_after = 0;
    unsigned char *data = NULL;

    int status = XGetWindowProperty(
        display,
        window,
        state_prop,
        0,
        64,
        False,
        XA_ATOM,
        &actual_type,
        &actual_format,
        &nitems,
        &bytes_after,
        &data
    );

    if (
        status != Success ||
        actual_type != XA_ATOM ||
        actual_format != 32 ||
        data == NULL
    ) {
        if (data) {
            XFree(data);
        }
        return 0;
    }

    Atom *states = (Atom *)data;
    int found = 0;

    for (unsigned long i = 0; i < nitems; i++) {
        if (states[i] == wanted) {
            found = 1;
            break;
        }
    }

    XFree(data);
    return found;
}

static void send_wm_state(
    Display *display,
    Window root,
    Window window,
    long action,
    Atom first,
    Atom second
) {
    Atom state_prop = XInternAtom(display, "_NET_WM_STATE", False);

    XEvent event;
    memset(&event, 0, sizeof(event));

    event.xclient.type = ClientMessage;
    event.xclient.window = window;
    event.xclient.message_type = state_prop;
    event.xclient.format = 32;
    event.xclient.data.l[0] = action;
    event.xclient.data.l[1] = (long)first;
    event.xclient.data.l[2] = (long)second;
    event.xclient.data.l[3] = 2; /* pager/taskbar */
    event.xclient.data.l[4] = 0;

    XSendEvent(
        display,
        root,
        False,
        SubstructureRedirectMask | SubstructureNotifyMask,
        &event
    );
}

static void move_window(
    Display *display,
    Window root,
    const HitWindow *hit,
    const Monitor *source,
    const Monitor *target
) {
    int new_x = project_axis(
        hit->frame_x,
        source->x,
        source->w,
        target->x,
        target->w,
        hit->frame_w
    );

    int new_y = project_axis(
        hit->frame_y,
        source->y,
        source->h,
        target->y,
        target->h,
        hit->frame_h
    );

    Atom max_h =
        XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_HORZ", False);
    Atom max_v =
        XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_VERT", False);

    int was_max_h = window_has_state(display, hit->window, max_h);
    int was_max_v = window_has_state(display, hit->window, max_v);

    if (was_max_h || was_max_v) {
        send_wm_state(
            display,
            root,
            hit->window,
            0, /* REMOVE */
            was_max_h ? max_h : None,
            was_max_v ? max_v : None
        );

        XSync(display, False);
        sleep_ms(120);
    }

    Atom moveresize =
        XInternAtom(display, "_NET_MOVERESIZE_WINDOW", False);

    XEvent event;
    memset(&event, 0, sizeof(event));

    event.xclient.type = ClientMessage;
    event.xclient.window = hit->window;
    event.xclient.message_type = moveresize;
    event.xclient.format = 32;

    /*
     * StaticGravity permite posicionar exatamente a janela incluindo
     * decoração. Bits 8/9 indicam x/y; source=2 identifica um pager.
     */
    event.xclient.data.l[0] =
        StaticGravity |
        (1L << 8) |
        (1L << 9) |
        (2L << 12);

    event.xclient.data.l[1] = new_x;
    event.xclient.data.l[2] = new_y;
    event.xclient.data.l[3] = 0;
    event.xclient.data.l[4] = 0;

    XSendEvent(
        display,
        root,
        False,
        SubstructureRedirectMask | SubstructureNotifyMask,
        &event
    );

    XSync(display, False);

    if (was_max_h || was_max_v) {
        sleep_ms(140);

        send_wm_state(
            display,
            root,
            hit->window,
            1, /* ADD */
            was_max_h ? max_h : None,
            was_max_v ? max_v : None
        );

        XSync(display, False);
    }
}

static void handle_middle_click(Display *display, Window root) {
    Monitor monitors[MAX_MONITORS];
    int monitor_count = read_monitors(monitors, MAX_MONITORS);

    if (monitor_count < 2) {
        return;
    }

    Window root_return = None;
    Window child_return = None;
    int root_x = 0;
    int root_y = 0;
    int win_x = 0;
    int win_y = 0;
    unsigned int pointer_mask = 0;

    if (!XQueryPointer(
        display,
        root,
        &root_return,
        &child_return,
        &root_x,
        &root_y,
        &win_x,
        &win_y,
        &pointer_mask
    )) {
        return;
    }

    HitWindow hit;

    if (!find_titlebar_window(
        display,
        root,
        root_x,
        root_y,
        &hit
    )) {
        return;
    }

    int source_index = find_source_monitor(
        monitors,
        monitor_count,
        &hit
    );

    int target_index = (source_index + 1) % monitor_count;

    move_window(
        display,
        root,
        &hit,
        &monitors[source_index],
        &monitors[target_index]
    );
}

int main(void) {
    Display *display = XOpenDisplay(NULL);

    if (!display) {
        fprintf(stderr, "wolf-titlebar-monitor-move: DISPLAY indisponível\n");
        return 1;
    }

    int xi_opcode = 0;
    int event = 0;
    int error = 0;

    if (!XQueryExtension(
        display,
        "XInputExtension",
        &xi_opcode,
        &event,
        &error
    )) {
        fprintf(stderr, "wolf-titlebar-monitor-move: XInput2 indisponível\n");
        XCloseDisplay(display);
        return 1;
    }

    int major = 2;
    int minor = 0;

    if (XIQueryVersion(display, &major, &minor) != Success) {
        fprintf(stderr, "wolf-titlebar-monitor-move: XI2 >= 2.0 necessário\n");
        XCloseDisplay(display);
        return 1;
    }

    Window root = DefaultRootWindow(display);

    unsigned char bits[(XI_LASTEVENT + 7) / 8];
    memset(bits, 0, sizeof(bits));
    XISetMask(bits, XI_RawButtonPress);

    XIEventMask mask;
    mask.deviceid = XIAllMasterDevices;
    mask.mask_len = (int)sizeof(bits);
    mask.mask = bits;

    XISelectEvents(display, root, &mask, 1);
    XFlush(display);

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGHUP, handle_signal);

    while (keep_running) {
        XEvent xevent;
        XNextEvent(display, &xevent);

        if (
            xevent.xcookie.type == GenericEvent &&
            xevent.xcookie.extension == xi_opcode &&
            XGetEventData(display, &xevent.xcookie)
        ) {
            if (xevent.xcookie.evtype == XI_RawButtonPress) {
                XIRawEvent *raw =
                    (XIRawEvent *)xevent.xcookie.data;

                if (raw->detail == 2) {
                    handle_middle_click(display, root);
                }
            }

            XFreeEventData(display, &xevent.xcookie);
        }
    }

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
    -o /usr/local/bin/wolf-titlebar-monitor-move \
    -lX11 \
    -lXi

sudo chmod 755 /usr/local/bin/wolf-titlebar-monitor-move

sudo tee /usr/local/bin/wolf-titlebar-monitor-move-start >/dev/null <<'EOF'
#!/usr/bin/env bash
set -u

if gsettings list-schemas 2>/dev/null | grep -Fxq 'org.mate.Marco.general'; then
    if gsettings list-keys org.mate.Marco.general 2>/dev/null \
        | grep -Fxq 'action-middle-click-titlebar'; then
        gsettings set \
            org.mate.Marco.general \
            action-middle-click-titlebar \
            'none' \
            2>/dev/null || true
    fi
fi

exec /usr/local/bin/wolf-titlebar-monitor-move
EOF

sudo chmod 755 /usr/local/bin/wolf-titlebar-monitor-move-start

sudo tee /etc/xdg/autostart/wolf-titlebar-monitor-move.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wolf Linux - Mover janela entre monitores
Comment=Clique do meio na barra de título envia a janela ao próximo monitor
Exec=/usr/local/bin/wolf-titlebar-monitor-move-start
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

if gsettings list-keys org.mate.Marco.general 2>/dev/null \
    | grep -Fxq 'action-middle-click-titlebar'; then
    gsettings set \
        org.mate.Marco.general \
        action-middle-click-titlebar \
        'none' || true
fi

pkill -x wolf-titlebar-monitor-move 2>/dev/null || true

mkdir -p "$HOME/.cache"

nohup /usr/local/bin/wolf-titlebar-monitor-move \
    >"$HOME/.cache/wolf-titlebar-monitor-move.log" 2>&1 &

disown || true

echo
echo "============================================================"
echo "                    CONCLUÍDO"
echo "============================================================"
echo
echo "Uso:"
echo "  BOTÃO DO MEIO na barra de título -> próximo monitor"
echo
echo "Com 2 monitores, alterna entre os dois."
echo "Com 3+, percorre da esquerda para a direita."
echo "A posição relativa é preservada."
echo
echo "Janelas maximizadas são temporariamente restauradas,"
echo "movidas e maximizadas novamente."
echo
echo "Aplicações com barra própria/CSD não são interceptadas."
echo
echo "Log:"
echo "  $HOME/.cache/wolf-titlebar-monitor-move.log"
