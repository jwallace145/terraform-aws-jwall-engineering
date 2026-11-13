#!/usr/bin/env bash
# Runs modules/nat-instance/files/nat-setup.sh against fake binaries and checks
# what it configures, and that it fails without a default route. The sysctl
# file is redirected into a temp directory (NAT_SYSCTL_DIR), so no root is
# needed. Used by CI.
set -euo pipefail

cd "$(dirname "$0")/.."
script=$PWD/modules/nat-instance/files/nat-setup.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0
check() {
  local desc="$1"
  shift
  if "$@"; then
    printf '  ok    %s\n' "$desc"
  else
    printf '  FAIL  %s\n' "$desc"
    fail=1
  fi
}

# run_case NAME IP_OUTPUT CIDR...
# Leaves $work/NAME/{calls,sysctl.d} behind and sets $status to the exit code.
run_case() {
  local name="$1" ip_out="$2"
  shift 2
  local root=$work/$name
  mkdir -p "$root/bin" "$root/sysctl.d"
  : > "$root/calls"

  fake() { # fake NAME BODY
    printf '#!/bin/sh\n%s\n' "$2" > "$root/bin/$1"
    chmod +x "$root/bin/$1"
  }
  for tool in sysctl dnf iptables service systemctl; do
    fake "$tool" 'echo "'"$tool"' $*" >> "'"$root"'/calls"'
  done
  fake ip 'echo "ip $*" >> "'"$root"'/calls"
printf "%s\n" "'"$ip_out"'"'

  status=0
  PATH="$root/bin:$PATH" NAT_SYSCTL_DIR="$root/sysctl.d" \
    bash "$script" "$@" > "$root/out" 2>&1 || status=$?
}

# shellcheck disable=SC2329 # called indirectly through check
calls_has() { grep -qxF -- "$2" "$work/$1/calls"; }
# shellcheck disable=SC2329
calls_count() { grep -cF -- "$2" "$work/$1/calls" || true; }
# shellcheck disable=SC2329
count_is() { [ "$(calls_count "$1" "$2")" = "$3" ]; }
# shellcheck disable=SC2329
call_index() { grep -nxF -- "$2" "$work/$1/calls" | head -1 | cut -d: -f1; }

echo "default route on ens5, two CIDRs"
run_case ok "default via 10.0.0.1 dev ens5 proto dhcp src 10.0.0.5 metric 512" 10.0.2.0/24 10.0.3.0/24
check "exits 0" test "$status" -eq 0
check "sysctl file holds ip_forward = 1" \
  grep -qx 'net.ipv4.ip_forward = 1' "$work/ok/sysctl.d/90-nat.conf"
check "sysctl --system ran" calls_has ok "sysctl --system"
check "iptables-services installed" calls_has ok "dnf install -y iptables-services"
check "MASQUERADE for first CIDR on ens5" \
  calls_has ok "iptables -t nat -A POSTROUTING -o ens5 -s 10.0.2.0/24 -j MASQUERADE"
check "MASQUERADE for second CIDR on ens5" \
  calls_has ok "iptables -t nat -A POSTROUTING -o ens5 -s 10.0.3.0/24 -j MASQUERADE"
check "exactly two MASQUERADE rules" count_is ok "MASQUERADE" 2
check "FORWARD policy ACCEPT" calls_has ok "iptables -P FORWARD ACCEPT"
check "rules saved" calls_has ok "service iptables save"
check "iptables enabled and started" calls_has ok "systemctl enable --now iptables"
check "rules are added before they are saved" \
  test "$(call_index ok "iptables -P FORWARD ACCEPT")" -lt "$(call_index ok "service iptables save")"

echo "no default route"
run_case noroute "" 10.0.2.0/24
check "exits non-zero" test "$status" -ne 0
check "adds no MASQUERADE rule" count_is noroute "MASQUERADE" 0

echo "no CIDR arguments"
run_case nocidr "default via 10.0.0.1 dev ens5" 
check "exits non-zero" test "$status" -ne 0

exit "$fail"
