#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Uma única fonte de verdade para a versão: VERSION.
[[ -r "$SELF_DIR/VERSION" ]] || { echo '[ERRO] DevKit sem VERSION.' >&2; exit 1; }
DEVKIT_VERSION="$(< "$SELF_DIR/VERSION")"
[[ "$DEVKIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?$ ]] || {
    printf '[ERRO] VERSION inválido em %s/VERSION: %q\n' "$SELF_DIR" "$DEVKIT_VERSION" >&2
    exit 1
}
PROJECT="${WOLF_PROJECT:-$HOME/wolf-linux}"
RELENG="${WOLF_RELENG:-/usr/share/archiso/configs/releng}"
FORCE=0
SKIP_DEPS=0
RUN_SMOKE=1

usage() {
    cat <<USAGE
Wolf Linux ${DEVKIT_VERSION} - preparação limpa do ambiente

Uso:
  ./preparar_ambiente_wolf_linux.sh [opções]

Opções:
  --force         apaga o projeto existente sem perguntar
  --skip-deps     não executa pacman (útil para desenvolvimento/testes)
  --no-smoke      não executa o smoke test ao final
  --project PATH  usa outro diretório em vez de ~/wolf-linux
  -h, --help      mostra esta ajuda

Fluxo recomendado para uma reconstrução limpa:
  rm -rf ~/wolf-linux
  ./preparar_ambiente_wolf_linux.sh
USAGE
}

while (($#)); do
    case "$1" in
        --force) FORCE=1; shift ;;
        --skip-deps) SKIP_DEPS=1; shift ;;
        --no-smoke) RUN_SMOKE=0; shift ;;
        --project)
            [[ $# -ge 2 ]] || { echo '[ERRO] --project exige um caminho.' >&2; exit 2; }
            PROJECT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "[ERRO] Opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
    esac
done

say(){ printf '%s\n' "$*"; }
ok(){ printf '[OK] %s\n' "$*"; }
err(){ printf '[ERRO] %s\n' "$*" >&2; exit 1; }

write_stage_live_ssh() {
    local dst="$1"
    mkdir -p "$(dirname "$dst")"
    cat > "$dst" <<'STAGE_SSH_EOF'
#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${WOLF_PROJECT:-$(cd "$SELF_DIR/.." && pwd)}"
PROFILE="${WOLF_ISO_PROFILE:-$PROJECT/iso-profile}"
AIROOT="$PROFILE/airootfs"
PACKAGES_FILE="$PROFILE/packages.x86_64"
PROFILEDEF="$PROFILE/profiledef.sh"
SSH_SRC="$PROJECT/tests/wolf-enable-ssh-live.sh"

[[ -d "$PROFILE" ]] || { echo "[ERRO] Perfil Archiso não encontrado: $PROFILE" >&2; exit 1; }
[[ -f "$SSH_SRC" ]] || { echo "[ERRO] Helper SSH fonte ausente: $SSH_SRC" >&2; exit 1; }
[[ -f "$PACKAGES_FILE" ]] || { echo "[ERRO] packages.x86_64 ausente: $PACKAGES_FILE" >&2; exit 1; }
[[ -f "$PROFILEDEF" ]] || { echo "[ERRO] profiledef.sh ausente: $PROFILEDEF" >&2; exit 1; }

mkdir -p "$AIROOT/usr/local/bin" "$AIROOT/root/wolf-linux/tests"
install -m 0755 "$SSH_SRC" "$AIROOT/usr/local/bin/wolf-enable-ssh-live"
install -m 0755 "$SSH_SRC" "$AIROOT/root/wolf-linux/tests/wolf-enable-ssh-live.sh"
ln -sfn wolf-enable-ssh-live "$AIROOT/usr/local/bin/wolf-ssh"
grep -Fxq openssh "$PACKAGES_FILE" || printf '%s\n' openssh >> "$PACKAGES_FILE"

python - "$PROFILEDEF" <<'PYCODE'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); t=p.read_text()
required={
 '/usr/local/bin/wolf-enable-ssh-live':'0:0:755',
 '/root/wolf-linux/tests/wolf-enable-ssh-live.sh':'0:0:755',
}
m=re.search(r'file_permissions=\\(\\s*(.*?)\\s*\\)',t,flags=re.S)
if m:
    block=m.group(0)
    for path,mode in required.items():
        pat=re.compile(rf'^\\s*\\["{re.escape(path)}"\\]="[^"]*"\\s*$',flags=re.M)
        entry=f'  ["{path}"]="{mode}"'
        block=pat.sub(entry,block) if pat.search(block) else block[:-1].rstrip()+'\\n'+entry+'\\n)'
    t=t[:m.start()]+block+t[m.end():]
else:
    t+='\\nfile_permissions=(\\n'+''.join(f'  ["{p}"]="{m}"\\n' for p,m in required.items())+')\\n'
p.write_text(t)
PYCODE

[[ -x "$AIROOT/usr/local/bin/wolf-enable-ssh-live" ]] || { echo '[ERRO] Staging SSH: executável não criado.' >&2; exit 1; }
[[ -L "$AIROOT/usr/local/bin/wolf-ssh" ]] || { echo '[ERRO] Staging SSH: alias wolf-ssh não criado.' >&2; exit 1; }
grep -Fxq openssh "$PACKAGES_FILE" || { echo '[ERRO] Staging SSH: openssh ausente.' >&2; exit 1; }
printf '[OK] SSH live staged: %s\n' "$AIROOT/usr/local/bin/wolf-enable-ssh-live"
STAGE_SSH_EOF
    chmod 755 "$dst"
}

say '============================================================'
say " WOLF LINUX ${DEVKIT_VERSION} - PREPARAÇÃO LIMPA KDE/WAYLAND"
say '============================================================'
say "DevKit : $SELF_DIR"
say "Projeto: $PROJECT"
say "Releng : $RELENG"
say

[[ -f "$SELF_DIR/install/wolf-install.sh" ]] || err 'DevKit incompleto: install/wolf-install.sh ausente.'
[[ -f "$SELF_DIR/package-profiles/packages.conf" ]] || err 'DevKit incompleto: package-profiles/packages.conf ausente.'
[[ -f "$SELF_DIR/tests/wolf-customize-iso-profile.sh" ]] || err 'DevKit incompleto: customizador ausente.'
[[ -f "$SELF_DIR/tests/wolf-enable-ssh-live.sh" ]] || err 'DevKit incompleto: helper SSH live ausente.'

if (( SKIP_DEPS == 0 )); then
    say '[1/8] Instalando/verificando ferramentas de desenvolvimento...'
    sudo pacman -S --needed --noconfirm \
        archiso \
        qemu-desktop \
        edk2-ovmf \
        shellcheck \
        git \
        python \
        squashfs-tools \
        openssh
else
    say '[1/8] Dependências: ignoradas por --skip-deps.'
fi

# Necessário somente DEPOIS de instalar archiso; antes de qualquer remoção
# do projeto anterior. Se --skip-deps foi solicitado, não instalamos nada.
if [[ ! -d "$RELENG" ]]; then
    if (( SKIP_DEPS == 1 )); then
        err "Perfil releng não encontrado: $RELENG. Retire --skip-deps ou instale archiso manualmente."
    fi
    err "O pacote archiso foi verificado/instalado, mas o perfil releng não existe em $RELENG. Confira: pacman -Q archiso; pacman -Ql archiso."
fi
[[ -f "$RELENG/profiledef.sh" && -f "$RELENG/packages.x86_64" ]] || \
    err "Perfil releng incompleto em $RELENG (faltam profiledef.sh ou packages.x86_64)."
ok "Perfil Archiso releng disponível: $RELENG"

if [[ -e "$PROJECT" ]]; then
    if (( FORCE == 0 )); then
        say
        say "O projeto já existe: $PROJECT"
        read -r -p 'Apagar completamente e reconstruir do zero? [s/N]: ' answer
        [[ "$answer" =~ ^[sS]([iI][mM])?$ ]] || err 'Preparação cancelada; projeto existente preservado.'
    fi
    say '[2/8] Removendo projeto anterior...'
    rm -rf -- "$PROJECT"
else
    say '[2/8] Nenhum projeto anterior encontrado.'
fi

say '[3/8] Criando estrutura limpa...'
mkdir -p \
    "$PROJECT/install" \
    "$PROJECT/package-profiles" \
    "$PROJECT/tests" \
    "$PROJECT/tools/stable" \
    "$PROJECT/tools/experimental" \
    "$PROJECT/docs" \
    "$PROJECT/live-gui" \
    "$PROJECT/assets" \
    "$PROJECT/out" \
    "$PROJECT/work" \
    "$PROJECT/vm"

say '[4/8] Copiando perfil Archiso releng NOVO...'
cp -a "$RELENG" "$PROJECT/iso-profile"

say '[5/8] Copiando baseline KDE/Wayland do DevKit...'
cp -f "$SELF_DIR/install/wolf-install.sh" "$PROJECT/install/wolf-install.sh"
cp -f "$SELF_DIR/package-profiles/packages.conf" "$PROJECT/package-profiles/packages.conf"
cp -a "$SELF_DIR/tests/." "$PROJECT/tests/"
cp -a "$SELF_DIR/tools/." "$PROJECT/tools/"
cp -a "$SELF_DIR/docs/." "$PROJECT/docs/"
cp -a "$SELF_DIR/live-gui/." "$PROJECT/live-gui/"
cp -a "$SELF_DIR/branding-assets/." "$PROJECT/assets/"
cp -f "$SELF_DIR/README.md" "$PROJECT/README.md"
cp -f "$SELF_DIR/CHANGELOG.md" "$PROJECT/CHANGELOG.md"
cp -f "$SELF_DIR/RELEASE-NOTES-2.0.0.md" "$PROJECT/RELEASE-NOTES-2.0.0.md"
cp -f "$SELF_DIR/RELEASE-NOTES-2.1.0.md" "$PROJECT/RELEASE-NOTES-2.1.0.md"
cp -f "$SELF_DIR/THIRD-PARTY-LICENSES.md" "$PROJECT/THIRD-PARTY-LICENSES.md"
cp -f "$SELF_DIR/wolf-linux-logo.png" "$PROJECT/wolf-linux-logo.png"
cp -f "$SELF_DIR/preparar_ambiente_wolf_linux.sh" "$PROJECT/preparar_ambiente_wolf_linux.sh"
printf '%s\n' "$DEVKIT_VERSION" > "$PROJECT/VERSION"

chmod 755 "$PROJECT/install/wolf-install.sh" "$PROJECT/preparar_ambiente_wolf_linux.sh"
find "$PROJECT/tests" -maxdepth 1 -type f -name '*.sh' -exec chmod 755 {} +
find "$PROJECT/tools" -type f -name '*.sh' -exec chmod 755 {} +

# O preparador é autocontido: se o stager não veio no DevKit por qualquer
# motivo, recria uma cópia conhecida antes de customizar a ISO.
if [[ ! -f "$PROJECT/tests/wolf-stage-live-ssh.sh" ]]; then
    say '[AVISO] stager SSH ausente no DevKit; recriando a partir do preparador.'
    write_stage_live_ssh "$PROJECT/tests/wolf-stage-live-ssh.sh"
else
    chmod 755 "$PROJECT/tests/wolf-stage-live-ssh.sh"
fi

# Regra da baseline 2.0: nenhum helper legado de desktop deve entrar na árvore ativa.
if find "$PROJECT/tools" -type f \( -iname '*xfce*' -o -iname '*cinnamon*' -o -iname '*mate*' \) -print -quit | grep -q .; then
    err 'DevKit contaminado: helper de desktop legado encontrado em tools/.'
fi

say '[6/8] Personalizando a ISO a partir do releng limpo...'
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROJECT/iso-profile" \
    "$PROJECT/tests/wolf-customize-iso-profile.sh"

# Executa novamente de propósito: o SSH live é crítico para diagnóstico e o
# staging deve ser idempotente.
WOLF_PROJECT="$PROJECT" WOLF_ISO_PROFILE="$PROJECT/iso-profile" \
    "$PROJECT/tests/wolf-stage-live-ssh.sh"

say '[7/8] Validando staging da ISO ANTES do build...'
SSH_BIN="$PROJECT/iso-profile/airootfs/usr/local/bin/wolf-enable-ssh-live"
SSH_ALIAS="$PROJECT/iso-profile/airootfs/usr/local/bin/wolf-ssh"
SSH_COPY="$PROJECT/iso-profile/airootfs/root/wolf-linux/tests/wolf-enable-ssh-live.sh"
PACKAGES="$PROJECT/iso-profile/packages.x86_64"
PROFILEDEF="$PROJECT/iso-profile/profiledef.sh"

[[ -x "$SSH_BIN" ]] || err "SSH live não foi criado: $SSH_BIN"
[[ -L "$SSH_ALIAS" ]] || err "Alias wolf-ssh não foi criado: $SSH_ALIAS"
[[ "$(readlink "$SSH_ALIAS")" == 'wolf-enable-ssh-live' ]] || err 'Alias wolf-ssh aponta para destino inesperado.'
[[ -x "$SSH_COPY" ]] || err "Cópia de diagnóstico do SSH ausente: $SSH_COPY"
grep -Fxq openssh "$PACKAGES" || err 'openssh não foi inserido em iso-profile/packages.x86_64.'
grep -Fq '/usr/local/bin/wolf-enable-ssh-live' "$PROFILEDEF" || err 'profiledef.sh não contém permissão do SSH live.'
[[ -f "$PROJECT/iso-profile/airootfs/etc/wolf-linux-live-build" ]] || err 'Marcador da build live ausente.'

# Comparação exata, sem versões duplicadas/hardcoded, e diagnóstico legível.
LIVE_MARKER="$PROJECT/iso-profile/airootfs/etc/wolf-linux-live-build"
EXPECTED_MARKER="Wolf Linux ${DEVKIT_VERSION} KDE/Wayland Clean Baseline"
if ! cmp -s "$LIVE_MARKER" <(printf '%s\n' "$EXPECTED_MARKER"); then
    printf '[ERRO] Marcador da live diverge da versão do DevKit.\n' >&2
    printf '  Esperado: %q\n' "$EXPECTED_MARKER" >&2
    printf '  Encontrado (conteúdo exato): ' >&2
    sed -n '1,4l' "$LIVE_MARKER" >&2
    printf '  Arquivo: %s\n' "$LIVE_MARKER" >&2
    exit 1
fi
ok "Marcador da live consistente com VERSION ($DEVKIT_VERSION)."

ok "SSH live presente: $SSH_BIN"
ok "Alias presente: $SSH_ALIAS -> $(readlink "$SSH_ALIAS")"
ok 'openssh presente na lista da ISO.'
ok 'Perfil Archiso criado e customizado a partir do zero.'

say '[8/8] Smoke test...'
if (( RUN_SMOKE == 1 )); then
    WOLF_PROJECT="$PROJECT" TERM="${TERM:-xterm}" "$PROJECT/tests/wolf-smoke-test.sh"
else
    say '[AVISO] Smoke test pulado por --no-smoke.'
fi

say
say '============================================================'
say '[OK] AMBIENTE WOLF LINUX PRONTO'
say '============================================================'
say "Projeto: $PROJECT"
say "Versão : $DEVKIT_VERSION"
say
say 'Confirmação do SSH antes de gerar a ISO:'
say "  ls -l '$SSH_BIN' '$SSH_ALIAS'"
say
say 'Gerar a ISO:'
say "  cd '$PROJECT'"
say '  ./tests/wolf-build-iso.sh'
say
say 'Na live bootada:'
say '  cat /etc/wolf-linux-live-build'
say '  wolf-enable-ssh-live --version'
say '  wolf-enable-ssh-live'
say
