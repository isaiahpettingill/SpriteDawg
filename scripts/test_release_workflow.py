"""Regression guards for the trusted publication boundary (no network)."""
import unittest
import re
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/android.yml'

class ReleaseWorkflowTests(unittest.TestCase):
    def test_only_trusted_main_can_sign_and_publish(self):
        source = WORKFLOW.read_text()
        guard = "github.event_name == 'push' && github.ref == 'refs/heads/main'"
        for job in ('signed-android', 'release'):
            section = re.split(r'\n  [a-z][a-z-]*:', source.split(f'  {job}:\n', 1)[1])[0]
            self.assertIn(guard, section)
        self.assertNotIn('pull_request_target', source)
        self.assertNotIn("tags: ['v*']", source)
        self.assertNotIn('[release]', source)

    def test_publication_requires_every_gate_and_pinned_signer(self):
        source = WORKFLOW.read_text()
        self.assertIn('needs: [version, test, android, android-interaction, linux, signed-android]', source)
        self.assertIn('8c66b44614c82edfa120b99f05101d938dbf6afac70d2ad8c55c058c757dd296', source)
        self.assertIn('versionCode=', source)
        self.assertIn('--build-number "$build_number"', source)
        self.assertIn('group: spritedawg-production-release-${{ github.run_id }}', source)
        self.assertNotIn('--clobber', source)
        self.assertIn("needs.version.outputs.native == 'false' && needs.android.result == 'skipped'", source)
        self.assertIn("needs.version.outputs.device == 'false' && needs.android-interaction.result == 'skipped'", source)
        self.assertIn("needs.signed-android.result == 'success'", source)
        self.assertIn("needs.linux.result == 'success'", source)
        # Flutter3.47 retains3 for removed x86; x86_64 is4.
        self.assertIn('armeabi-v7a) offset=1000', source)
        self.assertIn('arm64-v8a) offset=2000', source)
        self.assertIn('x86_64) offset=4000', source)

if __name__ == '__main__':
    unittest.main()
