#!/bin/bash
# Task instance setup. Terraform prepends the shebang, the lifetime guard
# (`shutdown -h +<minutes>`), TASK_RUST_TOOLCHAIN and TASK_GPU to this file to
# form the user data. Tasks wait for /etc/task-runner/ready before they start.
set -euo pipefail

: "${TASK_RUST_TOOLCHAIN:?TASK_RUST_TOOLCHAIN must be set}"
TASK_GPU=${TASK_GPU:-0}

exec > >(tee -a /var/log/task-runner-setup.log) 2>&1

dnf install -y git gcc gcc-c++ make tar

# Amazon Linux 2023 images ship the SSM agent; an image without it gets it
# here, since Run Command is the only way a task reaches the instance.
if ! systemctl is-enabled --quiet amazon-ssm-agent 2>/dev/null; then
  dnf install -y amazon-ssm-agent
  systemctl enable --now amazon-ssm-agent
fi

# Run Command runs tasks as root; ec2-user is for Session Manager debugging.
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
for user in root ec2-user; do
  sudo -u "$user" -H sh /tmp/rustup-init.sh -y --no-modify-path \
    --profile minimal --default-toolchain "$TASK_RUST_TOOLCHAIN"
done
rm -f /tmp/rustup-init.sh

imds_token=$(curl -sSf -X PUT http://169.254.169.254/latest/api/token \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
image_id=$(curl -sSf -H "X-aws-ec2-metadata-token: $imds_token" \
  http://169.254.169.254/latest/meta-data/ami-id)
rustc_version=$(/root/.cargo/bin/rustc --version)
cpu_model=$(lscpu | sed -n 's/^Model name:[[:space:]]*//p')
physical_cores=$(lscpu -p=CORE,SOCKET | grep -v '^#' | sort -u | wc -l)

mkdir -p /etc/task-runner
cat > /etc/task-runner/ready.tmp <<READY
image_id=$image_id
rust_toolchain=$TASK_RUST_TOOLCHAIN
rustc=$rustc_version
cpu_model=$cpu_model
physical_cores=$physical_cores
READY

# A GPU profile is not ready until the driver answers; set -e fails setup
# (no ready file) when it never does, and the task reports the setup log.
if [ "$TASK_GPU" = 1 ]; then
  for _ in $(seq 60); do
    nvidia-smi >/dev/null 2>&1 && break
    sleep 5
  done
  gpu=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | head -n 1)
  nvcc=/usr/local/cuda/bin/nvcc
  cuda_version=$("$nvcc" --version | sed -n 's/.*release \([0-9.]*\).*/\1/p')
  cat >> /etc/task-runner/ready.tmp <<READY
gpu_model=$(echo "$gpu" | cut -d, -f1 | xargs)
gpu_memory=$(echo "$gpu" | cut -d, -f2 | xargs)
nvidia_driver=$(echo "$gpu" | cut -d, -f3 | xargs)
cuda_version=$cuda_version
READY
fi
mv /etc/task-runner/ready.tmp /etc/task-runner/ready
