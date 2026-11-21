#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(< "$SELF_DIR/VERSION")"
PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux-2.3.1}"
RELENG="${WOLF_RELENG:-/usr/share/archiso/configs/releng}"
SKIP_DEPS=0
RUN_SMOKE=1
RESUME=0
usage() {
  cat <<EOF
Wolf Linux $VERSION — KDE Plasma Wayland; Live Openbox
Uso: $0 [--project CAMINHO] [--skip-deps] [--no-smoke] [--resume]
Sem --resume: nunca sobrescreve um projeto existente.
Com --resume: valida a identidade do projeto interrompido e retoma o staging
sem apagar arquivos ou sobrescrever o instalador.
EOF
}
while (($#)); do
  case "$1" in
    --project) [[ $# -ge 2 ]] || { echo 'Falta caminho.' >&2; exit 2; }; PROJECT="$2"; shift 2 ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --no-smoke) RUN_SMOKE=0; shift ;;
    --resume) RESUME=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done
# A retomada e permitida apenas para um projeto da mesma versao/DevKit
# que ja possua o perfil releng; jamais sobrescreve arquivos arbitrarios.
[[ "$PROJECT" != "$SELF_DIR" && "$PROJECT" != "$SELF_DIR"/* ]] || { echo '[ERRO] Projeto de build não pode ficar dentro do DevKit.' >&2; exit 1; }
[[ "$PROJECT" != / && "$PROJECT" != "$HOME" ]] || { echo '[ERRO] Diretório de projeto inseguro.' >&2; exit 1; }
REUSING=0
if [[ -e "$PROJECT" || -L "$PROJECT" ]]; then
  if (( ! RESUME )); then
    echo "[ERRO] Projeto existe e foi preservado: $PROJECT" >&2
    echo '[DICA] Para retomar um preparador interrompido, use --resume.' >&2
    exit 1
  fi
  [[ -d "$PROJECT" && ! -L "$PROJECT" &&
     -f "$PROJECT/VERSION" && "$(< "$PROJECT/VERSION")" == "$VERSION" &&
     -f "$PROJECT/iso-profile/profiledef.sh" &&
     -f "$PROJECT/iso-profile/packages.x86_64" &&
     -f "$PROJECT/install/wolf-install.sh" &&
     -f "$PROJECT/package-profiles/packages.conf" &&
     -f "$PROJECT/tests/wolf-customize-iso-profile.sh" &&
     -f "$PROJECT/tests/wolf-stage-live-desktop.sh" &&
     -f "$PROJECT/tests/wolf-stage-live-ssh.sh" &&
     -f "$PROJECT/tests/wolf-build-iso.sh" &&
     ! -L "$PROJECT/assets" && ! -L "$PROJECT/assets/wallpapers" &&
     ! -L "$PROJECT/assets/wallpapers/wolf-linux-wallpaper.png" ]] || {
    echo '[ERRO] Projeto não reconhecido como staging Wolf 2.3.1 válido; nada foi alterado.' >&2
    exit 1
  }
  cmp -s "$SELF_DIR/install/wolf-install.sh" "$PROJECT/install/wolf-install.sh" || {
    echo '[ERRO] Instalador no projeto difere deste DevKit; retomada bloqueada.' >&2
    exit 1
  }
  REUSING=1
  echo "[INFO] Retomando projeto validado: $PROJECT"
fi
[[ -f "$SELF_DIR/tools/wolf-first-login-plasma.sh" ]] || { echo '[ERRO] Helper KDE first-login ausente.' >&2; exit 1; }
# Exec bits of *.sh may be lost by some archive/copy tools. Shell entrypoints are
# invoked via Bash; the new build tree gets executable permissions normalized.
for script in wolf-customize-iso-profile.sh wolf-stage-live-ssh.sh wolf-stage-live-desktop.sh wolf-build-iso.sh; do
  [[ -f "$SELF_DIR/tests/$script" ]] || { echo "[ERRO] Script do build ausente: $script" >&2; exit 1; }
done
# Dependências precisam ser instaladas ANTES de verificar releng.
# Com --needed, um archiso já registrado como instalado pode continuar
# com arquivos ausentes; reparar só esse pacote se for o caso.
if (( SKIP_DEPS == 0 )); then
  command -v pacman >/dev/null 2>&1 || { echo '[ERRO] Requer Arch Linux com pacman.' >&2; exit 1; }
  echo '[INFO] Instalando/verificando dependências do Archiso...'
  sudo pacman -S --needed --noconfirm archiso qemu-desktop edk2-ovmf rsync python shellcheck squashfs-tools
  if [[ ! -f "$RELENG/profiledef.sh" ]] && [[ "$RELENG" == /usr/share/archiso/configs/releng ]]; then
    echo '[AVISO] Releng ausente mesmo após verificar dependências; reinstalando somente archiso...'
    sudo pacman -S --noconfirm archiso
  fi
fi
if [[ ! -d "$RELENG" || ! -f "$RELENG/profiledef.sh" ]]; then
  echo "[ERRO] Perfil Archiso releng ausente/incompleto: $RELENG" >&2
  if (( SKIP_DEPS )); then
    echo '[DICA] Retire --skip-deps para instalar/verificar archiso.' >&2
  else
    echo '[DICA] Verifique os arquivos de archiso: pacman -Qkk archiso' >&2
  fi
  exit 1
fi
# O diretório é novo: não remover projetos ou arquivos existentes.
if (( ! REUSING )); then
  mkdir -p "$PROJECT"
  cp -a "$SELF_DIR"/. "$PROJECT"/
  cp -a "$RELENG" "$PROJECT/iso-profile"
  mkdir -p "$PROJECT/out" "$PROJECT/work"
fi
# Validação geral da identidade Wolf. Um projeto parcial pode faltar com MAIS
# arquivos além do wallpaper (ex.: SVG de Kickoff). Somente ausências são
# restauradas a partir das cópias originais, com hash conferido.
python3 "$SELF_DIR/tests/wolf-reconcile-assets-2.3.0.py" \
  --source "$SELF_DIR" --project "$PROJECT" --repair
chmod 755 "$PROJECT/tests/wolf-customize-iso-profile.sh" \
          "$PROJECT/tests/wolf-stage-live-ssh.sh" \
          "$PROJECT/tests/wolf-stage-live-desktop.sh" \
          "$PROJECT/tests/wolf-build-iso.sh"
chmod 755 "$PROJECT/tools/wolf-thorium"
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROJECT/iso-profile" bash "$PROJECT/tests/wolf-customize-iso-profile.sh"
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROJECT/iso-profile" bash "$PROJECT/tests/wolf-stage-live-ssh.sh"
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROJECT/iso-profile" bash "$PROJECT/tests/wolf-stage-live-desktop.sh"
# Confirmar que a ISO Live recebeu todos os recursos íntegros.
python3 "$SELF_DIR/tests/wolf-reconcile-assets-2.3.0.py" \
  --source "$SELF_DIR" --project "$PROJECT" \
  --staged "$PROJECT/iso-profile/airootfs/root/wolf-linux/assets"
if (( RUN_SMOKE )); then
  python3 "$SELF_DIR/tests/wolf-test-build-assets-2.3.0.py" "$SELF_DIR"
  python3 "$PROJECT/tests/wolf-test-kde-2.3.0.py" "$PROJECT"
  python3 "$PROJECT/tests/wolf-test-no-suspend-optional-2.3.0.py" "$PROJECT"
  python3 "$PROJECT/tests/wolf-test-pm-subtitle-iso.py" "$PROJECT"
  python3 "$PROJECT/tests/wolf-test-release-2.3.1.py" "$PROJECT"
fi
# Marcador de projeto concluído: o gerador só reutiliza builds preparados
# por este fluxo; nunca executa mkarchiso sobre diretórios arbitrários.
printf 'wolf-linux-iso-project=2.3.1\n' > "$PROJECT/.wolf-iso-project"
printf '[OK] Projeto pronto em %s\nPróximo: ./gerar-iso.sh (na pasta do DevKit)\n' "$PROJECT"
