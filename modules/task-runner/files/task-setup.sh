#!/bin/bash
# Task instance setup. Terraform prepends the shebang, the lifetime guard
# (`shutdown -h +<minutes>`) and TASK_RUST_TOOLCHAIN to this file to form
# the user data. Tasks wait for /etc/task-runner/ready before they start.
set -euo pipefail

: "${TASK_RUST_TOOLCHAIN:?TASK_RUST_TOOLCHAIN must be set}"

exec > >(tee -a /var/log/task-runner-setup.log) 2>&1

dnf install -y git gcc gcc-c++ make tar

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
mv /etc/task-runner/ready.tmp /etc/task-runner/ready
