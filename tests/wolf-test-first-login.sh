#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$PROJECT/tools/wolf-first-login-plasma.sh"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/.config/autostart" "$T/helpers" "$T/bin"
cat > "$T/bin/qdbus6" <<'STUB'
#!/usr/bin/env bash
printf 'wolf-panels-ready\n'
STUB
cat > "$T/helpers/wolf-plasma-branding-0.2.sh" <<'STUB'
#!/usr/bin/env bash
printf 'branding %s\n' "$*" >> "$HOME/calls"
[[ ! -f "$HOME/fail-branding" ]]
STUB
cat > "$T/helpers/wolf-plasma-multimonitor-0.3.sh" <<'STUB'
#!/usr/bin/env bash
printf 'multimonitor %s\n' "$*" >> "$HOME/calls"
[[ ! -f "$HOME/fail-multimonitor" ]]
STUB
chmod +x "$T/bin/qdbus6" "$T/helpers/"*.sh
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state"
export XDG_CURRENT_DESKTOP="KDE" WOLF_HELPERS_ROOT="$T/helpers" PATH="$T/bin:$PATH"
AUTO="$HOME/.config/autostart/wolf-first-login-plasma.desktop"
DONE="$HOME/.local/state/wolf-linux/first-login-plasma/completed"
printf 'fake launcher\n' > "$AUTO"
touch "$HOME/fail-multimonitor"
if "$RUNNER"; then
    echo '[ERRO] Nao propagou falha do MultiMonitor' >&2
    exit 1
fi
[[ ! -f "$DONE" && -f "$AUTO" ]]
[[ $(wc -l < "$HOME/calls") -eq 2 ]]
rm "$HOME/fail-multimonitor"
"$RUNNER"
[[ -f "$DONE" && ! -f "$AUTO" ]]
[[ $(wc -l < "$HOME/calls") -eq 4 ]]
"$RUNNER"
[[ $(wc -l < "$HOME/calls") -eq 4 ]]
[[ $(tail -n 2 "$HOME/calls") == $'branding apply\nmultimonitor apply' ]]
grep -Fq '[OK] Branding e MultiMonitor aplicados' "$HOME/.local/state/wolf-linux/first-login-plasma/setup.log"
echo '[OK] First-login: erro, retry, ordem, sucesso e sem nova execução'
