#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${1:-$HOME/wolf-linux-2.3.0-rc1}"
[[ -d "$PROJECT" && -f "$PROJECT/VERSION" ]] || { echo "[ERRO] Projeto não encontrado: $PROJECT" >&2; exit 1; }
[[ "$(cat "$PROJECT/VERSION")" == '2.3.0-rc1' ]] || { echo '[ERRO] Versão do projeto incompatível.' >&2; exit 1; }
[[ -f "$PROJECT/iso-profile/profiledef.sh" && -d "$PROJECT/tests" ]] || { echo '[ERRO] ISO profile/testes ausentes; não continuar.' >&2; exit 1; }
[[ "$PROJECT" != "$SELF_DIR" ]] || { echo '[ERRO] Projeto e DevKit não podem ser o mesmo diretório.' >&2; exit 1; }
echo "Projeto existente validado: $PROJECT"
for script in wolf-customize-iso-profile.sh wolf-stage-live-ssh.sh wolf-stage-live-desktop.sh wolf-build-iso.sh; do
  [[ -f "$SELF_DIR/tests/$script" ]] || { echo "[ERRO] Ausente no DevKit: $script" >&2; exit 1; }
done
for script in wolf-customize-iso-profile.sh wolf-stage-live-ssh.sh wolf-stage-live-desktop.sh wolf-build-iso.sh; do
  install -m 0755 "$SELF_DIR/tests/$script" "$PROJECT/tests/$script"
  echo "[OK] Corrigido: tests/$script"
done
printf '\n[OK] Sem exclusão/recriação do projeto. Scripts atualizados.\n'
printf 'Para retomar o build, execute:\n  cd %q && python3 tests/wolf-test-kde-2.3.0-rc1.py . && bash tests/wolf-build-iso.sh\n' "$PROJECT"
printf '[AVISO] A etapa de build limpa somente o diretório work/ deste projeto antes de chamar mkarchiso.\n'
