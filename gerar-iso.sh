#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(< "$SELF_DIR/VERSION")"
[[ "$VERSION" == 2.3.1 ]] || { echo "[ERRO] Versão inesperada: $VERSION" >&2; exit 1; }
PROJECT="${WOLF_BUILD_PROJECT:-$HOME/wolf-linux-2.3.1}"
SKIP_DEPS=0
usage() {
  cat <<EOF
Wolf Linux $VERSION — gerador único de ISO (Release)
Uso: ./gerar-iso.sh [--project CAMINHO] [--skip-deps]

Se o projeto não existir, prepara dependências, copia o releng e gera a ISO.
Se ele já foi preparado por esta revisão, reutiliza-o sem sobrescrevê-lo.
Padrão: $PROJECT
EOF
}
while (($#)); do
  case "$1" in
    --project) [[ $# -ge 2 ]] || { echo '[ERRO] Informe o caminho.' >&2; exit 2; }; PROJECT="$2"; shift 2 ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "[ERRO] Opção desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done
# Mantemos o projeto fora da árvore do DevKit.
[[ "$PROJECT" != "$SELF_DIR" && "$PROJECT" != "$SELF_DIR"/* ]] || {
  echo '[ERRO] O projeto deve ficar fora da pasta do DevKit.' >&2; exit 1;
}
if [[ -e "$PROJECT" || -L "$PROJECT" ]]; then
  [[ -d "$PROJECT" && ! -L "$PROJECT" &&
     -f "$PROJECT/.wolf-iso-project" &&
     "$(< "$PROJECT/.wolf-iso-project")" == 'wolf-linux-iso-project=2.3.1' &&
     "$(< "$PROJECT/VERSION")" == "$VERSION" &&
     -f "$PROJECT/iso-profile/profiledef.sh" &&
     -f "$PROJECT/tests/wolf-build-iso.sh" ]] || {
    echo "[ERRO] Projeto existente não reconhecido ou incompleto: $PROJECT" >&2
    echo '[DICA] Se a preparação parou, execute no DevKit: bash preparar_ambiente_wolf_linux.sh --resume --skip-deps' >&2
    echo '[DICA] Se for um projeto diferente, use --project com um diretório novo.' >&2
    exit 1
  }
  echo "[INFO] Reutilizando projeto já preparado: $PROJECT"
else
  args=(--project "$PROJECT")
  if (( SKIP_DEPS )); then args+=(--skip-deps); fi
  bash "$SELF_DIR/preparar_ambiente_wolf_linux.sh" "${args[@]}"
fi
# Não iniciar mkarchiso sobre um projeto reutilizado com branding incompleto.
# Se faltarem arquivos, orientar retomada em vez de reparar silenciosamente
# durante a fase custosa de montagem da ISO.
python3 "$SELF_DIR/tests/wolf-reconcile-assets-2.3.0.py" \
  --source "$SELF_DIR" --project "$PROJECT" --check || {
  echo '[ERRO] Recursos do projeto incompletos. Execute: ./preparar_ambiente_wolf_linux.sh --resume --skip-deps' >&2
  exit 1
}
python3 "$SELF_DIR/tests/wolf-reconcile-assets-2.3.0.py" \
  --source "$SELF_DIR" --project "$PROJECT" \
  --staged "$PROJECT/iso-profile/airootfs/root/wolf-linux/assets" || {
  echo '[ERRO] Assets não foram totalmente transportados à ISO Live. Execute o preparador com --resume.' >&2
  exit 1
}
# Este é o ÚNICO comando público para geração. O construtor em tests/
# permanece como implementação interna e faz os preflights do projeto.
cd "$PROJECT"
WOLF_PROJECT="$PROJECT" bash "$PROJECT/tests/wolf-build-iso.sh"
echo "[OK] Verifique a ISO em: $PROJECT/out/"
