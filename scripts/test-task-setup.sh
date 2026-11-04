#!/usr/bin/env bash
# Runs modules/task-runner/files/task-setup.sh against fake binaries and checks
# what it does with and without a Rust toolchain, and when a GPU never answers.
# The paths the script writes (/var/log, /etc/task-runner, /root/.cargo,
# /usr/local/cuda) are redirected into a temp directory, so no root is needed.
# Used by CI.
set -euo pipefail

cd "$(dirname "$0")/.."
script=$PWD/modules/task-runner/files/task-setup.sh

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

# run_case NAME TOOLCHAIN GPU NVIDIA_SMI_OK [RUSTC_OK]
# Leaves $work/NAME/{ready,calls,out} behind and sets $status to the exit code.
run_case() {
  local name="$1" toolchain="$2" gpu="$3" smi_ok="$4" rustc_ok="${5:-1}"
  local root=$work/$name
  mkdir -p "$root/bin" "$root/etc" "$root/log" "$root/cargo/bin" "$root/cuda/bin"
  : > "$root/calls"

  # Rewrite the absolute paths and prepend what Terraform prepends.
  {
    printf 'TASK_RUST_TOOLCHAIN=%s\nTASK_GPU=%s\n' "$toolchain" "$gpu"
    sed -e "s#/var/log#$root/log#g" \
      -e "s#/etc/task-runner#$root/etc#g" \
      -e "s#/root/.cargo#$root/cargo#g" \
      -e "s#/usr/local/cuda#$root/cuda#g" \
      -e "s#/tmp/rustup-init.sh#$root/rustup-init.sh#g" \
      "$script"
  } > "$root/setup.sh"

  fake() { # fake NAME BODY
    printf '#!/bin/sh\n%s\n' "$2" > "$root/bin/$1"
    chmod +x "$root/bin/$1"
  }
  fake dnf 'echo "dnf $*" >> "'"$root"'/calls"'
  fake systemctl 'exit 0'
  fake sudo 'echo "sudo $*" >> "'"$root"'/calls"'
  fake sleep 'exit 0'
  fake seq 'echo 1'
  fake curl 'case "$*" in
  *-o*) out=$(echo "$*" | sed "s/.*-o //; s/ .*//"); echo "echo rustup" > "$out"; echo "curl rustup" >> "'"$root"'/calls" ;;
  *api/token*) echo token ;;
  *ami-id*) echo ami-0123456789abcdef0 ;;
  esac'
  fake lscpu 'case "$*" in
  *-p*) printf "# CORE,SOCKET\n0,0\n1,0\n" ;;
  *) echo "Model name: Fake CPU 9000" ;;
  esac'
  if [ "$smi_ok" = 1 ]; then
    fake nvidia-smi 'echo "Fake GPU, 16384 MiB, 999.9"'
  else
    fake nvidia-smi 'echo "nvidia-smi" >> "'"$root"'/calls"; exit 9'
  fi
  if [ "$rustc_ok" = 1 ]; then
    fake rustc 'echo "rustc 1.99.1 (fake)"'
  else
    fake rustc 'exit 7'
  fi
  cp "$root/bin/rustc" "$root/cargo/bin/rustc"
  printf '#!/bin/sh\necho "Cuda compilation tools, release 12.9, V12.9.1"\n' > "$root/cuda/bin/nvcc"
  chmod +x "$root/cuda/bin/nvcc"

  status=0
  PATH="$root/bin:$PATH" bash "$root/setup.sh" > "$root/out" 2>&1 || status=$?
}

ready_has() { grep -qx -- "$2" "$work/$1/etc/ready"; }
ready_lacks() { ! grep -q -- "$2" "$work/$1/etc/ready"; }
ready_exists() { [ -f "$work/$1/etc/ready" ]; }
ready_missing() { [ ! -e "$work/$1/etc/ready" ]; }
calls_lack() { ! grep -q -- "$2" "$work/$1/calls"; }
calls_have() { grep -q -- "$2" "$work/$1/calls"; }
tmp_exists() { [ -f "$work/$1/etc/ready.tmp" ]; }
is_zero() { [ "$1" -eq 0 ]; }
is_nonzero() { [ "$1" -ne 0 ]; }

echo "empty toolchain:"
run_case empty "" 0 1
check "exits 0" is_zero "$status"
check "ready file exists" ready_exists empty
check "ready records rust_toolchain=none" ready_has empty "rust_toolchain=none"
check "ready has no rustc line" ready_lacks empty "^rustc="
check "ready still records the image" ready_has empty "image_id=ami-0123456789abcdef0"
check "sudo is never invoked" calls_lack empty "^sudo"
check "rustup is never downloaded" calls_lack empty "rustup"

echo "pinned toolchain:"
run_case pinned "1.99.1" 0 1
check "exits 0" is_zero "$status"
check "ready records the toolchain" ready_has pinned "rust_toolchain=1.99.1"
check "ready records rustc" ready_has pinned "rustc=rustc 1.99.1 (fake)"
check "rustup runs for root" calls_have pinned "^sudo -u root .*--default-toolchain 1.99.1"
check "rustup runs for ec2-user" calls_have pinned "^sudo -u ec2-user .*--default-toolchain 1.99.1"

echo "gpu that never answers:"
run_case gpu "1.99.1" 1 0
check "exits non-zero" is_nonzero "$status"
check "leaves no ready file" ready_missing gpu
check "nvidia-smi was invoked" calls_have gpu "^nvidia-smi"
check "setup got as far as ready.tmp" tmp_exists gpu

echo "broken toolchain:"
run_case badrustc "1.99.1" 0 1 0
check "exits non-zero" is_nonzero "$status"
check "leaves no ready file" ready_missing badrustc

echo "gpu that answers:"
run_case gpuok "1.99.1" 1 1
check "exits 0" is_zero "$status"
check "ready records the gpu" ready_has gpuok "gpu_model=Fake GPU"
check "ready records cuda" ready_has gpuok "cuda_version=12.9"

if [[ "$fail" -ne 0 ]]; then
  echo "task-setup tests FAILED"
  exit 1
fi
echo "task-setup tests passed"
