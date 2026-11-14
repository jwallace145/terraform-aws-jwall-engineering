#!/usr/bin/env bash
# Turns an AL2023 instance into a NAT: forwards IPv4 and masquerades traffic
# from each source CIDR (the script's arguments) out of the default-route
# interface. Run once from cloud-init user data.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: nat-setup.sh SOURCE_CIDR..." >&2
  exit 2
fi

sysctl_dir=${NAT_SYSCTL_DIR:-/etc/sysctl.d}

echo 'net.ipv4.ip_forward = 1' > "$sysctl_dir/90-nat.conf"
sysctl --system

dnf install -y iptables-services

iface=$(ip route show default | awk '/^default/ { for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
if [ -z "$iface" ]; then
  echo "no default route found: cannot pick the interface to masquerade on" >&2
  exit 1
fi

for cidr in "$@"; do
  iptables -t nat -A POSTROUTING -o "$iface" -s "$cidr" -j MASQUERADE
done
iptables -P FORWARD ACCEPT

service iptables save
systemctl enable --now iptables
