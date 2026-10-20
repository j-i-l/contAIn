#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class RuntimeStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.data = self.home / ".local/share/opencode"
        self.data.mkdir(parents=True)
        self.root = self.base / "service/opencode"
        for suffix in ("", "-wal", "-shm"):
            file = self.data / ("opencode.db" + suffix)
            file.write_text("retained" + suffix)
            file.chmod(0o660)

    def migrate(self):
        return subprocess.run(
            ["bash", str(REPO / "lib/contain-runtime-state.sh"),
             str(self.root), str(self.home), str(os.getuid()), str(os.getgid())],
            capture_output=True, text=True,
        )

    def test_migrates_sqlite_set_privately_and_keeps_recovery_copy(self):
        result = self.migrate()
        self.assertEqual(result.returncode, 0, result.stderr)
        for suffix in ("", "-wal", "-shm"):
            name = "opencode.db" + suffix
            target = self.root / "data" / name
            self.assertEqual(target.read_text(), "retained" + suffix)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual((self.data / name).read_text(), target.read_text())
            self.assertEqual((Path(str(self.root) + ".legacy-backup") / "data" / name).read_text(), target.read_text())
        self.assertEqual(self.root.stat().st_mode & 0o777, 0o700)
        self.assertEqual(Path(str(self.root) + ".legacy-backup").stat().st_mode & 0o777, 0o700)
        (self.root / "data/opencode.db").write_text("new state")
        self.assertEqual(self.migrate().returncode, 0)
        self.assertEqual((self.root / "data/opencode.db").read_text(), "new state")

    def test_refuses_existing_uninitialized_destination(self):
        self.root.mkdir(parents=True)
        self.assertNotEqual(self.migrate().returncode, 0)

    def test_refuses_interrupted_migration(self):
        Path(str(self.root) + ".migrating").mkdir(parents=True)
        self.assertNotEqual(self.migrate().returncode, 0)
        self.assertFalse(self.root.exists())

    def test_initializes_without_legacy_state(self):
        for file in self.data.iterdir():
            file.unlink()
        self.assertEqual(self.migrate().returncode, 0)
        for kind in ("config", "data", "state"):
            self.assertEqual((self.root / kind).stat().st_mode & 0o777, 0o700)

    def test_rejects_symlinks_without_touching_target(self):
        outside = self.base / "outside"
        outside.write_text("private")
        outside.chmod(0o640)
        (self.data / "link").symlink_to(outside)
        self.assertNotEqual(self.migrate().returncode, 0)
        self.assertEqual(outside.stat().st_mode & 0o777, 0o640)
        self.assertFalse((self.root / ".ready").exists())

    def test_watcher_separates_projects_and_private_state(self):
        import pwd
        user = pwd.getpwuid(os.getuid()).pw_name
        project = self.base / "projects"
        project.mkdir()
        private = project / "private"
        private.mkdir(mode=0o700)
        database = private / "opencode.db"
        database.write_text("private")
        database.chmod(0o600)
        ordinary = project / "ordinary"
        ordinary.write_text("shared")
        ordinary.chmod(0o644)
        executable = project / "executable"
        executable.write_text("executable")
        executable.chmod(0o755)
        directory = project / "directory"
        directory.mkdir()
        git = project / ".git"
        git.mkdir(mode=0o750)
        protected = git / "config"
        protected.write_text("protected")
        protected.chmod(0o640)
        outside = self.base / "outside"
        outside.write_text("outside")
        outside.chmod(0o640)
        link = project / "link"
        link.symlink_to(outside)
        events = [ordinary, executable, directory, database, protected, link]
        tools = self.base / "bin"
        tools.mkdir()
        monitor = tools / "inotifywait"
        monitor.write_text("#!/bin/sh\nprintf '%s\\n' " + " ".join(
            "'" + str(file) + "'" for file in events) + "\n")
        monitor.chmod(0o755)
        result = subprocess.run(
            ["bash", str(REPO / "lib/contain-watcher.sh"), user, user,
             str(project), "--exclude", str(private)],
            env={**os.environ, "PATH": str(tools) + ":" + os.environ["PATH"]},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(ordinary.stat().st_mode & 0o777, 0o660)
        self.assertEqual(executable.stat().st_mode & 0o777, 0o770)
        self.assertEqual(directory.stat().st_mode & 0o7777, 0o2770)
        self.assertEqual(database.stat().st_mode & 0o777, 0o600)
        self.assertEqual(protected.stat().st_mode & 0o777, 0o640)
        self.assertEqual(outside.stat().st_mode & 0o777, 0o640)


if __name__ == "__main__":
    unittest.main()
