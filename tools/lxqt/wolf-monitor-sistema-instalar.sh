#!/usr/bin/env bash
# Wolf Linux LXQt — GNOME System Monitor: stable process sort and GTK4/libadwaita dark preference.
set -Eeuo pipefail

PROCESS_SCHEMA='org.gnome.gnome-system-monitor.proctree'
APPEARANCE_SCHEMA='org.gnome.desktop.interface'
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/wolf-linux/monitor-sistema"
MODE="${1:---install}"

usage() {
  cat <<'EOF'
Uso: bash wolf-monitor-sistema-instalar.sh [--install|--status|--restore]
  --install  instala o monitor e ajusta ordenação (Nome A-Z) e preferência GTK4 escura
  --status   mostra pacote, ordenação e preferência de cor, sem alterar
  --restore  recupera somente as preferências GSettings salvas antes da atualização
Sem alterações no tema GTK global, KDE, LXQt, btop ou nos outros serviços.
EOF
}

need_schemas() {
  command -v gsettings >/dev/null || { echo '[ERRO] gsettings indisponível.' >&2; exit 1; }
  local s
  for s in "$PROCESS_SCHEMA" "$APPEARANCE_SCHEMA"; do
    if ! gsettings list-schemas | grep -Fxq "$s"; then
      echo "[ERRO] Schema $s indisponível." >&2; exit 1
    fi
  done
  for s in sort-col sort-order; do
    gsettings get "$PROCESS_SCHEMA" "$s" >/dev/null || exit 1
  done
  gsettings get "$APPEARANCE_SCHEMA" color-scheme >/dev/null || exit 1
}

show_status() {
  if command -v pacman >/dev/null && pacman -Q gnome-system-monitor; then :
  else echo '[INFO] GNOME System Monitor não está instalado.'; fi
  if command -v gsettings >/dev/null && gsettings list-schemas | grep -Fxq "$PROCESS_SCHEMA"; then
    printf 'Ordenação: coluna=%s; sentido=%s (esperado: 0/0, Nome A-Z)\n' \
      "$(gsettings get "$PROCESS_SCHEMA" sort-col)" \
      "$(gsettings get "$PROCESS_SCHEMA" sort-order)"
  fi
  if command -v gsettings >/dev/null && gsettings list-schemas | grep -Fxq "$APPEARANCE_SCHEMA"; then
    printf 'GTK4/libadwaita color-scheme: %s (esperado: prefer-dark)\n' \
      "$(gsettings get "$APPEARANCE_SCHEMA" color-scheme)"
  fi
}

save_original() {
  mkdir -p "$BACKUP_ROOT"
  chmod 700 "$BACKUP_ROOT"
  if [[ ! -f "$BACKUP_ROOT/sort-original.conf" ]]; then
    { printf 'sort-col=%s\n' "$(gsettings get "$PROCESS_SCHEMA" sort-col)"
      printf 'sort-order=%s\n' "$(gsettings get "$PROCESS_SCHEMA" sort-order)"; } > "$BACKUP_ROOT/sort-original.conf"
    chmod 600 "$BACKUP_ROOT/sort-original.conf"
  fi
  # Existing 0.1 backups remain unchanged; this key gets its own original-value backup.
  if [[ ! -f "$BACKUP_ROOT/color-original.conf" ]]; then
    gsettings get "$APPEARANCE_SCHEMA" color-scheme > "$BACKUP_ROOT/color-original.conf"
    chmod 600 "$BACKUP_ROOT/color-original.conf"
  fi
}

restore_original() {
  local found=0 c o color
  if [[ -f "$BACKUP_ROOT/sort-original.conf" ]]; then
    c=$(sed -nE 's/^sort-col=(-?[0-9]+)$/\1/p' "$BACKUP_ROOT/sort-original.conf" | head -1)
    o=$(sed -nE 's/^sort-order=(-?[0-9]+)$/\1/p' "$BACKUP_ROOT/sort-original.conf" | head -1)
    [[ $c =~ ^-?[0-9]+$ && $o =~ ^-?[0-9]+$ ]] || { echo '[ERRO] Backup de ordenação inválido.' >&2; exit 1; }
    gsettings set "$PROCESS_SCHEMA" sort-col "$c"
    gsettings set "$PROCESS_SCHEMA" sort-order "$o"
    found=1
  fi
  if [[ -f "$BACKUP_ROOT/color-original.conf" ]]; then
    color="$(cat "$BACKUP_ROOT/color-original.conf")"
    case "$color" in
      "'default'"|"'prefer-light'"|"'prefer-dark'") ;;
      *) echo '[ERRO] Backup de cor inválido.' >&2; exit 1 ;;
    esac
    gsettings set "$APPEARANCE_SCHEMA" color-scheme "$color"
    found=1
  fi
  (( found == 1 )) || { echo '[ERRO] Nenhum backup encontrado.' >&2; exit 1; }
  echo '[OK] Preferências anteriores restauradas.'
}

case "$MODE" in
  --install)
    [[ $EUID -ne 0 ]] || { echo '[ERRO] Execute como usuário normal, sem sudo.' >&2; exit 1; }
    command -v pacman >/dev/null || { echo '[ERRO] Este instalador requer Arch Linux/pacman.' >&2; exit 1; }
    sudo pacman -S --needed gnome-system-monitor
    need_schemas
    save_original
    gsettings set "$PROCESS_SCHEMA" sort-col 0
    gsettings set "$PROCESS_SCHEMA" sort-order 0
    gsettings set "$APPEARANCE_SCHEMA" color-scheme 'prefer-dark'
    echo '[OK] Monitor do Sistema: processos Nome A-Z e preferência GTK4 escura.'
    echo '[INFO] Se ainda abrir claro, teste: ADW_DISABLE_PORTAL=1 gnome-system-monitor'
    show_status
    ;;
  --status) show_status ;;
  --restore)
    [[ $EUID -ne 0 ]] || { echo '[ERRO] Execute como usuário normal.' >&2; exit 1; }
    need_schemas
    restore_original
    ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
