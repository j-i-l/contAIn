#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class CliConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.destination = self.directory / "cli.json"
        self.seed = self.directory / "seed.json"
        self.seed.write_text(json.dumps({"session": {"tps": True}}))

    def seed_config(self):
        return subprocess.run(
            ["bash", str(REPO / "lib/contain-cli-config-seed.sh"),
             str(self.destination), str(os.getuid()), str(os.getgid()), str(self.seed)],
            capture_output=True, text=True,
        )

    def test_creates_private_config(self):
        result = self.seed_config()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.destination.read_text()), {"session": {"tps": True}})
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.destination.stat().st_uid, os.getuid())
        self.assertEqual(self.destination.stat().st_gid, os.getgid())

    def test_merges_preferences_reasserts_tps_and_is_idempotent(self):
        self.destination.write_text(json.dumps({
            "theme": {"name": "catppuccin"},
            "session": {"tps": False, "thinking": "hide"},
        }))
        result = self.seed_config()
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = {"theme": {"name": "catppuccin"}, "session": {"tps": True, "thinking": "hide"}}
        self.assertEqual(json.loads(self.destination.read_text()), expected)
        self.assertEqual(self.seed_config().returncode, 0)
        self.assertEqual(json.loads(self.destination.read_text()), expected)

    def test_allows_explicit_disable(self):
        self.seed.write_text('{"session":{"tps":false}}')
        self.assertEqual(self.seed_config().returncode, 0)
        self.assertFalse(json.loads(self.destination.read_text())["session"]["tps"])

    def test_preserves_invalid_existing_config(self):
        self.destination.write_text("invalid JSON")
        self.assertNotEqual(self.seed_config().returncode, 0)
        self.assertEqual(self.destination.read_text(), "invalid JSON")

    def test_rejects_invalid_or_nonobject_seed(self):
        for text in ("invalid", "[]", "false", "null"):
            with self.subTest(text=text):
                self.seed.write_text(text)
                self.assertNotEqual(self.seed_config().returncode, 0)
                self.assertFalse(self.destination.exists())

    def test_does_not_follow_destination_symlink(self):
        target = self.directory / "outside"
        target.write_text("{}")
        target.chmod(0o640)
        self.destination.symlink_to(target)
        self.assertNotEqual(self.seed_config().returncode, 0)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)
        self.assertEqual(target.read_text(), "{}")


if __name__ == "__main__":
    unittest.main()
