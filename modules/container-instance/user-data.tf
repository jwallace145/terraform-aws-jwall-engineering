locals {
  # Shell-quoted KEY='value' lines; both bash (`source`) and the records sync
  # (shlex) read them.
  config = {
    AWS_REGION             = local.region
    PARAMETER_PREFIX       = local.parameter_prefix
    IMAGE_REPOSITORY       = var.image_repository_url
    LOG_GROUP              = local.log_group_name
    SECRET_PARAMETERS      = join(" ", [for k in sort(keys(var.secret_parameters)) : "${k}=${var.secret_parameters[k]}"])
    CONTAINER_ENV          = join(" ", [for k in sort(keys(var.container_environment)) : "${k}=${var.container_environment[k]}"])
    RECORDS_BUCKET         = var.records_bucket_name == null ? "" : var.records_bucket_name
    RECORDS_PREFIX         = var.records_prefix
    RECORDS_CONTAINER_PATH = var.records_bucket_name == null || var.records_container_path == null ? "" : var.records_container_path
    HEALTH_LOG_PATTERN     = var.health_log_pattern
    HEALTH_SECONDS         = tostring(var.health_seconds)
    STOP_SIGNAL            = var.stop_signal
    STOP_POLL_SECONDS      = tostring(var.stop_poll_seconds)
    BOT_NAME               = var.bot_name
  }

  config_env = join("\n", [
    for k in sort(keys(local.config)) : "${k}='${replace(local.config[k], "'", "'\"'\"'")}'"
  ])

  reconcile_script    = file("${path.module}/files/container-reconcile.sh")
  records_sync_script = file("${path.module}/files/container-records-sync.py")

  user_data = templatefile("${path.module}/files/user-data.yaml.tftpl", {
    config_env          = local.config_env
    reconcile_script    = base64gzip(local.reconcile_script)
    records_sync_script = base64gzip(local.records_sync_script)
  })
}
