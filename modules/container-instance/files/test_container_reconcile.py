"""Behavioural tests for container-reconcile.sh.

The real script runs against fake `docker`, `aws`, `sleep` and `flock`
binaries that model the app container's state and the SSM parameters in a
JSON file. Stdlib only; needs bash and python3.

Run: python3 -m unittest discover -s modules/container-instance/files -p 'test_*.py'
"""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path
from typing import Any, Dict, List, Optional

SCRIPT = Path(__file__).resolve().parent / "container-reconcile.sh"
REPO = "123456789012.dkr.ecr.us-east-1.amazonaws.com/jwall-engineering-rusty-chess"
PREFIX = "/jwall-engineering/rusty-chess/bot"
SECRET = "/jwall-engineering/rusty-chess/lichess-token"

FAKE_DOCKER = r'''#!/usr/bin/env python3
import json, os, sys
import fcntl
if sys.argv[1:2] == ["login"]:
    sys.stdin.read()  # before locking: the aws fake feeding stdin needs the lock
state_path = os.environ["FAKE_STATE"]
_lock = open(state_path + ".lock", "w")
fcntl.flock(_lock, fcntl.LOCK_EX)
s = json.load(open(state_path))
args = sys.argv[1:]
s["calls"].append(["docker"] + args)
app = s["containers"].get("app")
running = app is not None and app["state"] in ("running", "stopping")
code, out = 0, ""
cmd = args[0]
if cmd == "ps":
    show_all = "-a" in args
    if app is not None and (running or show_all):
        out = (app["image"] if "--format" in args else "c0ffee") + "\n"
elif cmd == "kill":
    if not running or os.environ.get("FAKE_KILL_NOT_RUNNING") == "1":
        if app is not None:
            app["state"] = "exited"
        code, out = 1, "Error response from daemon: container is not running\n"
    else:
        app["signals"] = app.get("signals", 0) + 1
        app["state"] = "stopping"
        app["polls_left"] = int(os.environ.get("FAKE_STOP_POLLS", "2"))
elif cmd == "update":
    if app is None:
        code = 1
    else:
        app["restart"] = "no"
elif cmd == "rm":
    if app is None or (running and "--force" not in args):
        code = 1
    else:
        s["containers"].pop("app")
elif cmd == "run":
    image = args[-1]
    tag = image.rsplit(":", 1)[1]
    env_file = args[args.index("--env-file") + 1]
    if app is not None or not os.path.exists(env_file):
        code = 125
    elif tag in os.environ.get("FAKE_RUN_FAIL", "").split(","):
        code = 125
    else:
        unhealthy = tag in os.environ.get("FAKE_UNHEALTHY", "").split(",")
        s["containers"]["app"] = {"image": image, "state": "exited" if unhealthy else "running",
                                  "restart": "unless-stopped", "env": open(env_file).read()}
        s["started"].append(tag)
elif cmd == "pull":
    tag = args[-1].rsplit(":", 1)[1]
    if tag in os.environ.get("FAKE_PULL_FAIL", "").split(","):
        code = 1
elif cmd == "logs":
    if app is not None and app["state"] == "running":
        out = "You're now connected and awaiting challenges.\n"
        if os.environ.get("FAKE_LONG_LOGS") == "1":
            out += "a long game log line\n" * 200000
json.dump(s, open(state_path, "w"))
_lock.close()
try:
    sys.stdout.write(out)
    sys.stdout.flush()
except BrokenPipeError:
    sys.exit(141)  # like a real process killed by SIGPIPE
sys.exit(code)
'''

FAKE_AWS = r'''#!/usr/bin/env python3
import json, os, re, sys
import fcntl
state_path = os.environ["FAKE_STATE"]
_lock = open(state_path + ".lock", "w")
fcntl.flock(_lock, fcntl.LOCK_EX)
s = json.load(open(state_path))
args = sys.argv[1:]
s["calls"].append(["aws"] + args)
code, out = 0, ""
def opt(name):
    return args[args.index(name) + 1]
if args[:2] == ["ssm", "get-parameter"]:
    name = opt("--name")
    if os.environ.get("FAKE_SECRET_FAIL") == "1" and "--with-decryption" in args:
        code = 255
    elif name in s["params"]:
        out = s["params"][name] + "\n"
    else:
        code = 255
elif args[:2] == ["ssm", "put-parameter"]:
    name, value = opt("--name"), opt("--value")
    fail = os.environ.get("FAKE_PUT_FAIL_MATCH")
    if fail and re.search(fail, value) and not s.get("put_failed"):
        s["put_failed"] = True
        code = 255
    else:
        s["params"][name] = value
        s["puts"].append([name, value])
elif args[:2] == ["ecr", "get-login-password"]:
    out = "password\n"
json.dump(s, open(state_path, "w"))
sys.stdout.write(out)
sys.exit(code)
'''

FAKE_SLEEP = r'''#!/usr/bin/env python3
import json, os
import fcntl
state_path = os.environ["FAKE_STATE"]
_lock = open(state_path + ".lock", "w")
fcntl.flock(_lock, fcntl.LOCK_EX)
s = json.load(open(state_path))
s["sleeps"] += 1
app = s["containers"].get("app")
if app is not None and app["state"] == "stopping":
    app["polls_left"] -= 1
    if app["polls_left"] <= 0:
        app["state"] = "exited"
    later = os.environ.get("FAKE_DESIRED_DURING_WAIT")
    if later:
        s["params"][os.environ["FAKE_PREFIX"] + "/desired-version"] = later
json.dump(s, open(state_path, "w"))
'''

FAKE_FLOCK = "#!/bin/sh\nexit 0\n"
FAKE_SYNC = '#!/bin/sh\necho sync >> "$FAKE_SYNC_LOG"\n'


class Reconciler:
    def __init__(self, tmp: Path) -> None:
        self.tmp = tmp
        self.bin = tmp / "bin"
        self.bin.mkdir()
        for name, body in (("docker", FAKE_DOCKER), ("aws", FAKE_AWS), ("sleep", FAKE_SLEEP),
                           ("flock", FAKE_FLOCK), ("container-records-sync", FAKE_SYNC)):
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        self.state_path = tmp / "state.json"
        self.sync_log = tmp / "sync.log"
        self.sync_log.write_text("")
        self.config = tmp / "config.env"
        self.config.write_text(textwrap.dedent(f"""\
            AWS_REGION='us-east-1'
            BOT_NAME='rusty-chess-bot'
            CONTAINER_ENV='ENGINE_HASH_MB=128'
            HEALTH_LOG_PATTERN='awaiting challenges'
            HEALTH_SECONDS='90'
            IMAGE_REPOSITORY='{REPO}'
            LOG_GROUP='/jwall-engineering/rusty-chess/bot'
            PARAMETER_PREFIX='{PREFIX}'
            RECORDS_BUCKET='jwall-engineering-rusty-chess-records'
            RECORDS_CONTAINER_PATH='/opt/lichess-bot/game_records'
            RECORDS_PREFIX='records/'
            SECRET_PARAMETERS='LICHESS_TOKEN={SECRET}'
            STOP_POLL_SECONDS='15'
            STOP_SIGNAL='SIGINT'
            """))

    def seed(self, params: Dict[str, str], app_tag: Optional[str], app_state: str = "running") -> None:
        containers: Dict[str, Any] = {}
        if app_tag is not None:
            containers["app"] = {"image": f"{REPO}:{app_tag}", "state": app_state, "restart": "unless-stopped"}
        full = {f"{PREFIX}/{k}": v for k, v in params.items()}
        full[SECRET] = "lip_secret"
        self.state_path.write_text(json.dumps({"containers": containers, "params": full, "calls": [],
                                               "puts": [], "started": [], "sleeps": 0}))

    def run(self, *args: str, **env: str) -> subprocess.CompletedProcess:
        environ = dict(os.environ)
        environ.update({
            "PATH": f"{self.bin}:{environ['PATH']}",
            "FAKE_STATE": str(self.state_path),
            "FAKE_SYNC_LOG": str(self.sync_log),
            "FAKE_PREFIX": PREFIX,
            "CONTAINER_INSTANCE_CONFIG": str(self.config),
            "CONTAINER_INSTANCE_RECORDS_ROOT": str(self.tmp / "records"),
            "CONTAINER_INSTANCE_RECORDS_OWNER": str(os.getuid()),
            "CONTAINER_INSTANCE_RUN_DIR": str(self.tmp / "run"),
            "CONTAINER_INSTANCE_LOCK_FILE": str(self.tmp / "reconcile.lock"),
            "CONTAINER_INSTANCE_RECORDS_SYNC": str(self.bin / "container-records-sync"),
        })
        environ.update(env)
        return subprocess.run(["bash", str(SCRIPT), *args], env=environ, capture_output=True, text=True)

    @property
    def state(self) -> Dict[str, Any]:
        return json.loads(self.state_path.read_text())

    def param(self, name: str) -> Optional[str]:
        return self.state["params"].get(f"{PREFIX}/{name}")

    def docker_calls(self, verb: str) -> List[List[str]]:
        return [c[1:] for c in self.state["calls"] if c[0] == "docker" and c[1] == verb]

    def app_tag(self) -> Optional[str]:
        app = self.state["containers"].get("app")
        return app["image"].rsplit(":", 1)[1] if app and app["state"] == "running" else None


class ReconcilerTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.r = Reconciler(Path(self._tmp.name))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def assertDone(self, result: subprocess.CompletedProcess, code: int = 0) -> None:
        self.assertEqual(result.returncode, code, result.stderr)

    def test_converged_does_nothing(self) -> None:
        self.r.seed({"desired-version": "v1", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run())
        self.assertEqual(self.r.docker_calls("kill"), [])
        self.assertEqual(self.r.param("status"), "ok")

    def test_no_desired_version_does_nothing(self) -> None:
        self.r.seed({}, None)
        self.assertDone(self.r.run())
        self.assertEqual(self.r.state["started"], [])

    def test_swap_sends_one_signal_and_waits(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_STOP_POLLS="3"))
        kills = self.r.docker_calls("kill")
        self.assertEqual(kills, [["kill", "--signal=SIGINT", "app"]])
        calls = [c[1] for c in self.r.state["calls"] if c[0] == "docker"]
        self.assertLess(calls.index("update"), calls.index("kill"), "restart policy is cleared before the signal")
        self.assertEqual(self.r.app_tag(), "v2")
        self.assertEqual(self.r.param("running-version"), "v2")
        self.assertEqual(self.r.param("status"), "ok")
        self.assertGreaterEqual(len(self.r.sync_log.read_text().splitlines()), 2)
        self.assertIn("LICHESS_TOKEN=lip_secret", self.r.state["containers"]["app"]["env"])
        self.assertFalse(any((self.r.tmp / "run").glob("*.env")), "the env file is removed")

    def test_a_container_that_ignores_the_signal_is_waited_for_not_killed(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_STOP_POLLS="40"))
        self.assertEqual(len(self.r.docker_calls("kill")), 1)
        self.assertFalse(any("--force" in c for c in self.r.docker_calls("rm")[:1]))
        waiting = [v for n, v in self.r.state["puts"] if n.endswith("/status") and v == "waiting:v1"]
        self.assertGreaterEqual(len(waiting), 10, "waiting:<tag> is refreshed every minute")
        self.assertEqual(self.r.app_tag(), "v2")

    def test_secrets_are_read_before_the_old_container_is_stopped(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        result = self.r.run(FAKE_SECRET_FAIL="1")
        self.assertDone(result, 1)
        self.assertEqual(self.r.docker_calls("kill"), [])
        self.assertEqual(self.r.app_tag(), "v1")
        self.assertTrue(self.r.param("status").startswith("failed:"), self.r.param("status"))

    def test_a_failed_status_write_while_waiting_does_not_abort(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_STOP_POLLS="10", FAKE_PUT_FAIL_MATCH="^waiting:"))
        self.assertEqual(self.r.app_tag(), "v2")
        self.assertEqual(self.r.param("status"), "ok")

    def test_container_already_gone_at_the_signal(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_KILL_NOT_RUNNING="1"))
        self.assertEqual(self.r.app_tag(), "v2")
        self.assertEqual(self.r.param("status"), "ok")

    def test_unhealthy_version_rolls_back(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_UNHEALTHY="v2"), 1)
        self.assertEqual(len(self.r.docker_calls("kill")), 1)
        self.assertEqual(self.r.app_tag(), "v1")
        self.assertEqual(self.r.param("running-version"), "v1")
        self.assertEqual(self.r.param("status"), "failed:v2 did not become healthy; v1 restored")
        statuses = [v for n, v in self.r.state["puts"] if n.endswith("/status")]
        self.assertTrue(any(v.startswith("rolling-back:") for v in statuses))

    def test_a_version_that_cannot_start_rolls_back(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_RUN_FAIL="v2"), 1)
        self.assertEqual(self.r.app_tag(), "v1")
        self.assertEqual(self.r.param("status"), "failed:v2 did not become healthy; v1 restored")

    def test_rollback_that_fails_ends_in_a_terminal_status(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_UNHEALTHY="v2", FAKE_RUN_FAIL="v1"), 1)
        self.assertEqual(self.r.param("status"), "failed:v2 did not become healthy; v1 did not restart")

    def test_pull_failure_keeps_the_old_version(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_PULL_FAIL="v2"), 1)
        self.assertEqual(self.r.docker_calls("kill"), [])
        self.assertEqual(self.r.app_tag(), "v1")
        self.assertEqual(self.r.param("status"), "failed:could not pull v2")

    def test_a_deploy_during_the_wait_is_not_lost(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_DESIRED_DURING_WAIT="v3"))
        self.assertEqual(self.r.app_tag(), "v3")
        self.assertEqual(self.r.param("running-version"), "v3")
        self.assertEqual(len(self.r.docker_calls("kill")), 1)

    def test_a_dead_container_is_started_again_at_boot(self) -> None:
        self.r.seed({"desired-version": "v1", "running-version": "v1"}, "v1", app_state="exited")
        self.assertDone(self.r.run())
        self.assertEqual(self.r.app_tag(), "v1")
        self.assertEqual(self.r.docker_calls("kill"), [])
        self.assertEqual(self.r.param("status"), "ok")

    def test_restart_swaps_a_converged_container(self) -> None:
        self.r.seed({"desired-version": "v1", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run("--restart"))
        self.assertEqual(len(self.r.docker_calls("kill")), 1)
        self.assertEqual(self.r.app_tag(), "v1")
        self.assertEqual(self.r.state["started"], ["v1"])

    def test_a_long_log_does_not_fail_the_health_check(self) -> None:
        # grep -q stops reading at the first match; the log writer then dies
        # of SIGPIPE, which pipefail would report as a failed pipeline.
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run(FAKE_LONG_LOGS="1"))
        self.assertEqual(self.r.app_tag(), "v2")
        self.assertEqual(self.r.param("status"), "ok")

    def test_records_are_written_per_version(self) -> None:
        self.r.seed({"desired-version": "v2", "running-version": "v1"}, "v1")
        self.assertDone(self.r.run())
        run = self.r.docker_calls("run")[-1]
        volume = run[run.index("--volume") + 1]
        self.assertEqual(volume, f"{self.r.tmp / 'records'}/v2:/opt/lichess-bot/game_records")


if __name__ == "__main__":
    unittest.main()
