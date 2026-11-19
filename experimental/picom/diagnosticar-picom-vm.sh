#!/usr/bin/env bash
# Diagnóstico somente leitura: nenhuma alteração na sessão, sem sudo.
set -uo pipefail
printf '%s\n' '=== WOLF PICOM / VM - DIAGNÓSTICO ==='
printf 'Sessão: XDG_SESSION_TYPE=%s, XDG_CURRENT_DESKTOP=%s, DISPLAY=%s\n' \
  "${XDG_SESSION_TYPE:-indefinido}" "${XDG_CURRENT_DESKTOP:-indefinido}" "${DISPLAY:-indefinido}"
printf '\n%s\n' '=== HIPERVISOR ==='
if command -v systemd-detect-virt >/dev/null 2>&1; then
  systemd-detect-virt --vm || printf '%s\n' 'Nenhuma VM detectada'
else
  printf '%s\n' 'systemd-detect-virt indisponível'
fi
printf '\n%s\n' '=== GPU / DRIVER ==='
if command -v lspci >/dev/null 2>&1; then
  lspci -nnk | grep -Ei -A 3 'VGA compatible|3D controller|Display controller' || true
else
  printf '%s\n' 'lspci ausente (pacote pciutils)'
fi
printf '\n%s\n' '=== RENDERIZADOR OPENGL ==='
if command -v glxinfo >/dev/null 2>&1; then
  glxinfo -B 2>&1 | head -40
else
  printf '%s\n' 'glxinfo ausente (pacote mesa-utils; instalação não necessária para corrigir)'
fi
printf '\n%s\n' '=== PROCESSOS PICOM ==='
pgrep -a -u "$(id -u)" -x picom || printf '%s\n' 'Nenhum Picom ativo'
printf '\n%s\n' '=== PERFIS LOCAIS ==='
for f in "$HOME/.config/picom/picom.conf" "$HOME/.config/autostart/wolf-picom.desktop"; do
  if [[ -f "$f" ]]; then printf '%s\n' "-- $f"; grep -E '^([[:space:]]*(backend|vsync|shadow|unredir-if-possible)[[:space:]]*=|Exec=|Hidden=|TryExec=)' "$f" || true
  else printf '%s\n' "[AUSENTE] $f"; fi
done
if [[ -x "$HOME/.local/bin/wolf-picom-session" ]]; then
  printf '\n%s\n' '=== DECISÃO DO GUARD ==='
  "$HOME/.local/bin/wolf-picom-session" --status
fi
