#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then exec /usr/bin/env bash "$0" "$@"; fi
set -Eeuo pipefail

# Abre a instância do Whisker pertencente ao monitor onde está o ponteiro,
# sempre ancorada ao BOTÃO do painel. O bool:false é importante: versões
# recentes do Whisker aceitam o parâmetro "popup" com um booleano que define
# se o menu deve nascer no ponteiro (true) ou junto ao applet (false).

command -v xfconf-query >/dev/null 2>&1 || exit 1
command -v xrandr >/dev/null 2>&1 || exit 1
command -v xfce4-panel >/dev/null 2>&1 || exit 1

mouse_x=0
mouse_y=0
if command -v xdotool >/dev/null 2>&1; then
    while IFS='=' read -r key value; do
        case "$key" in
            X) mouse_x="$value" ;;
            Y) mouse_y="$value" ;;
        esac
    done < <(xdotool getmouselocation --shell 2>/dev/null || true)
fi

# Uma única consulta ao RandR por acionamento da tecla.
randr_query="$(xrandr --query 2>/dev/null || true)"
randr_monitors="$(xrandr --listmonitors 2>/dev/null || true)"

point_output=""
while IFS= read -r line; do
    [[ "$line" == *" connected "* ]] || continue
    out="${line%% *}"
    if [[ "$line" =~ ([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) ]]; then
        w="${BASH_REMATCH[1]}"
        h="${BASH_REMATCH[2]}"
        x="${BASH_REMATCH[3]}"
        y="${BASH_REMATCH[4]}"
        if (( mouse_x >= x && mouse_x < x+w && mouse_y >= y && mouse_y < y+h )); then
            point_output="$out"
            break
        fi
    fi
done <<< "$randr_query"

primary_output="$(awk 'NR>1 && /\*/ {print $NF; exit}' <<< "$randr_monitors")"
[[ -n "$primary_output" ]] || primary_output="$(awk '$2=="connected" {print $1; exit}' <<< "$randr_query")"
[[ -n "$point_output" ]] || point_output="$primary_output"

panel_id=""
first_panel=""
while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    [[ -n "$first_panel" ]] || first_panel="$p"
    out="$(xfconf-query -c xfce4-panel -p "/panels/panel-$p/output-name" 2>/dev/null || true)"
    if [[ "$out" == "$point_output" ]]; then
        panel_id="$p"
        break
    fi
    if [[ "$point_output" == "$primary_output" && "$out" == "Automatic" ]]; then
        panel_id="$p"
    fi
done < <(xfconf-query -c xfce4-panel -p /panels 2>/dev/null || true)

monitor_count="$(awk 'NR>1 {n++} END {print n+0}' <<< "$randr_monitors")"
if [[ -z "$panel_id" && "$monitor_count" -le 1 ]]; then
    panel_id="$first_panel"
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
    # O booleano false força popup junto ao applet, e não sob o ponteiro.
    if xfce4-panel --plugin-event="whiskermenu-${whisker_id}:popup:bool:false" >/dev/null 2>&1; then
        exit 0
    fi

    # Fallback apenas para builds antigos. Nunca use --pointer.
    if command -v xfce4-popup-whiskermenu >/dev/null 2>&1 \
       && xfce4-popup-whiskermenu --instance="$whisker_id" >/dev/null 2>&1; then
        exit 0
    fi
fi

if (( monitor_count <= 1 )) && command -v xfce4-popup-whiskermenu >/dev/null 2>&1; then
    exec xfce4-popup-whiskermenu
fi

printf '[Wolf XFCE Whisker] Não encontrei uma instância do Whisker no monitor %s.\n' \
    "${point_output:-desconhecido}" >&2
exit 1
