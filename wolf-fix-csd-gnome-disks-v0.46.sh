#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}" != *MATE* ]]; then
    echo "[ERRO] Execute dentro da sessão MATE."
    exit 1
fi

if [[ "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
    echo "[ERRO] O mover de janelas foi feito para MATE/X11."
    exit 1
fi

echo "============================================================"
echo "     WOLF LINUX - CSD + GNOME DISKS FIX v0.46"
echo "============================================================"
echo
echo "Correções:"
echo "  - Chrome não deixa mais o gesto cair na janela de baixo"
echo "  - Super+botão do meio usa a janela topmost"
echo "  - GNOME Disks é forçado a usar Materia-dark"
echo

sudo pacman -S --needed --noconfirm libxi xorg-xrandr gnome-disk-utility

echo
echo "[1/2] Forçando Materia-dark no GNOME Disks..."

sudo tee /usr/local/bin/wolf-gnome-disks >/dev/null <<'EOF'
#!/usr/bin/env bash
set -u
export GTK_THEME=Materia-dark
exec /usr/bin/gnome-disks "$@"
EOF

sudo chmod 755 /usr/local/bin/wolf-gnome-disks
sudo install -d /usr/local/share/applications

if [[ -f /usr/share/applications/org.gnome.DiskUtility.desktop ]]; then
    sudo cp -f \
        /usr/share/applications/org.gnome.DiskUtility.desktop \
        /usr/local/share/applications/org.gnome.DiskUtility.desktop

    sudo sed -i \
        -e 's|^Exec=gnome-disks|Exec=/usr/local/bin/wolf-gnome-disks|' \
        -e 's|^TryExec=gnome-disks|TryExec=/usr/local/bin/wolf-gnome-disks|' \
        /usr/local/share/applications/org.gnome.DiskUtility.desktop
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
fi

echo "[OK] Wrapper e launcher escuro criados."

echo
echo "[2/2] Atualizando detecção topmost do Chrome/CSD..."

tmp_c="$(mktemp --suffix=.c)"
trap 'rm -f "$tmp_c"' EXIT

cat > "$tmp_c" <<'C'
#define _POSIX_C_SOURCE 200809L

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#include <X11/extensions/XInput2.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAX_MONITORS 16
#define MAX_CLIENTS 4096
#define CSD_TOP_HEIGHT 64

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

static int window_is_normal_type(
    Display *display,
    Window window
) {
    Atom prop = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
    Atom normal = XInternAtom(display, "_NET_WM_WINDOW_TYPE_NORMAL", False);

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
        16,
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

        /* Sem hint: não rejeitamos automaticamente uma janela comum. */
        return 1;
    }

    Atom *types = (Atom *)data;
    int found = 0;

    for (unsigned long i = 0; i < nitems; i++) {
        if (types[i] == normal) {
            found = 1;
            break;
        }
    }

    XFree(data);
    return found;
}

static int string_contains_case_insensitive(
    const char *haystack,
    const char *needle
) {
    if (!haystack || !needle) {
        return 0;
    }

    size_t needle_len = strlen(needle);

    if (needle_len == 0) {
        return 1;
    }

    for (const char *p = haystack; *p; p++) {
        size_t i = 0;

        while (
            i < needle_len &&
            p[i] &&
            (
                p[i] == needle[i] ||
                (
                    p[i] >= 'A' && p[i] <= 'Z' &&
                    p[i] - 'A' + 'a' == needle[i]
                ) ||
                (
                    needle[i] >= 'A' && needle[i] <= 'Z' &&
                    needle[i] - 'A' + 'a' == p[i]
                )
            )
        ) {
            i++;
        }

        if (i == needle_len) {
            return 1;
        }
    }

    return 0;
}

static int class_looks_like_csd_app(
    Display *display,
    Window window
) {
    XClassHint hint;

    if (!XGetClassHint(display, window, &hint)) {
        return 0;
    }

    const char *candidates[] = {
        "google-chrome",
        "chromium",
        "brave",
        "microsoft-edge",
        "code",
        "vscodium",
        "electron"
    };

    int matched = 0;

    for (
        unsigned long i = 0;
        i < sizeof(candidates) / sizeof(candidates[0]);
        i++
    ) {
        if (
            string_contains_case_insensitive(
                hint.res_name,
                candidates[i]
            ) ||
            string_contains_case_insensitive(
                hint.res_class,
                candidates[i]
            )
        ) {
            matched = 1;
            break;
        }
    }

    if (hint.res_name) {
        XFree(hint.res_name);
    }

    if (hint.res_class) {
        XFree(hint.res_class);
    }

    return matched;
}

static int has_gtk_frame_extents(
    Display *display,
    Window window
) {
    Atom prop = XInternAtom(display, "_GTK_FRAME_EXTENTS", False);

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

    int found =
        status == Success &&
        actual_type == XA_CARDINAL &&
        actual_format == 32 &&
        nitems >= 4 &&
        data != NULL;

    if (data) {
        XFree(data);
    }

    return found;
}

static int find_csd_top_window(
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

    /*
     * _NET_CLIENT_LIST_STACKING vai de baixo para cima. O primeiro frame
     * que contém o ponteiro, ao percorrer ao contrário, é a janela topmost.
     * Nunca "caímos" para uma janela inferior.
     */
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

        int have_extents = get_frame_extents(
            display,
            window,
            &left,
            &right,
            &top,
            &bottom
        );

        if (!have_extents) {
            left = 0;
            right = 0;
            top = 0;
            bottom = 0;
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
            pointer_x < frame_x ||
            pointer_x >= frame_x + frame_w ||
            pointer_y < frame_y ||
            pointer_y >= frame_y + frame_h
        ) {
            continue;
        }

        /*
         * ESTA é a janela visível sob o ponteiro. Se não for CSD, o gesto
         * falha nela; não procuramos qualquer janela por baixo.
         */
        if (!window_is_normal_type(display, window)) {
            XFree(clients);
            return 0;
        }

        int looks_csd =
            top == 0 ||
            has_gtk_frame_extents(display, window) ||
            class_looks_like_csd_app(display, window);

        if (!looks_csd) {
            XFree(clients);
            return 0;
        }

        int top_limit = frame_y + CSD_TOP_HEIGHT;

        if (top_limit > frame_y + frame_h) {
            top_limit = frame_y + frame_h;
        }

        if (pointer_y >= top_limit) {
            XFree(clients);
            return 0;
        }

        hit->window = window;
        hit->frame_x = frame_x;
        hit->frame_y = frame_y;
        hit->frame_w = frame_w;
        hit->frame_h = frame_h;

        XClassHint hint;
        memset(&hint, 0, sizeof(hint));

        if (XGetClassHint(display, window, &hint)) {
            fprintf(
                stderr,
                "wolf-titlebar-monitor-move: CSD hit window=0x%lx class=%s/%s frame=%dx%d%+d%+d\n",
                window,
                hint.res_name ? hint.res_name : "?",
                hint.res_class ? hint.res_class : "?",
                frame_w,
                frame_h,
                frame_x,
                frame_y
            );

            if (hint.res_name) {
                XFree(hint.res_name);
            }

            if (hint.res_class) {
                XFree(hint.res_class);
            }
        } else {
            fprintf(
                stderr,
                "wolf-titlebar-monitor-move: CSD hit window=0x%lx frame=%dx%d%+d%+d\n",
                window,
                frame_w,
                frame_h,
                frame_x,
                frame_y
            );
        }

        fflush(stderr);
        XFree(clients);
        return 1;
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

static int move_hit_to_next_monitor(
    Display *display,
    Window root,
    const HitWindow *hit
) {
    Monitor monitors[MAX_MONITORS];
    int monitor_count = read_monitors(monitors, MAX_MONITORS);

    if (monitor_count < 2) {
        return 0;
    }

    int source_index = find_source_monitor(
        monitors,
        monitor_count,
        hit
    );

    int target_index = (source_index + 1) % monitor_count;

    move_window(
        display,
        root,
        hit,
        &monitors[source_index],
        &monitors[target_index]
    );

    return 1;
}

static void handle_middle_click(
    Display *display,
    Window root,
    unsigned int super_mask
) {
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

    /*
     * Super+Button2 pertence exclusivamente ao caminho CSD. Sem esse
     * filtro o evento RAW também podia movimentar uma barra Marco atrás
     * do Chrome.
     */
    if ((pointer_mask & super_mask) == super_mask) {
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

    move_hit_to_next_monitor(display, root, &hit);
}

static int handle_csd_super_middle(
    Display *display,
    Window root,
    int root_x,
    int root_y
) {
    HitWindow hit;

    if (!find_csd_top_window(
        display,
        root,
        root_x,
        root_y,
        &hit
    )) {
        return 0;
    }

    return move_hit_to_next_monitor(display, root, &hit);
}

static int grab_error_count = 0;

static int record_grab_error(
    Display *display,
    XErrorEvent *event
) {
    (void)display;

    if (event->error_code == BadAccess) {
        grab_error_count++;
    }

    return 0;
}

static unsigned int modifier_mask_for_keysym(
    Display *display,
    KeySym keysym
) {
    KeyCode keycode = XKeysymToKeycode(display, keysym);

    if (keycode == 0) {
        return 0;
    }

    XModifierKeymap *map = XGetModifierMapping(display);

    if (!map) {
        return 0;
    }

    unsigned int mask = 0;

    for (int modifier = 0; modifier < 8; modifier++) {
        for (int index = 0; index < map->max_keypermod; index++) {
            int offset =
                modifier * map->max_keypermod + index;

            if (map->modifiermap[offset] == keycode) {
                mask |= (1U << modifier);
            }
        }
    }

    XFreeModifiermap(map);
    return mask;
}

static unsigned int detect_super_mask(Display *display) {
    unsigned int left =
        modifier_mask_for_keysym(display, XK_Super_L);
    unsigned int right =
        modifier_mask_for_keysym(display, XK_Super_R);

    unsigned int mask = left | right;

    if (mask == 0) {
        mask = Mod4Mask;
    }

    return mask;
}

static unsigned int detect_numlock_mask(Display *display) {
    return modifier_mask_for_keysym(display, XK_Num_Lock);
}

static void grab_super_middle(
    Display *display,
    Window root,
    unsigned int super_mask,
    unsigned int numlock_mask
) {
    unsigned int modifiers[4];
    modifiers[0] = super_mask;
    modifiers[1] = super_mask | LockMask;
    modifiers[2] = super_mask | numlock_mask;
    modifiers[3] = super_mask | LockMask | numlock_mask;

    grab_error_count = 0;

    int (*old_handler)(Display *, XErrorEvent *) =
        XSetErrorHandler(record_grab_error);

    for (int i = 0; i < 4; i++) {
        int duplicate = 0;

        for (int j = 0; j < i; j++) {
            if (modifiers[i] == modifiers[j]) {
                duplicate = 1;
                break;
            }
        }

        if (duplicate) {
            continue;
        }

        XGrabButton(
            display,
            Button2,
            modifiers[i],
            root,
            False,
            ButtonPressMask,
            GrabModeSync,
            GrabModeAsync,
            None,
            None
        );
    }

    XSync(display, False);
    XSetErrorHandler(old_handler);

    fprintf(
        stderr,
        "wolf-titlebar-monitor-move: SuperMask=0x%x NumLockMask=0x%x grab_errors=%d\n",
        super_mask,
        numlock_mask,
        grab_error_count
    );
    fflush(stderr);
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

    unsigned int super_mask = detect_super_mask(display);
    unsigned int numlock_mask = detect_numlock_mask(display);

    unsigned char bits[(XI_LASTEVENT + 7) / 8];
    memset(bits, 0, sizeof(bits));
    XISetMask(bits, XI_RawButtonPress);

    XIEventMask mask;
    mask.deviceid = XIAllMasterDevices;
    mask.mask_len = (int)sizeof(bits);
    mask.mask = bits;

    XISelectEvents(display, root, &mask, 1);

    /*
     * Gesto especial para Chrome/Electron/CSD:
     * Super + botão do meio na faixa superior.
     *
     * O passive grab permite CONSUMIR o clique quando a área é válida,
     * evitando que o Chrome interprete Button2 como "fechar aba".
     * Fora de uma CSD válida, ReplayPointer devolve o clique ao app.
     */
    grab_super_middle(
        display,
        root,
        super_mask,
        numlock_mask
    );

    XFlush(display);

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGHUP, handle_signal);

    while (keep_running) {
        XEvent xevent;
        XNextEvent(display, &xevent);

        if (
            xevent.type == ButtonPress &&
            xevent.xbutton.button == Button2 &&
            (
                xevent.xbutton.state & super_mask
            ) == super_mask
        ) {
            int moved = handle_csd_super_middle(
                display,
                root,
                xevent.xbutton.x_root,
                xevent.xbutton.y_root
            );

            /*
             * Se movemos uma CSD, o clique é consumido.
             * Caso contrário ele é replayado para o aplicativo original.
             */
            XAllowEvents(
                display,
                moved ? AsyncPointer : ReplayPointer,
                xevent.xbutton.time
            );

            XFlush(display);
            continue;
        }

        if (
            xevent.xcookie.type == GenericEvent &&
            xevent.xcookie.extension == xi_opcode &&
            XGetEventData(display, &xevent.xcookie)
        ) {
            if (xevent.xcookie.evtype == XI_RawButtonPress) {
                XIRawEvent *raw =
                    (XIRawEvent *)xevent.xcookie.data;

                if (raw->detail == 2) {
                    handle_middle_click(
                        display,
                        root,
                        super_mask
                    );
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

pkill -x wolf-titlebar-monitor-move 2>/dev/null || true
mkdir -p "$HOME/.cache"
: > "$HOME/.cache/wolf-titlebar-monitor-move.log"

nohup /usr/local/bin/wolf-titlebar-monitor-move-start \
    >"$HOME/.cache/wolf-titlebar-monitor-move.log" 2>&1 &

disown || true

sleep 1

echo
echo "Log inicial:"
tail -n 10 "$HOME/.cache/wolf-titlebar-monitor-move.log" 2>/dev/null || true

echo
echo "============================================================"
echo "                    CONCLUÍDO"
echo "============================================================"
echo
echo "Teste Chrome:"
echo "  Super + botão do meio na faixa das abas."
echo "  Nenhuma janela abaixo deve se mover."
echo
echo "Teste GNOME Disks:"
echo "  feche instâncias antigas e execute:"
echo "    /usr/local/bin/wolf-gnome-disks"
echo
echo "Se Chrome ainda não mover:"
echo "  tail -n 30 ~/.cache/wolf-titlebar-monitor-move.log"
