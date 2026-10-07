#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

# Abre a instância do Whisker que pertence ao monitor onde está o ponteiro,
# mas deixa o próprio Whisker ancorar o popup ao botão do painel.
# Isso evita o visual de --pointer (menu solto no meio da tela).

command -v xfconf-query >/dev/null 2>&1 || exit 1
command -v xdotool >/dev/null 2>&1 || exec xfce4-popup-whiskermenu

mouse_x=0 mouse_y=0
while IFS='=' read -r key value; do
    case "$key" in
        X) mouse_x="$value" ;;
        Y) mouse_y="$value" ;;
    esac
done < <(xdotool getmouselocation --shell 2>/dev/null || true)

point_output=""
while IFS= read -r line; do
    [[ "$line" == *" connected "* ]] || continue
    out="${line%% *}"
    if [[ "$line" =~ ([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) ]]; then
        w="${BASH_REMATCH[1]}"; h="${BASH_REMATCH[2]}"
        x="${BASH_REMATCH[3]}"; y="${BASH_REMATCH[4]}"
        if (( mouse_x >= x && mouse_x < x+w && mouse_y >= y && mouse_y < y+h )); then
            point_output="$out"
            break
        fi
    fi
done < <(xrandr --query 2>/dev/null || true)

# Fallback para o monitor principal/primeiro ativo.
if [[ -z "$point_output" ]]; then
    point_output="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && /\*/ {print $NF; exit}')"
fi
if [[ -z "$point_output" ]]; then
    point_output="$(xrandr --query 2>/dev/null | awk '$2=="connected" {print $1; exit}')"
fi

panel_id=""
while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    out="$(xfconf-query -c xfce4-panel -p "/panels/panel-$p/output-name" 2>/dev/null || true)"
    if [[ "$out" == "$point_output" ]]; then
        panel_id="$p"
        break
    fi
done < <(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true)

# Se o painel principal estiver em modo Automatic, ainda podemos usá-lo quando
# o ponteiro está no output principal.
if [[ -z "$panel_id" ]]; then
    panel_id="$(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$' | head -n1 || true)"
fi

whisker_id=""
if [[ -n "$panel_id" ]]; then
    while IFS= read -r id; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue
        type="$(xfconf-query -c xfce4-panel -p "/plugins/plugin-$id" 2>/dev/null || true)"
        if [[ "$type" == "whiskermenu" ]]; then
            whisker_id="$id"
            break
        fi
    done < <(xfconf-query -c xfce4-panel -p "/panels/panel-$panel_id/plugin-ids" 2>/dev/null || true)
fi

if [[ -n "$whisker_id" ]]; then
    # Whisker 2.8+ aceita --instance. Quando não aceita o ID numérico do plugin,
    # o remote event do painel continua sendo um fallback confiável.
    if xfce4-popup-whiskermenu --list 2>/dev/null | grep -Eq "(^|[^0-9])${whisker_id}([^0-9]|$)"; then
        exec xfce4-popup-whiskermenu --instance="$whisker_id"
    fi
    if xfce4-panel --plugin-event="whiskermenu-${whisker_id}:popup" >/dev/null 2>&1; then
        exit 0
    fi
fi

exec xfce4-popup-whiskermenu
