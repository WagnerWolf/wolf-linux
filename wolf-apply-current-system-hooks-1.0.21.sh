#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

# Sincroniza uma instalação Wolf Linux já existente com as políticas
# persistentes usadas pelo instalador 1.0.21, sem reinstalar o sistema.

if (( EUID != 0 )); then
    exec sudo env WOLF_TARGET_USER="${WOLF_TARGET_USER:-$USER}" /usr/bin/env bash "$0" "$@"
fi

TARGET_USER="${1:-${WOLF_TARGET_USER:-${SUDO_USER:-}}}"

if [[ -z "$TARGET_USER" || "$TARGET_USER" == root ]] || ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "[ERRO] Não foi possível determinar o usuário principal." >&2
    echo "Uso: $0 <usuario>" >&2
    exit 1
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" ]] || {
    echo "[ERRO] Home do usuário $TARGET_USER não encontrada." >&2
    exit 1
}

echo "============================================================"
echo "       WOLF LINUX - SINCRONIZAR HOOKS DO SISTEMA"
echo "============================================================"
echo
echo "Usuário: $TARGET_USER"
echo

if ! command -v setfacl >/dev/null 2>&1; then
    echo ">> Instalando suporte a ACL..."
    pacman -S --needed --noconfirm acl
fi

install -d /usr/local/sbin /usr/local/bin /etc/pacman.d/hooks

# ---------------------------------------------------------------------------
# Cinnamon: X11-only, inclusive após upgrades do pacote cinnamon.
# ---------------------------------------------------------------------------
if pacman -Q cinnamon >/dev/null 2>&1 || [[ -d /usr/share/wayland-sessions ]]; then
    cat > /usr/local/sbin/wolf-disable-cinnamon-wayland <<'CINNAMON_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

for entry in /usr/share/wayland-sessions/cinnamon*.desktop; do
    rm -f -- "$entry"
done
CINNAMON_EOF
    chmod 755 /usr/local/sbin/wolf-disable-cinnamon-wayland

    cat > /etc/pacman.d/hooks/wolf-cinnamon-x11-only.hook <<'HOOK_EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = cinnamon

[Action]
Description = Wolf Linux: mantendo Cinnamon somente em X11...
When = PostTransaction
Exec = /usr/local/sbin/wolf-disable-cinnamon-wayland
HOOK_EOF

    /usr/local/sbin/wolf-disable-cinnamon-wayland
    echo "[OK] Cinnamon X11-only + hook persistente instalados."
fi

# ---------------------------------------------------------------------------
# Android SDK: root-owned, mas gravável pelo grupo android-sdk via ACL.
# Reaplica automaticamente após atualizações dos pacotes do SDK.
# ---------------------------------------------------------------------------
groupadd -f android-sdk
usermod -aG android-sdk "$TARGET_USER"

cat > /usr/local/sbin/wolf-fix-android-sdk-permissions <<'ANDROID_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SDK_ROOT=/opt/android-sdk
SDK_GROUP=android-sdk

getent group "$SDK_GROUP" >/dev/null 2>&1 || groupadd -f "$SDK_GROUP"
[[ -d "$SDK_ROOT" ]] || exit 0

setfacl -R -m "g:${SDK_GROUP}:rwX" "$SDK_ROOT"
find "$SDK_ROOT" -type d -exec setfacl -m "d:g:${SDK_GROUP}:rwx" {} +
ANDROID_EOF
chmod 755 /usr/local/sbin/wolf-fix-android-sdk-permissions

cat > /etc/pacman.d/hooks/wolf-android-sdk-permissions.hook <<'HOOK_EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = android-sdk
Target = android-sdk-build-tools
Target = android-sdk-platform-tools
Target = android-platform

[Action]
Description = Wolf Linux: reaplicando permissoes compartilhadas do Android SDK...
When = PostTransaction
Exec = /usr/local/sbin/wolf-fix-android-sdk-permissions
HOOK_EOF

/usr/local/sbin/wolf-fix-android-sdk-permissions

echo "[OK] Android SDK com grupo/ACL + hook persistente instalados."

# Flutter instalado manualmente em /opt deve permanecer gravável pelo usuário.
if [[ -d /opt/flutter ]]; then
    chown -R "$TARGET_USER:$TARGET_USER" /opt/flutter
    echo "[OK] /opt/flutter pertence a $TARGET_USER."
fi

cat > /usr/local/bin/wolf-android-licenses <<'LICENSE_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="/opt/flutter/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:$PATH"

if (( EUID == 0 )); then
    echo "[ERRO] Não execute as licenças Android com sudo/root." >&2
    exit 1
fi

if ! id -nG "$USER" | tr ' ' '\n' | grep -Fxq android-sdk; then
    echo "[ERRO] Sua sessão ainda não possui o grupo android-sdk." >&2
    echo "       Faça logout/login e tente novamente." >&2
    exit 1
fi

if [[ ! -w /opt/android-sdk ]]; then
    echo "[ERRO] /opt/android-sdk não está gravável nesta sessão." >&2
    echo "       Rode: sudo /usr/local/sbin/wolf-fix-android-sdk-permissions" >&2
    exit 1
fi

exec /opt/flutter/bin/flutter doctor --android-licenses
LICENSE_EOF
chmod 755 /usr/local/bin/wolf-android-licenses

echo "[OK] wolf-android-licenses instalado."

echo
echo "[INFO] Grupo android-sdk configurado para $TARGET_USER."
echo "       Se o grupo foi adicionado agora, faça logout/login antes de usar"
echo "       flutter doctor --android-licenses sem sudo."

echo
echo "Hooks instalados:"
printf '  %s\n' \
    /etc/pacman.d/hooks/wolf-cinnamon-x11-only.hook \
    /etc/pacman.d/hooks/wolf-android-sdk-permissions.hook
