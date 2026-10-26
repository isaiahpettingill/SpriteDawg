import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('install-linux-deps.sh')


class LinuxDependencyTests(unittest.TestCase):
    def run_stubbed(self, installed, failures):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            commands = {
                'dpkg-query': '#!/bin/bash\n' + ('printf "install ok installed"\n' if installed else 'exit 1\n'),
                'timeout': '#!/bin/bash\nshift; exec "$@"\n',
                'sleep': '#!/bin/bash\nexit 0\n',
                'sudo': '''#!/bin/bash
n=$(cat "$STUB_DIR/count" 2>/dev/null || echo 0)
n=$((n+1)); echo "$n" > "$STUB_DIR/count"
printf '%s\\n' "$*" >> "$STUB_DIR/calls"
[[ "$n" -gt "$STUB_FAILURES" ]]
''',
            }
            for name, text in commands.items():
                file = folder / name; file.write_text(text); file.chmod(0o755)
            env = {**os.environ, 'PATH': directory + ':' + os.environ['PATH'],
                   'STUB_DIR': directory, 'STUB_FAILURES': str(failures)}
            result = subprocess.run(['bash', str(SCRIPT)], env=env, text=True, capture_output=True)
            calls = (folder / 'calls').read_text() if (folder / 'calls').exists() else ''
            return result, calls

    def test_installed_packages_do_not_touch_apt(self):
        result, calls = self.run_stubbed(True, 0)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, '')

    def test_transient_failure_retries_then_installs(self):
        result, calls = self.run_stubbed(False, 1)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(calls.splitlines()), 3)
        self.assertIn('Acquire::https::Timeout=20', calls)
        self.assertIn('install -y clang cmake', calls)

    def test_repeated_failure_stops(self):
        result, calls = self.run_stubbed(False, 99)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(calls.splitlines()), 2)


if __name__ == '__main__':
    unittest.main()
