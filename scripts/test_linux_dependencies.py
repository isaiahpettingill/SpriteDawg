"""Exercise dependency decisions with fake tools; never invoke real apt/sudo."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('install-linux-deps.sh').resolve()

class DependenciesTest(unittest.TestCase):
    def run_script(self, version='99.0.0', installed=False):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def command(name, body):
                path = root / name
                path.write_text('#!/bin/bash\n' + body + '\n')
                path.chmod(0o755)
            for name in ['clang', 'cmake', 'ninja', 'pkg-config', 'meson', 'nasm']:
                command(name, 'echo "tool version ' + version + '"')
            command('dpkg-query', 'echo "' + ('install ok installed' if installed else 'not installed') + '"')
            command('timeout', 'shift; exec "$@"')
            command('sudo', 'printf "%s\\n" "$*" >> "$CALLS"')
            env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'], CALLS=str(root / 'calls'))
            subprocess.run(['bash', str(SCRIPT)], env=env, check=True, capture_output=True)
            return (root / 'calls').read_text() if (root / 'calls').exists() else ''

    def test_toolcache_commands_skip_distro_tools_but_not_headers(self):
        calls = self.run_script()
        install = calls.splitlines()[-1]
        self.assertIn('--no-install-recommends', install)
        self.assertIn('libgtk-3-dev libstdc++-12-dev', install)
        for package in [' clang', ' cmake', ' ninja-build', ' pkg-config', ' meson', ' nasm']:
            self.assertNotIn(package, install)

    def test_old_or_unparseable_commands_require_packages(self):
        for version in ['1.0', 'unknown']:
            install = self.run_script(version).splitlines()[-1]
            for package in ['clang', 'cmake', 'ninja-build']:
                self.assertIn(package, install)

    def test_installed_dependencies_do_not_touch_network(self):
        self.assertEqual(self.run_script(installed=True), '')
