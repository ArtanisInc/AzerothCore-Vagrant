#!/bin/bash

set -Eeuo pipefail
source /vagrant/provision/scripts/00-env.sh

echo "========================================"
echo "Network sysctl optimization"
echo "========================================"

SYSCTL_FILE="/etc/sysctl.d/99-azerothcore.conf"

cat > "$SYSCTL_FILE" <<'SYSCTL_CONF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_tw_reuse=1
vm.swappiness=1
SYSCTL_CONF

echo "[OK] Configuration written: $SYSCTL_FILE"

if [ -f /proc/sys/net/ipv4/tcp_available_congestion_control ] && ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
    echo "[WARN] BBR is not available on this kernel. Applying other parameters only."
    if sysctl -p "$SYSCTL_FILE" --ignore 2>/dev/null; then
        echo "[OK] sysctl parameters applied (except BBR)."
    else
        echo "[WARN] Partial sysctl parameter application."
    fi
else
    if sysctl --system; then
        echo "[OK] sysctl parameters applied."
    else
        echo "[WARN] Partial failure while applying sysctl --system."
    fi
fi
