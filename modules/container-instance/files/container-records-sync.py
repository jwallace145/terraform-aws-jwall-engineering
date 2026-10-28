#!/usr/bin/env python3
"""Ship finished game records to S3 in a fixed, versioned layout.

Installed by the container-instance module as /usr/local/bin/container-records-sync
and run by a systemd timer, by the reconciler around every swap and once at
shutdown. Stdlib only (Python 3.9, Amazon Linux 2023); uploads through the AWS CLI.

Each container version writes into its own directory,
/var/lib/container-instance/records/<tag>/, so a game is always labelled with
the engine version that played it. Finished games (a terminal Result header,
untouched for MIN_AGE_SECONDS) are staged and uploaded as

  <prefix>pgn/schema=1/engine=<tag>/date=<YYYY-MM-DD>/<game_id>.pgn   the file, byte for byte
  <prefix>meta/schema=1/engine=<tag>/date=<YYYY-MM-DD>/<game_id>.json the sidecar below

Objects are only ever added: no overwrite of a shipped game, no deletes. A
change to the layout or the sidecar keys is a new schema number.
"""

import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional

SCHEMA = 1
MIN_AGE_SECONDS = 60
CONFIG_PATH = Path("/etc/container-instance/config.env")
RECORDS_ROOT = Path("/var/lib/container-instance/records")
STATE_ROOT = Path("/var/lib/container-instance/records-state")
INSTANCE_ID_CACHE = Path("/var/lib/container-instance/instance-id")
LOCK_PATH = "/run/lock/container-records-sync.lock"

_HEADER = re.compile(r'^\[([A-Za-z0-9_]+)\s+"((?:[^"\\]|\\.)*)"\]\s*$')
_FILE_GAME_ID = re.compile(r" - ([A-Za-z0-9]{8})\.pgn$")
_SITE_GAME_ID = re.compile(r"^https?://lichess\.org/([A-Za-z0-9]{8})(?:[/?#].*)?$")
_DATE = re.compile(r"^(\d{4})\.(\d{2})\.(\d{2})$")
_SAFE_DIR = re.compile(r"^[A-Za-z0-9._-]+$")
_RESULTS = {"1-0", "0-1", "1/2-1/2"}


@dataclass(frozen=True)
class Context:
    image_repository: str
    bot: str
    instance_id: str


def log(message: str) -> None:
    print(f"container-records-sync: {message}", file=sys.stderr, flush=True)


def load_config(path: Path) -> Dict[str, str]:
    """KEY='value' lines as written by user data (shell-quoted)."""
    config: Dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, raw = line.split("=", 1)
        parts = shlex.split(raw) if raw else []
        config[key] = parts[0] if parts else ""
    return config


def parse_headers(text: str) -> Dict[str, str]:
    """The PGN tag pairs at the top of the file, unescaped."""
    headers: Dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip():
            if headers:
                break
            continue
        match = _HEADER.match(line)
        if not match:
            break
        headers[match.group(1)] = re.sub(r"\\(.)", r"\1", match.group(2))
    return headers


def is_complete(headers: Dict[str, str]) -> bool:
    return headers.get("Result", "") in _RESULTS


def game_id_from(file_name: str, headers: Dict[str, str]) -> Optional[str]:
    match = _FILE_GAME_ID.search(file_name)
    if match:
        return match.group(1)
    match = _SITE_GAME_ID.match(headers.get("Site", ""))
    return match.group(1) if match else None


def normalise_date(value: Optional[str]) -> Optional[str]:
    match = _DATE.match(value or "")
    return "-".join(match.groups()) if match else None


def to_int(value: Optional[str]) -> Optional[int]:
    try:
        return int(value) if value is not None else None
    except ValueError:
        return None


def _relative(engine: str, date: str, game_id: str, ext: str) -> Path:
    return Path(f"schema={SCHEMA}") / f"engine={engine}" / f"date={date}" / f"{game_id}.{ext}"


def stage_all(records_root: Path, state_root: Path, context: Context, now: float) -> Dict[str, int]:
    """Stage every finished, not yet shipped game into state_root/outbox."""
    counts = {"staged": 0, "incomplete": 0, "recent": 0, "unparseable": 0, "already": 0}
    outbox, shipped = state_root / "outbox", state_root / "shipped"
    if not records_root.is_dir():
        return counts
    for engine_dir in sorted(p for p in records_root.iterdir() if p.is_dir()):
        engine = engine_dir.name
        if not _SAFE_DIR.match(engine):
            log(f"ignoring {engine_dir}: not a safe version name")
            continue
        for source in sorted(engine_dir.glob("*.pgn")):
            if now - source.stat().st_mtime < MIN_AGE_SECONDS:
                counts["recent"] += 1
                continue
            data = source.read_bytes()
            text = data.decode("utf-8", errors="replace")
            headers = parse_headers(text)
            if not is_complete(headers):
                counts["incomplete"] += 1
                continue
            game_id = game_id_from(source.name, headers)
            date = normalise_date(headers.get("UTCDate") or headers.get("Date"))
            if game_id is None or date is None:
                log(f"cannot place {source}: game id {game_id!r}, date {date!r}")
                counts["unparseable"] += 1
                continue
            meta_rel = _relative(engine, date, game_id, "json")
            if (shipped / "meta" / meta_rel).exists() or (outbox / "meta" / meta_rel).exists():
                counts["already"] += 1
                continue
            sidecar = {
                "schema": SCHEMA,
                "game_id": game_id,
                "engine_version": engine,
                "image": f"{context.image_repository}:{engine}",
                "bot": context.bot,
                "instance_id": context.instance_id,
                "white": headers.get("White"),
                "black": headers.get("Black"),
                "result": headers.get("Result"),
                "utc_date": date,
                "utc_time": headers.get("UTCTime"),
                "time_control": headers.get("TimeControl"),
                "variant": headers.get("Variant"),
                "white_elo": to_int(headers.get("WhiteElo")),
                "black_elo": to_int(headers.get("BlackElo")),
                "event": headers.get("Event"),
                "site": headers.get("Site"),
                "termination": headers.get("Termination"),
                "headers": headers,
                "source_file": source.name,
                "sha256": hashlib.sha256(data).hexdigest(),
                "synced_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            }
            pgn_path = outbox / "pgn" / _relative(engine, date, game_id, "pgn")
            meta_path = outbox / "meta" / meta_rel
            pgn_path.parent.mkdir(parents=True, exist_ok=True)
            meta_path.parent.mkdir(parents=True, exist_ok=True)
            pgn_path.write_bytes(data)
            # The sidecar is written last: its presence marks a complete stage.
            meta_path.write_text(json.dumps(sidecar, sort_keys=True, ensure_ascii=False) + "\n")
            counts["staged"] += 1
    return counts


def mark_shipped(state_root: Path) -> None:
    """Move uploaded files from the outbox into the local shipped record."""
    outbox, shipped = state_root / "outbox", state_root / "shipped"
    for path in sorted(outbox.rglob("*")):
        if path.is_file():
            target = shipped / path.relative_to(outbox)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(target))
    for path in sorted((p for p in outbox.rglob("*") if p.is_dir()), reverse=True):
        try:
            path.rmdir()
        except OSError:
            pass


def instance_id() -> str:
    if INSTANCE_ID_CACHE.is_file():
        return INSTANCE_ID_CACHE.read_text().strip()
    try:
        token_request = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        token = urllib.request.urlopen(token_request, timeout=2).read().decode()
        request = urllib.request.Request(
            "http://169.254.169.254/latest/meta-data/instance-id",
            headers={"X-aws-ec2-metadata-token": token},
        )
        value = urllib.request.urlopen(request, timeout=2).read().decode().strip()
    except OSError as exc:
        log(f"instance id unavailable: {exc}")
        return ""
    INSTANCE_ID_CACHE.write_text(value + "\n")
    return value


def _aws(*args: str) -> None:
    subprocess.run(["aws", *args], check=True)


def upload(state_root: Path, bucket: str, prefix: str) -> None:
    outbox = state_root / "outbox"
    for kind, content_type in (("pgn", "application/x-chess-pgn"), ("meta", "application/json")):
        source = outbox / kind
        if source.is_dir() and any(source.rglob("*")):
            _aws("s3", "sync", str(source), f"s3://{bucket}/{prefix}{kind}/",
                 "--content-type", content_type, "--no-progress", "--only-show-errors")


def main() -> int:
    config = load_config(CONFIG_PATH)
    bucket = config.get("RECORDS_BUCKET", "")
    if not bucket:
        return 0
    prefix = config.get("RECORDS_PREFIX", "records/")
    with open(LOCK_PATH, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        context = Context(
            image_repository=config.get("IMAGE_REPOSITORY", ""),
            bot=config.get("BOT_NAME", ""),
            instance_id=instance_id(),
        )
        counts = stage_all(RECORDS_ROOT, STATE_ROOT, context, now=time.time())
        upload(STATE_ROOT, bucket, prefix)
        mark_shipped(STATE_ROOT)
        _aws("ssm", "put-parameter", "--name", f"{config['PARAMETER_PREFIX']}/last-sync",
             "--type", "String", "--overwrite",
             "--value", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
        log(", ".join(f"{k} {v}" for k, v in counts.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
