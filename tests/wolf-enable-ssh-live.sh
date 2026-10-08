#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

if [[ "${1:-}" == "--version" ]]; then
    if [[ -r /etc/wolf-linux-live-build ]]; then
        printf 'Wolf SSH Live 0.2 - %s\n' "$(head -n 1 /etc/wolf-linux-live-build)"
    else
        echo 'Wolf SSH Live 0.2'
    fi
    exit 0
fi

if (( EUID != 0 )); then
    echo "[ERRO] Execute como root."
    exit 1
fi

echo "======================================================"
echo "       WOLF LINUX - SSH LIVE v0.2 - VM/DIAGNÓSTICO"
echo "======================================================"

mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-wolf-vm.conf <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
EOF

echo
echo "Defina uma senha TEMPORÁRIA para o root desta sessão live."
echo "Essa senha desaparece quando a VM for reiniciada."
echo
passwd root

ssh-keygen -A
sshd -t
systemctl restart sshd

echo
echo "[OK] SSH iniciado."
echo
ip -brief address show | grep -v '^lo' || true

echo
echo "No host:"
echo "  ~/wolf-linux/tests/wolf-vm-ssh.sh"
echo "  (na ISO, o helper também está disponível como: wolf-ssh)"
echo
echo "ou:"
echo "  ssh -p 2222 root@127.0.0.1"
echo "======================================================"
