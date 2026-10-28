#!/usr/bin/env bash
set -euo pipefail
#
# container-reconcile: converge the `app` container to the desired image tag.
#
# Installed by the container-instance module. Runs once at boot
# (container-reconcile.service) and whenever Run Command calls
# container-reconcile-async after a deploy. Idempotent; one run at a time
# (a second run waits for the first, then converges to the newest desired tag).
#
#   container-reconcile            swap only if the desired tag is not running
#   container-reconcile --restart  swap even if it is (picks up a new secret)
#
# Guarantees:
#   - everything that can fail for an ordinary reason (pulling the image,
#     reading the secrets) happens BEFORE the running container is touched;
#   - the running container is asked to stop with ONE stop signal and is
#     never killed: the reconciler waits as long as it takes for it to exit
#     on its own (a bot finishes its game first);
#   - a new tag that does not start or does not become healthy is removed
#     and the previous tag is started again;
#   - every run ends with a terminal status: ok or failed:<reason>. While it
#     runs the status is waiting:<tag> or rolling-back:<reason>.

CONFIG=${CONTAINER_INSTANCE_CONFIG:-/etc/container-instance/config.env}
RECORDS_ROOT=${CONTAINER_INSTANCE_RECORDS_ROOT:-/var/lib/container-instance/records}
RECORDS_OWNER=${CONTAINER_INSTANCE_RECORDS_OWNER:-1000}
RUN_DIR=${CONTAINER_INSTANCE_RUN_DIR:-/run/container-instance}
LOCK_FILE=${CONTAINER_INSTANCE_LOCK_FILE:-/run/lock/container-reconcile.lock}
RECORDS_SYNC=${CONTAINER_INSTANCE_RECORDS_SYNC:-/usr/local/bin/container-records-sync}
ENV_FILE="$RUN_DIR/app.env"

# shellcheck source=/dev/null
source "$CONFIG"
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

# A status write that must not abort the run (progress reports).
status_soft() {
  status "$1" || log "could not write status $1; continuing"
}

# shellcheck disable=SC2317,SC2329 # invoked by the ERR trap (code differs by shellcheck version)
on_error() {
  status_soft "failed:unexpected error at line $1 of container-reconcile; see the journal"
}

running_image() {
  docker ps --filter "name=^app$" --format '{{.Image}}'
}

# No `| grep -q`: under pipefail an early-exiting grep can make docker die of
# SIGPIPE and the check report a running container as gone.
app_running() {
  [ -n "$(docker ps -q --filter "name=^app$")" ]
}

app_exists() {
  [ -n "$(docker ps -a -q --filter "name=^app$")" ]
}

ecr_login() {
  aws ecr get-login-password | docker login --username AWS --password-stdin "${IMAGE_REPOSITORY%%/*}" >/dev/null
}

pull() {
  docker pull --quiet "$IMAGE_REPOSITORY:$1" >/dev/null
}

records_sync() {
  if [ -n "$RECORDS_BUCKET" ]; then
    "$RECORDS_SYNC" || log "records sync failed; the next run retries"
  fi
}

# Secrets are read once, before anything is stopped, and kept in a 0600 file
# under /run until the run ends (the rollback needs them too).
write_env_file() {
  local pair name parameter value
  install -d -m 0700 "$RUN_DIR"
  (
    umask 077
    : >"$ENV_FILE"
    for pair in $SECRET_PARAMETERS; do
      name=${pair%%=*}
      parameter=${pair#*=}
      value=$(aws ssm get-parameter --name "$parameter" --with-decryption --query Parameter.Value --output text) || exit 1
      printf '%s=%s\n' "$name" "$value" >>"$ENV_FILE"
    done
    for pair in $CONTAINER_ENV; do
      printf '%s\n' "$pair" >>"$ENV_FILE"
    done
  )
}

start() {
  local tag=$1
  local volume=()
  if [ -n "$RECORDS_CONTAINER_PATH" ]; then
    install -d -o "$RECORDS_OWNER" -g "$RECORDS_OWNER" "$RECORDS_ROOT/$tag"
    volume=(--volume "$RECORDS_ROOT/$tag:$RECORDS_CONTAINER_PATH")
  fi
  if ! docker run --detach --name app --restart unless-stopped \
    --log-driver awslogs \
    --log-opt "awslogs-region=$AWS_REGION" \
    --log-opt "awslogs-group=$LOG_GROUP" \
    --log-opt "awslogs-stream=app-$tag-$(date -u +%Y%m%dT%H%M%SZ)" \
    --env-file "$ENV_FILE" \
    "${volume[@]}" \
    "$IMAGE_REPOSITORY:$tag" >/dev/null; then
    log "could not start $tag"
    return 1
  fi
  log "started $tag"
}

# Docker's dual logging (Docker >= 20.10) keeps `docker logs` working with the
# awslogs driver.
healthy() {
  local tag=$1
  sleep "$HEALTH_SECONDS"
  if [ "$(running_image)" != "$IMAGE_REPOSITORY:$tag" ]; then
    log "$tag is not running after ${HEALTH_SECONDS}s"
    return 1
  fi
  # The log is captured first: piping it into `grep -q` would let grep exit
  # at the first match and docker die of SIGPIPE, failing a healthy check.
  if [ -n "$HEALTH_LOG_PATTERN" ] && ! grep -q -- "$HEALTH_LOG_PATTERN" <<<"$(docker logs app 2>&1)"; then
    log "$tag did not log '$HEALTH_LOG_PATTERN' within ${HEALTH_SECONDS}s"
    return 1
  fi
}

remove_app() {
  docker rm --force app >/dev/null 2>&1 || true
}

stop_gracefully() {
  local tag=$1 waited=0
  records_sync
  # Never let the restart policy bring the container back once it exits.
  docker update --restart=no app >/dev/null || log "could not clear the restart policy of $tag"
  log "sending $STOP_SIGNAL to $tag; waiting for it to exit on its own"
  docker kill --signal="$STOP_SIGNAL" app >/dev/null || log "$tag had already exited"
  status_soft "waiting:$tag"
  while app_running; do
    sleep "$STOP_POLL_SECONDS"
    waited=$((waited + STOP_POLL_SECONDS))
    if [ $((waited % 60)) -lt "$STOP_POLL_SECONDS" ]; then
      log "still waiting for $tag to exit (${waited}s)"
      status_soft "waiting:$tag"
    fi
  done
  log "$tag exited after ${waited}s"
  # Ship the game that finished while we waited, under the version that played it.
  records_sync
  docker rm app >/dev/null 2>&1 || true
}

main() {
  local force=0 desired latest running current previous
  if [ "${1:-}" = "--restart" ]; then
    force=1
  fi

  exec 9>"$LOCK_FILE"
  flock 9
  trap 'rm -f "$ENV_FILE"' EXIT
  set -E
  trap 'on_error $LINENO' ERR

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

  # Everything that can fail for an ordinary reason happens before the
  # running container is touched.
  ecr_login
  if ! pull "$desired"; then
    status "failed:could not pull $desired"
    exit 1
  fi
  if ! write_env_file; then
    status "failed:could not read the secret parameters; $([ -n "$current" ] && echo "${current##*:} still running" || echo "nothing running")"
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

  # A deploy that arrived while we waited wins.
  latest=$(param_get desired-version)
  if [ -n "$latest" ] && [ "$latest" != "$desired" ]; then
    if pull "$latest"; then
      log "desired version changed to $latest while waiting"
      desired=$latest
    else
      log "could not pull $latest; continuing with $desired"
    fi
  fi

  if start "$desired" && healthy "$desired"; then
    param_put running-version "$desired"
    status ok
    exit 0
  fi

  log "last log lines of $desired:"
  docker logs --tail 50 app >&2 2>&1 || true
  remove_app
  if [ -z "$previous" ] || [ "$previous" = "$desired" ]; then
    status "failed:$desired did not become healthy; nothing to roll back to"
    exit 1
  fi
  status_soft "rolling-back:$desired did not become healthy"
  if start "$previous" && healthy "$previous"; then
    param_put running-version "$previous" || true
    status "failed:$desired did not become healthy; $previous restored"
  else
    remove_app
    status "failed:$desired did not become healthy; $previous did not restart"
  fi
  exit 1
}

main "$@"
