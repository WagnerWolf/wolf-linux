#!/usr/bin/env bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    exec /usr/bin/env bash "$0" "$@"
fi
set -Eeuo pipefail

if (( EUID != 0 )); then
    echo "[ERRO] Execute como root."
    exit 1
fi

echo "======================================================"
echo "       WOLF LINUX - HABILITAR SSH NA VM LIVE"
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

systemctl restart sshd

echo
echo "[OK] SSH iniciado."
echo
ip -brief address show | grep -v '^lo' || true

echo
echo "No host:"
echo "  ~/wolf-linux/tests/wolf-vm-ssh.sh"
echo
echo "ou:"
echo "  ssh -p 2222 root@127.0.0.1"
echo "======================================================"
