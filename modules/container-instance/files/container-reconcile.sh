#!/usr/bin/env bash
set -euo pipefail
#
# container-reconcile: converge the `app` container to the desired image tag.
#
# Installed by the container-instance module. Runs once at boot
# (container-reconcile.service) and whenever Run Command calls
# container-reconcile-async after a deploy. Idempotent; one run at a time.
#
#   container-reconcile            swap only if the desired tag is not running
#   container-reconcile --restart  swap even if it is (picks up a new secret)
#
# Guarantees:
#   - the running container is asked to stop with ONE stop signal and is
#     never killed: the reconciler waits as long as it takes for it to exit
#     on its own (a bot finishes its game first);
#   - a new tag that does not become healthy is removed and the previous tag
#     is started again;
#   - every outcome is written to the status parameter:
#     ok | waiting:<tag> | rolling-back:<reason> | failed:<reason>

# shellcheck source=/dev/null
source /etc/container-instance/config.env

RECORDS_ROOT=/var/lib/container-instance/records
ENV_DIR=/run/container-instance
ENV_FILE="$ENV_DIR/app.env"
LOCK_FILE=/run/lock/container-reconcile.lock
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

log() {
  echo "container-reconcile: $*" >&2
}

param_get() {
  local value
  if value=$(aws ssm get-parameter --name "$PARAMETER_PREFIX/$1" --query Parameter.Value --output text 2>/dev/null); then
    echo "$value"
  fi
}

param_put() {
  aws ssm put-parameter --name "$PARAMETER_PREFIX/$1" --type String --overwrite --value "$2" >/dev/null
}

status() {
  log "status: $1"
  param_put status "$1"
}

running_image() {
  docker ps --filter "name=^app$" --format '{{.Image}}'
}

app_exists() {
  docker ps -a -q --filter "name=^app$" | grep -q .
}

ecr_login() {
  aws ecr get-login-password | docker login --username AWS --password-stdin "${IMAGE_REPOSITORY%%/*}" >/dev/null
}

records_sync() {
  if [ -n "$RECORDS_BUCKET" ]; then
    /usr/local/bin/container-records-sync || log "records sync failed; the next run retries"
  fi
}

write_env_file() {
  local pair name parameter value
  install -d -m 0700 "$ENV_DIR"
  umask 077
  : >"$ENV_FILE"
  for pair in $SECRET_PARAMETERS; do
    name=${pair%%=*}
    parameter=${pair#*=}
    value=$(aws ssm get-parameter --name "$parameter" --with-decryption --query Parameter.Value --output text)
    printf '%s=%s\n' "$name" "$value" >>"$ENV_FILE"
  done
  for pair in $CONTAINER_ENV; do
    printf '%s\n' "$pair" >>"$ENV_FILE"
  done
}

start() {
  local tag=$1
  local volume=()
  if [ -n "$RECORDS_CONTAINER_PATH" ]; then
    install -d -o 1000 -g 1000 "$RECORDS_ROOT/$tag"
    volume=(--volume "$RECORDS_ROOT/$tag:$RECORDS_CONTAINER_PATH")
  fi
  write_env_file
  docker run --detach --name app --restart unless-stopped \
    --log-driver awslogs \
    --log-opt "awslogs-region=$AWS_REGION" \
    --log-opt "awslogs-group=$LOG_GROUP" \
    --log-opt "awslogs-stream=app-$tag-$(date -u +%Y%m%dT%H%M%SZ)" \
    --env-file "$ENV_FILE" \
    "${volume[@]}" \
    "$IMAGE_REPOSITORY:$tag" >/dev/null
  rm -f "$ENV_FILE"
  log "started $tag"
}

healthy() {
  local tag=$1
  sleep "$HEALTH_SECONDS"
  if [ "$(running_image)" != "$IMAGE_REPOSITORY:$tag" ]; then
    log "$tag is not running after ${HEALTH_SECONDS}s"
    return 1
  fi
  if [ -n "$HEALTH_LOG_PATTERN" ] && ! docker logs app 2>&1 | grep -q -- "$HEALTH_LOG_PATTERN"; then
    log "$tag did not log '$HEALTH_LOG_PATTERN' within ${HEALTH_SECONDS}s"
    return 1
  fi
}

stop_gracefully() {
  local tag=$1 waited=0
  records_sync
  # Never let the restart policy bring the container back once it exits.
  docker update --restart=no app >/dev/null
  log "sending $STOP_SIGNAL to $tag; waiting for it to exit on its own"
  docker kill --signal="$STOP_SIGNAL" app >/dev/null
  status "waiting:$tag"
  while docker ps -q --filter "name=^app$" | grep -q .; do
    sleep "$STOP_POLL_SECONDS"
    waited=$((waited + STOP_POLL_SECONDS))
    if [ $((waited % 60)) -lt "$STOP_POLL_SECONDS" ]; then
      log "still waiting for $tag to exit (${waited}s)"
      status "waiting:$tag"
    fi
  done
  log "$tag exited after ${waited}s"
  # Ship the game that finished while we waited, under the version that played it.
  records_sync
  docker rm app >/dev/null
}

main() {
  local force=0 desired running current previous
  if [ "${1:-}" = "--restart" ]; then
    force=1
  fi

  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "another reconcile is running"
    exit 0
  fi

  desired=$(param_get desired-version)
  if [ -z "$desired" ]; then
    log "no desired version set; nothing to do"
    exit 0
  fi
  running=$(param_get running-version)
  current=$(running_image)

  if [ "$current" = "$IMAGE_REPOSITORY:$desired" ] && [ "$force" -eq 0 ]; then
    param_put running-version "$desired"
    status ok
    exit 0
  fi

  ecr_login
  if ! docker pull --quiet "$IMAGE_REPOSITORY:$desired" >/dev/null; then
    status "failed:could not pull $desired"
    exit 1
  fi

  previous=""
  if [ -n "$current" ]; then
    previous=${current##*:}
    stop_gracefully "$previous"
  elif app_exists; then
    docker rm app >/dev/null
  fi
  if [ -z "$previous" ]; then
    previous=$running
  fi

  start "$desired"
  if healthy "$desired"; then
    param_put running-version "$desired"
    status ok
    exit 0
  fi

  log "last log lines of $desired:"
  docker logs --tail 50 app >&2 2>&1 || true
  docker rm --force app >/dev/null
  if [ -z "$previous" ] || [ "$previous" = "$desired" ]; then
    status "failed:$desired did not become healthy; nothing to roll back to"
    exit 1
  fi
  status "rolling-back:$desired did not become healthy"
  start "$previous"
  if healthy "$previous"; then
    param_put running-version "$previous"
    status "failed:$desired did not become healthy; $previous restored"
  else
    status "failed:$desired did not become healthy; $previous did not restart"
  fi
  exit 1
}

main "$@"
