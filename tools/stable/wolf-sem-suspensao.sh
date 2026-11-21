#!/usr/bin/env bash
# Wolf Linux KDE/Wayland - Sem Suspensao (opt-in) + bloqueio com wallpaper Wolf
# Execucao: bash wolf-sem-suspensao.sh --apply [caminho-da-imagem]
#           bash wolf-sem-suspensao.sh --status
#           bash wolf-sem-suspensao.sh --undo
set -euo pipefail

NAME='Wolf Linux - Sem Suspensao Fix 1'
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/sem-suspensao-fix1"
SLEEP_CONF='/etc/systemd/sleep.conf.d/90-wolf-no-suspend.conf'
POWER_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/powerdevilrc"
LOCK_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/kscreenlockerrc"
WOLF_IMAGE='/usr/share/backgrounds/wolf-linux/wallpaper.png'
MARKER='# Wolf Linux - Sem Suspensao Fix 1 (opt-in)'
# Isolation hook is enabled only in an explicitly declared test harness.
if [[ "${WOLF_FIX_TEST_MODE:-0}" == 1 ]]; then
  [[ -n "${WOLF_FIX_TEST_ROOT:-}" ]] || { echo 'WOLF_FIX_TEST_ROOT required' >&2; exit 2; }
  SLEEP_CONF="${WOLF_FIX_TEST_ROOT}/etc/systemd/sleep.conf.d/90-wolf-no-suspend.conf"
fi
IDS=(ac battery lowbattery plugin image preview)

msg() { printf '[WOLF] %s\n' "$*"; }
fail() { printf '[ERRO] %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'HELP'
Wolf Linux - Sem Suspensao Fix 1 (opcional)

  --apply [IMAGEM]   Desativa suspensao/hibernacao e aplica o wallpaper Wolf
                     na tela de bloqueio. IMAGEM e opcional.
  --status           Mostra a situacao sem alterar o sistema.
  --undo             Restaura os valores anteriores e reativa a suspensao.

Execute como usuario normal do KDE (nao use sudo bash).
Apenas a instalacao da politica do systemd solicitara sudo.
HELP
}

k_args() {
  case "$1" in
    ac)         CFG="$POWER_FILE"; K_GROUP_ARGS=(--group AC --group SuspendAndShutdown); KEY=AutoSuspendAction ;;
    battery)    CFG="$POWER_FILE"; K_GROUP_ARGS=(--group Battery --group SuspendAndShutdown); KEY=AutoSuspendAction ;;
    lowbattery) CFG="$POWER_FILE"; K_GROUP_ARGS=(--group LowBattery --group SuspendAndShutdown); KEY=AutoSuspendAction ;;
    plugin)     CFG="$LOCK_FILE";  K_GROUP_ARGS=(--group Greeter); KEY=WallpaperPlugin ;;
    image)      CFG="$LOCK_FILE";  K_GROUP_ARGS=(--group Greeter --group Wallpaper --group org.kde.image --group General); KEY=Image ;;
    preview)    CFG="$LOCK_FILE";  K_GROUP_ARGS=(--group Greeter --group Wallpaper --group org.kde.image --group General); KEY=PreviewImage ;;
    *) fail "Identificador desconhecido: $1" ;;
  esac
}

check_user() {
  [[ $EUID -ne 0 ]] || fail 'Execute como usuario comum; o script solicitara sudo somente quando necessario.'
  command -v kreadconfig6 >/dev/null || fail 'kreadconfig6 nao encontrado; este fix exige KDE Plasma 6.'
  command -v kwriteconfig6 >/dev/null || fail 'kwriteconfig6 nao encontrado; este fix exige KDE Plasma 6.'
  command -v sudo >/dev/null || fail 'sudo nao encontrado.'
}

save_original() {
  local id="$1" value sentinel='__WOLF_FIX_1_UNSET_9824__'
  k_args "$id"
  value="$(kreadconfig6 --file "$CFG" "${K_GROUP_ARGS[@]}" --key "$KEY" --default "$sentinel")"
  if [[ "$value" == "$sentinel" ]]; then
    printf 'absent' > "$STATE_DIR/$id.status"
  else
    printf 'present' > "$STATE_DIR/$id.status"
    printf '%s' "$value" > "$STATE_DIR/$id.value"
  fi
}

write_value() {
  local id="$1" value="$2"
  k_args "$id"
  kwriteconfig6 --file "$CFG" "${K_GROUP_ARGS[@]}" --key "$KEY" "$value"
}

restore_value() {
  local id="$1"
  k_args "$id"
  if [[ "$(cat "$STATE_DIR/$id.status")" == 'absent' ]]; then
    kwriteconfig6 --file "$CFG" "${K_GROUP_ARGS[@]}" --key "$KEY" --delete
  else
    kwriteconfig6 --file "$CFG" "${K_GROUP_ARGS[@]}" --key "$KEY" "$(cat "$STATE_DIR/$id.value")"
  fi
}

status() {
  msg 'Situacao atual (nao faz alteracoes):'
  if [[ -r "$SLEEP_CONF" ]] && grep -Fqx "$MARKER" "$SLEEP_CONF"; then
    msg 'Politica systemd Wolf: instalada.'
  elif [[ -e "$SLEEP_CONF" ]]; then
    msg 'Politica systemd: existe um arquivo diferente no mesmo caminho (nao gerenciado).'
  else
    msg 'Politica systemd Wolf: nao instalada.'
  fi
  for id in ac battery lowbattery plugin image preview; do
    k_args "$id"
    printf '  %-11s %s\n' "$id" "$(kreadconfig6 --file "$CFG" "${K_GROUP_ARGS[@]}" --key "$KEY" --default '(padrao)')"
  done
  if [[ -d "$STATE_DIR" ]]; then msg 'Registro de restauracao: presente.'; else msg 'Registro de restauracao: ausente.'; fi
}

apply() {
  local pic="${1:-$WOLF_IMAGE}" tmp
  [[ -f "$pic" && -r "$pic" ]] || fail "Wallpaper nao encontrado: $pic. Informe o caminho com --apply /caminho/imagem.png"
  pic="$(realpath "$pic")"
  [[ -n "$pic" ]] || fail 'Caminho de wallpaper invalido.'
  if [[ -d "$STATE_DIR" ]]; then
    fail "Existe uma aplicacao anterior em $STATE_DIR; use --status ou --undo antes de reaplicar."
  fi
  if [[ -e "$SLEEP_CONF" || -L "$SLEEP_CONF" ]]; then
    fail "O arquivo $SLEEP_CONF ja existe; nao vou sobrescreve-lo."
  fi

  # Valide o sudo antes de modificar configuracoes do usuario.
  sudo -v || fail 'Nao foi possivel obter permissao para a politica de suspensao.'
  umask 077
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$pic" > "$STATE_DIR/wallpaper-used.txt"
  for id in "${IDS[@]}"; do save_original "$id"; done
  msg 'Configuracoes originais guardadas (apenas as seis chaves afetadas).'

  # Desliga auto-suspensao nos tres perfis. Nao altera brilho, tela apagada,
  # tempo de bloqueio, senha, nem acao do botao fisico de energia.
  write_value ac 0
  write_value battery 0
  write_value lowbattery 0
  # KDE usa um wallpaper separado para o bloqueio.
  write_value plugin org.kde.image
  write_value image "$pic"
  write_value preview "$pic"

  tmp="$(mktemp)"
  trap 'rm -f "${tmp:-}"' EXIT
  cat > "$tmp" <<CONF
$MARKER
# Remova pelo script --undo, nao edite diretamente.
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
CONF
  sudo install -D -m 0644 "$tmp" "$SLEEP_CONF" || {
    msg 'Falha na politica systemd. Para restaurar valores do KDE, execute --undo.'
    exit 1
  }
  printf 'ok\n' > "$STATE_DIR/applied"
  msg 'Suspensao e hibernacao desabilitadas (KDE + systemd).'
  msg "Papel de parede do bloqueio: $pic"
  msg 'O bloqueio de tela e o desligamento de video por inatividade continuam permitidos.'
  msg 'Encerre e inicie novamente a sessao KDE para recarregar o PowerDevil.'
  msg 'Depois, use Meta+L para testar o novo fundo da tela de bloqueio.'
  msg 'Para restaurar: bash wolf-sem-suspensao.sh --undo'
}

undo() {
  [[ -d "$STATE_DIR" ]] || fail 'Nenhuma aplicacao deste fix registrada.'
  for id in "${IDS[@]}"; do
    [[ -f "$STATE_DIR/$id.status" ]] || fail "Registro incompleto para $id; nao vou restaurar parcialmente."
  done
  if [[ -e "$SLEEP_CONF" || -L "$SLEEP_CONF" ]]; then
    grep -Fqx "$MARKER" "$SLEEP_CONF" || fail "O arquivo $SLEEP_CONF foi alterado externamente; nao vou remove-lo."
    sudo rm -- "$SLEEP_CONF"
    msg 'Politica de suspensao Wolf removida.'
  fi
  for id in "${IDS[@]}"; do restore_value "$id"; done
  rm -rf -- "$STATE_DIR"
  msg 'Preferencias anteriores do PowerDevil e da tela de bloqueio restauradas.'
  msg 'Suspensao volta a seguir as regras originais do sistema.'
}

main() {
  local cmd="${1:---help}"
  check_user
  case "$cmd" in
    --apply) shift; [[ $# -le 1 ]] || fail 'Somente um caminho de wallpaper e permitido.'; apply "${1:-}" ;;
    --status) [[ $# -eq 1 ]] || fail 'Uso: --status'; status ;;
    --undo|--restore) [[ $# -eq 1 ]] || fail 'Uso: --undo'; undo ;;
    --help|-h) usage ;;
    *) usage; exit 2 ;;
  esac
}
main "$@"
