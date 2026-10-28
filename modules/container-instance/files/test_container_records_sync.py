"""Unit tests for container-records-sync.py. Stdlib only, Python 3.9+.

Run: python3 -m unittest discover -s modules/container-instance/files -p 'test_*.py'
"""

import importlib.util
import json
import os
import tempfile
import time
import unittest
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location("records_sync", _HERE / "container-records-sync.py")
assert _SPEC and _SPEC.loader
sync = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(sync)

GAME_ID = "AbCd1234"
PGN = """[Event "Rated Blitz game"]
[Site "https://lichess.org/AbCd1234"]
[Date "2026.10.27"]
[White "rusty-chess-bot"]
[Black "Some \\"Quoted\\" Bot"]
[Result "1-0"]
[WhiteElo "1850"]
[BlackElo "?"]
[TimeControl "180+2"]
[UTCDate "2026.10.27"]
[UTCTime "21:04:05"]
[Variant "Standard"]
[Termination "Normal"]

1. e4 { [%eval 0.3] } e5 2. Nf3 1-0
"""

SIDECAR_KEYS = {
    "schema", "game_id", "engine_version", "image", "bot", "instance_id",
    "white", "black", "result", "utc_date", "utc_time", "time_control", "variant",
    "white_elo", "black_elo", "event", "site", "termination", "headers",
    "source_file", "sha256", "synced_at",
}


class ParseTests(unittest.TestCase):
    def test_headers_with_escaped_quotes(self) -> None:
        headers = sync.parse_headers(PGN)
        self.assertEqual(headers["Black"], 'Some "Quoted" Bot')
        self.assertEqual(headers["Result"], "1-0")
        self.assertEqual(len(headers), 13)

    def test_headers_stop_at_movetext(self) -> None:
        headers = sync.parse_headers(PGN + '\n[Fake "not a header"]\n')
        self.assertNotIn("Fake", headers)

    def test_complete_results(self) -> None:
        for result in ("1-0", "0-1", "1/2-1/2"):
            self.assertTrue(sync.is_complete({"Result": result}))
        for result in ("*", ""):
            self.assertFalse(sync.is_complete({"Result": result}))
        self.assertFalse(sync.is_complete({}))

    def test_game_id_from_file_name(self) -> None:
        name = f"rusty-chess-bot vs Other - {GAME_ID}.pgn"
        self.assertEqual(sync.game_id_from(name, {}), GAME_ID)

    def test_game_id_from_site(self) -> None:
        self.assertEqual(sync.game_id_from("odd.pgn", {"Site": "https://lichess.org/Zz9y8X7w"}), "Zz9y8X7w")

    def test_game_id_unparseable(self) -> None:
        self.assertIsNone(sync.game_id_from("odd.pgn", {"Site": "https://example.com/"}))

    def test_date_normalisation(self) -> None:
        self.assertEqual(sync.normalise_date("2026.10.27"), "2026-10-27")
        self.assertIsNone(sync.normalise_date("2026.??.??"))
        self.assertIsNone(sync.normalise_date(""))

    def test_elo(self) -> None:
        self.assertEqual(sync.to_int("1850"), 1850)
        self.assertIsNone(sync.to_int("?"))
        self.assertIsNone(sync.to_int(None))

    def test_config_values_are_shell_quoted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.env"
            path.write_text("A='x y'\nB=''\n# comment\nC='it'\"'\"'s'\n")
            self.assertEqual(sync.load_config(path), {"A": "x y", "B": "", "C": "it's"})


class StagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.records = root / "records"
        self.state = root / "state"
        self.engine_dir = self.records / "v0.14.0"
        self.engine_dir.mkdir(parents=True)
        self.context = sync.Context(
            image_repository="123456789012.dkr.ecr.us-east-1.amazonaws.com/jwall-engineering-rusty-chess",
            bot="rusty-chess-bot",
            instance_id="i-0123456789abcdef0",
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _write(self, name: str, text: str, age_seconds: int = 3600) -> Path:
        path = self.engine_dir / name
        path.write_text(text)
        old = time.time() - age_seconds
        os.utime(path, (old, old))
        return path

    def test_layout_and_sidecar(self) -> None:
        self._write(f"rusty-chess-bot vs Other - {GAME_ID}.pgn", PGN)
        counts = sync.stage_all(self.records, self.state, self.context, now=time.time())
        self.assertEqual(counts["staged"], 1)
        base = "schema=1/engine=v0.14.0/date=2026-10-27"
        pgn = self.state / "outbox" / "pgn" / base / f"{GAME_ID}.pgn"
        meta = self.state / "outbox" / "meta" / base / f"{GAME_ID}.json"
        self.assertEqual(pgn.read_text(), PGN)
        sidecar = json.loads(meta.read_text())
        self.assertEqual(set(sidecar), SIDECAR_KEYS)
        self.assertEqual(sidecar["schema"], 1)
        self.assertEqual(sidecar["game_id"], GAME_ID)
        self.assertEqual(sidecar["engine_version"], "v0.14.0")
        self.assertEqual(sidecar["image"], self.context.image_repository + ":v0.14.0")
        self.assertEqual(sidecar["white_elo"], 1850)
        self.assertIsNone(sidecar["black_elo"])
        self.assertEqual(sidecar["utc_date"], "2026-10-27")
        self.assertEqual(sidecar["termination"], "Normal")
        self.assertEqual(sidecar["headers"]["Black"], 'Some "Quoted" Bot')
        self.assertEqual(len(sidecar["sha256"]), 64)

    def test_incomplete_and_recent_games_are_skipped(self) -> None:
        self._write("a vs b - Aaaaaaaa.pgn", PGN.replace('[Result "1-0"]', '[Result "*"]'))
        self._write(f"a vs b - {GAME_ID}.pgn", PGN, age_seconds=5)
        counts = sync.stage_all(self.records, self.state, self.context, now=time.time())
        self.assertEqual(counts, {"staged": 0, "incomplete": 1, "recent": 1, "unparseable": 0, "already": 0})

    def test_staging_is_idempotent_across_shipping(self) -> None:
        self._write(f"a vs b - {GAME_ID}.pgn", PGN)
        sync.stage_all(self.records, self.state, self.context, now=time.time())
        sync.mark_shipped(self.state)
        self.assertFalse(any((self.state / "outbox").rglob("*.pgn")))
        counts = sync.stage_all(self.records, self.state, self.context, now=time.time())
        self.assertEqual(counts["already"], 1)
        self.assertEqual(counts["staged"], 0)

    def test_unsafe_engine_directory_is_ignored(self) -> None:
        bad = self.records / "bad dir"
        bad.mkdir()
        (bad / f"a vs b - {GAME_ID}.pgn").write_text(PGN)
        counts = sync.stage_all(self.records, self.state, self.context, now=time.time() + 3600)
        self.assertEqual(sum(counts.values()), 0)

    def test_undated_game_is_unparseable(self) -> None:
        text = PGN.replace('[Date "2026.10.27"]', '[Date "????.??.??"]').replace('[UTCDate "2026.10.27"]\n', "")
        self._write(f"a vs b - {GAME_ID}.pgn", text)
        counts = sync.stage_all(self.records, self.state, self.context, now=time.time())
        self.assertEqual(counts["unparseable"], 1)


if __name__ == "__main__":
    unittest.main()
