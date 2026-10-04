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
echo "          WOLF LINUX 1.0 - FINALIZER"
echo "============================================================"
echo
echo "Aplicando:"
echo "  - tema escuro via XDG Desktop Portal"
echo "  - remoção do wrapper temporário do GNOME Disks"
echo "  - Super + botão do meio universal para mover janelas"
echo "  - restauração do clique do meio nativo do Marco"
echo "  - singleton/kill robusto do daemon de janelas"
echo

sudo pacman -S --needed --noconfirm \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk \
    rtkit \
    gnome-disk-utility \
    xorg-xrandr

# ------------------------------------------------------------
# 1. Dark portal
# ------------------------------------------------------------
echo
echo "[1/3] Consolidando tema escuro via portal..."

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.mate.interface gtk-theme 'Materia-dark' 2>/dev/null || true
gsettings set org.mate.interface icon-theme 'Papirus-Dark' 2>/dev/null || true

systemctl --user restart \
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

# Remove o workaround temporário da v0.46: agora usamos o mecanismo correto.
sudo rm -f /usr/local/bin/wolf-gnome-disks
sudo rm -f /usr/local/share/applications/org.gnome.DiskUtility.desktop

if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/local/share/applications >/dev/null 2>&1 || true
fi

echo "[OK] GNOME Disks volta ao launcher original e herda dark mode do portal."

# ------------------------------------------------------------
# 2. Build universal Super+Middle daemon
# ------------------------------------------------------------
echo
echo "[2/3] Instalando Super + botão do meio universal..."

tmp_c="$(mktemp --suffix=.c)"
trap 'rm -f "$tmp_c"' EXIT

cat > "$tmp_c" <<'C'
#define _POSIX_C_SOURCE 200809L

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

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

static int find_super_move_window(
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
     * _NET_CLIENT_LIST_STACKING vai de baixo para cima.
     * O primeiro frame atingido ao percorrer ao contrário é a janela
     * topmost real naquele ponto. Nunca procuramos uma janela abaixo.
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
         * ESTA é a janela topmost. O gesto só é aceito:
         *
         * - janela Marco tradicional: na barra de título real;
         * - Chrome/Electron/CSD: nos primeiros CSD_TOP_HEIGHT px do frame.
         *
         * Se o ponteiro estiver em outra região, ReplayPointer devolverá
         * o clique ao aplicativo. Não há fallback para janelas inferiores.
         */
        int looks_csd =
            top == 0 ||
            has_gtk_frame_extents(display, window) ||
            class_looks_like_csd_app(display, window);

        int valid_region = 0;

        if (looks_csd) {
            int top_limit = frame_y + CSD_TOP_HEIGHT;

            if (top_limit > frame_y + frame_h) {
                top_limit = frame_y + frame_h;
            }

            valid_region =
                pointer_y >= frame_y &&
                pointer_y < top_limit;
        } else if (top > 0) {
            valid_region =
                pointer_y >= frame_y &&
                pointer_y < client_y;
        }

        if (!valid_region) {
            XFree(clients);
            return 0;
        }

        if (!window_is_normal_type(display, window)) {
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
                "wolf-titlebar-monitor-move: Super+Middle hit window=0x%lx class=%s/%s mode=%s frame=%dx%d%+d%+d\n",
                window,
                hint.res_name ? hint.res_name : "?",
                hint.res_class ? hint.res_class : "?",
                looks_csd ? "csd" : "marco",
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
                "wolf-titlebar-monitor-move: Super+Middle hit window=0x%lx mode=%s frame=%dx%d%+d%+d\n",
                window,
                looks_csd ? "csd" : "marco",
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

static int handle_super_middle(
    Display *display,
    Window root,
    int root_x,
    int root_y
) {
    HitWindow hit;

    if (!find_super_move_window(
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

    Window root = DefaultRootWindow(display);

    unsigned int super_mask = detect_super_mask(display);
    unsigned int numlock_mask = detect_numlock_mask(display);

    /*
     * Gesto universal do Wolf Linux:
     * Super + botão do meio na barra/topo da janela.
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
            int moved = handle_super_middle(
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
    -lX11

sudo chmod 755 /usr/local/bin/wolf-titlebar-monitor-move

sudo tee /usr/local/bin/wolf-titlebar-monitor-move-start >/dev/null <<'EOF'
#!/usr/bin/env bash
set -u

# Uma única instância por sessão/usuário. O lock permanece aberto no daemon
# depois do exec, evitando instâncias antigas concorrendo pelos X11 grabs.
LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_FILE="$LOCK_DIR/wolf-titlebar-monitor-move-${UID}.lock"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# O botão do meio SEM Super volta ao comportamento nativo do Marco.
if gsettings list-schemas 2>/dev/null | grep -Fxq 'org.mate.Marco.general'; then
    if gsettings list-keys org.mate.Marco.general 2>/dev/null \
        | grep -Fxq 'action-middle-click-titlebar'; then
        gsettings set \
            org.mate.Marco.general \
            action-middle-click-titlebar \
            'lower' \
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
Comment=Super+botão do meio na barra de título envia a janela ao próximo monitor
Exec=/usr/local/bin/wolf-titlebar-monitor-move-start
OnlyShowIn=MATE;
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

# Restaura o comportamento nativo do botão do meio sem Super.
if gsettings list-keys org.mate.Marco.general 2>/dev/null \
    | grep -Fxq 'action-middle-click-titlebar'; then
    gsettings set \
        org.mate.Marco.general \
        action-middle-click-titlebar \
        'lower' || true
fi

# Kill robusto: pkill -x falha com nomes >15 chars no campo comm.
pkill -f '^/usr/local/bin/wolf-titlebar-monitor-move$' 2>/dev/null || true

sleep 0.5

mkdir -p "$HOME/.cache"
: > "$HOME/.cache/wolf-titlebar-monitor-move.log"

nohup /usr/local/bin/wolf-titlebar-monitor-move-start \
    >"$HOME/.cache/wolf-titlebar-monitor-move.log" 2>&1 &

disown || true
sleep 1

echo
echo "Daemon:"
pgrep -af '^/usr/local/bin/wolf-titlebar-monitor-move$' || true

echo
echo "Log inicial:"
cat "$HOME/.cache/wolf-titlebar-monitor-move.log" 2>/dev/null || true

grab_errors="$(
    sed -n 's/.*grab_errors=\([0-9][0-9]*\).*/\1/p' \
        "$HOME/.cache/wolf-titlebar-monitor-move.log" \
        | tail -n1
)"

if pgrep -f '^/usr/local/bin/wolf-titlebar-monitor-move$' >/dev/null 2>&1; then
    if [[ -n "$grab_errors" && "$grab_errors" -eq 0 ]]; then
        echo "[OK] Daemon ativo; todos os grabs X11 registrados."
    elif [[ -n "$grab_errors" && "$grab_errors" -lt 4 ]]; then
        echo "[OK] Daemon ativo; gesto funcional."
        echo "[INFO] $grab_errors combinação(ões) de Lock/NumLock já estava(m) ocupada(s)."
    else
        echo "[AVISO] Daemon ativo, mas os grabs devem ser conferidos no log."
    fi
else
    echo "[ERRO] wolf-titlebar-monitor-move não permaneceu em execução."
    exit 1
fi

# ------------------------------------------------------------
# 3. RTKit
# ------------------------------------------------------------
echo
echo "[3/3] Conferindo RTKit..."

sudo systemctl start rtkit-daemon.service 2>/dev/null || true

if systemctl is-active rtkit-daemon.service >/dev/null 2>&1; then
    echo "[OK] rtkit-daemon ativo."
else
    echo "[INFO] RTKit instalado; D-Bus também pode ativá-lo sob demanda."
fi

echo
echo "============================================================"
echo "              WOLF LINUX 1.0 - PRONTO"
echo "============================================================"
echo
echo "Gestos de janela:"
echo "  Super + botão do meio na barra Marco -> próximo monitor"
echo "  Super + botão do meio no topo Chrome/CSD -> próximo monitor"
echo "  botão do meio sem Super no Marco -> lower (comportamento nativo)"
echo
echo "GNOME Disks:"
echo "  abra normalmente pelo menu ou execute: gnome-disks"
echo "  portal esperado: uint32 1"
echo
echo "Log do mover:"
echo "  ~/.cache/wolf-titlebar-monitor-move.log"
