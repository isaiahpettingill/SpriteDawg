"""Pure offline tests: python3 -m unittest discover -s scripts -p 'test_*.py'."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("release-plan.py")
spec = importlib.util.spec_from_file_location("release_plan", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleasePlanTests(unittest.TestCase):
    def test_version_and_android_upgrade(self):
        self.assertEqual(module.release_plan("version: 0.3.0+5\n", "23"),
                         {"version": "0.3.23", "build_number": 10023, "tag": "v0.3.23"})
        self.assertGreater(module.release_plan("version: 0.3.0+5", "1")["build_number"], 2004)

    def test_rerun_is_identical(self):
        for _attempt in range(1, 5):
            self.assertEqual(module.release_plan("version: 0.3.0+5", "23"),
                             module.release_plan("version: 0.3.0+5", "23"))

    def test_monotonic_and_base_major_minor(self):
        first = module.release_plan("version: 12.34.99+500", "9")
        second = module.release_plan("version: 12.34.99+500", "10")
        self.assertEqual(second["version"], "12.34.10")
        self.assertGreater(second["build_number"], first["build_number"])

    def test_play_limit_includes_largest_abi(self):
        limit = module.PLAY_MAX_VERSION_CODE - module.BUILD_OFFSET - module.MAX_ABI_OFFSET
        self.assertEqual(module.release_plan("version: 0.3.0", str(limit))["build_number"] + 3000,
                         module.PLAY_MAX_VERSION_CODE)
        with self.assertRaises(ValueError):
            module.release_plan("version: 0.3.0", str(limit + 1))

    def test_invalid_run_numbers(self):
        for value in ("0", "-1", "1.2", "01", " 1", "1\n", "1e3", "", "$(echo 1)"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.release_plan("version: 0.3.0", value)

    def test_invalid_versions(self):
        for value in ("0.3.0-dev+5", "0.3.0-rc.1", "01.3.0", "0.03.0", "0.3", '"0.3.0"', "0.3.0+abc"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.release_plan(f"version: {value}", "1")
        for text in ("", "version: 0.3.0\nversion: 0.4.0"):
            with self.assertRaises(ValueError):
                module.release_plan(text, "1")

    def test_cli_formats_and_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_text("name: example\nversion: 0.3.0+5 # comment\n")
            command = [sys.executable, str(SCRIPT), "--pubspec", str(pubspec), "--run-number", "23"]
            parsed = json.loads(subprocess.check_output(command, text=True))
            self.assertEqual(parsed["tag"], "v0.3.23")
            env = subprocess.check_output(command + ["--format", "env"], text=True)
            self.assertEqual(env, "version=0.3.23\nbuild_number=10023\ntag=v0.3.23\n")
            failed = subprocess.run(command[:-1] + ["0"], capture_output=True, text=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(failed.stdout, "")


if __name__ == "__main__":
    unittest.main()
