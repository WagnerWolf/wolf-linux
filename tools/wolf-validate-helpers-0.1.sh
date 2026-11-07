#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/usr/local/lib/wolf-linux/helpers"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/helper-validation"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$STATE_ROOT/validation-$STAMP.tsv"
MODE="auto"

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[AVISO] %s\n' "$*" >&2; }
die()  { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
Uso: wolf-validate-helpers [--vm|--hardware]

Executa uma validação GUIADA dos helpers Wolf. Nenhum helper é aplicado sem
confirmação. Entre as etapas há pausa para teste manual e registro PASS/FAIL/SKIP.
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --vm) MODE="vm" ;;
        --hardware) MODE="hardware" ;;
        -h|--help) usage; exit 0 ;;
        *) die "Argumento inválido: $arg" ;;
    esac
done

if [[ "$MODE" == "auto" ]]; then
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    case "$virt" in
        none|"") MODE="hardware" ;;
        *) MODE="vm" ;;
    esac
fi

mkdir -p "$STATE_ROOT"
printf 'timestamp\tstage\tresult\tnote\n' > "$REPORT"

record() {
    local stage="$1" result="$2" note="${3:-}"
    note="${note//$'\t'/ }"
    note="${note//$'\n'/ }"
    printf '%s\t%s\t%s\t%s\n' "$(date -Is)" "$stage" "$result" "$note" >> "$REPORT"
}

pause_enter() {
    read -r -p $'\nPressione Enter quando terminar a verificação manual...' _ || true
}

result_prompt() {
    local stage="$1" rollback_cmd="${2:-}"
    local answer
    while true; do
        say ""
        if [[ -n "$rollback_cmd" ]]; then
            read -r -p "Resultado: [p] passou  [f] falhou  [r] rollback  [s] pular  [q] parar: " answer
        else
            read -r -p "Resultado: [p] passou  [f] falhou  [s] pular  [q] parar: " answer
        fi
        case "${answer,,}" in
            p|pass)
                record "$stage" PASS
                ok "$stage marcado como PASS."
                return 0
                ;;
            f|fail)
                record "$stage" FAIL
                warn "$stage marcado como FAIL. A validação será interrompida."
                return 1
                ;;
            r|rollback)
                if [[ -n "$rollback_cmd" ]]; then
                    info "Executando rollback..."
                    bash -lc "$rollback_cmd" || warn "Rollback retornou erro."
                    record "$stage" FAIL "rollback executado"
                    return 1
                fi
                warn "Esta etapa não possui rollback automático."
                ;;
            s|skip)
                record "$stage" SKIP
                warn "$stage marcado como SKIP."
                return 0
                ;;
            q|quit)
                record "$stage" STOP "interrompido pelo usuário"
                say "Relatório: $REPORT"
                exit 0
                ;;
            *) warn "Opção inválida." ;;
        esac
    done
}

ask_apply() {
    local prompt="$1" answer
    read -r -p "$prompt [s/N]: " answer
    [[ "$answer" =~ ^[sS]([iI][mM])?$ ]]
}

helper_path() {
    local class="$1"
    local name="$2"
    local path="$ROOT/$class/$name"
    [[ -x "$path" ]] || die "Helper ausente: $path"
    printf '%s\n' "$path"
}

header() {
    say "============================================================"
    say "        WOLF LINUX - VALIDAÇÃO GUIADA DE HELPERS"
    say "============================================================"
    say "Modo ....: $MODE"
    say "Relatório: $REPORT"
    say ""
    say "Branding e MultiMonitor: aplicação inicial automática, uma única vez."
    say "Gamepad e GRUB Manager: execução manual."
    say "Você decide quando aplicar e quando avançar."
    say "============================================================"
}

stage_baseline() {
    say ""
    say "[1/5] BASELINE KDE/WAYLAND"
    say "-------------------------"
    printf 'Sessão ....: %s\n' "${XDG_SESSION_TYPE:-?}"
    printf 'Desktop ...: %s\n' "${XDG_CURRENT_DESKTOP:-?}"
    printf 'Virt ......: %s\n' "$(systemd-detect-virt 2>/dev/null || true)"
    say ""
    say "systemctl --user --failed:"
    systemctl --user --failed --no-pager || true
    say ""
    say "Use alguns minutos o Plasma antes de aprovar: terminal, rede, áudio, navegador."
    pause_enter
    result_prompt baseline
}

stage_branding() {
    local helper
    helper="$(helper_path experimental wolf-plasma-branding-0.2.sh)"
    say ""
    say "[2/5] BRANDING PLASMA 0.2"
    say "-------------------------"
    "$helper" status || true
    if ask_apply "Aplicar branding agora?"; then
        "$helper" apply
        say ""
        say "Verifique: Breeze Dark, Papirus-Dark, wallpaper Wolf e ícone Kickoff proporcional."
        pause_enter
        result_prompt branding "'$helper' restore"
    else
        record branding SKIP "não aplicado"
    fi
}

show_wolf_processes() {
    say ""
    say "Processos potencialmente relacionados a helpers/watchers:"
    local pids
    pids="$(pgrep -d, -f 'wolf-(plasma|helper)|xrandr|xev|xprop' || true)"
    if [[ -n "$pids" ]]; then
        ps -o pid=,ppid=,etimes=,pcpu=,stat=,args= -p "$pids" || true
    else
        say "(nenhum processo correspondente encontrado)"
    fi
}

stage_multimonitor() {
    local helper
    helper="$(helper_path experimental wolf-plasma-multimonitor-0.3.sh)"
    say ""
    say "[3/5] PLASMA MULTIMONITOR 0.3"
    say "------------------------------"
    "$helper" status || true
    if ask_apply "Executar a reconciliação one-shot agora?"; then
        "$helper" apply
        "$helper" status || true
        show_wolf_processes
        if [[ "$MODE" == "vm" ]]; then
            say ""
            say "VM: valide apenas que não ficou watcher/polling permanente."
            say "O comportamento com múltiplos monitores será validado no hardware real."
        else
            say ""
            say "Hardware: teste monitor secundário, painel, KScreen e reconexão/hotplug."
        fi
        pause_enter
        result_prompt multimonitor
    else
        record multimonitor SKIP "não aplicado"
    fi
}

stage_gamepad() {
    local helper
    helper="$(helper_path stable wolf-gamepad-setup-0.3.sh)"
    say ""
    say "[4/5] GAMEPAD"
    say "-------------"
    if [[ "$MODE" == "vm" ]]; then
        say "Gamepad exige hardware/Bluetooth real para validação útil."
        if ask_apply "Mesmo assim abrir o Wolf Gamepad Setup?"; then
            "$helper"
            pause_enter
            result_prompt gamepad
        else
            record gamepad SKIP "VM sem hardware apropriado"
        fi
    else
        if ask_apply "Abrir o Wolf Gamepad Setup agora?"; then
            "$helper"
            pause_enter
            result_prompt gamepad
        else
            record gamepad SKIP "adiado"
        fi
    fi
}

stage_grub() {
    local helper
    helper="$(helper_path stable wolf-grub-manager-0.3.sh)"
    say ""
    say "[5/5] GRUB MANAGER"
    say "------------------"
    say "O helper é interativo. Para validação segura, use primeiro as opções de diagnóstico/leitura."
    if ask_apply "Abrir Wolf GRUB Manager agora?"; then
        "$helper"
        pause_enter
        result_prompt grub
    else
        record grub SKIP "adiado"
    fi
}

summary() {
    say ""
    say "============================================================"
    say "                 RESUMO DA VALIDAÇÃO"
    say "============================================================"
    column -t -s $'\t' "$REPORT" 2>/dev/null || cat "$REPORT"
    say ""
    say "Relatório salvo em: $REPORT"
}

header
stage_baseline || { summary; exit 1; }
stage_branding || { summary; exit 1; }
stage_multimonitor || { summary; exit 1; }
stage_gamepad || { summary; exit 1; }
stage_grub || { summary; exit 1; }
summary
