import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('publisher', Path(__file__).parents[1] / 'publish-release.py')
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)
SHA = 'a' * 40
TAG = 'v0.3.25'
REPO = 'owner/project'


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        self.notes = self.root / 'notes.md'
        self.notes.write_text('Release notes')
        names = [f'spritedawg-{TAG}-android-{a}.apk' for a in ('armeabi-v7a', 'arm64-v8a', 'x86_64')]
        names += [f'spritedawg-{TAG}-linux-{a}.tar.gz' for a in ('x64', 'arm64')]
        for name in names:
            (self.assets / name).write_bytes(name.encode())
        self.write_manifest()
        self.files, self.hashes = publisher.local_assets(self.assets, TAG)
        self.payloads = {n: p.read_bytes() for n, p in self.files.items()}
        self.release = None
        self.commit = None
        self.calls = []
        self.others = []
        self.latest = None
        self.patch = patch.object(publisher, 'gh', side_effect=self.fake_gh)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def write_manifest(self):
        (self.assets / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n'
            for p in sorted(self.assets.iterdir()) if p.name != 'SHA256SUMS'))

    def make_release(self, draft=True, names=()):
        self.release = {'id': 42, 'tag_name': TAG, 'target_commitish': SHA,
                        'draft': draft, 'prerelease': False,
                        'html_url': 'https://github.com/owner/project/releases/tag/' + TAG,
                        'assets': []}
        for name in names:
            self.add_asset(name)
        return self.release

    def add_asset(self, name):
        self.release['assets'].append({'id': len(self.release['assets']) + 100,
                                      'name': name, 'digest': 'sha256:' + self.hashes[name]})

    def fake_gh(self, *args, binary=False):
        self.calls.append(args)
        if args[:2] == ('release', 'create'):
            self.make_release()
            return ''
        if args[:2] == ('release', 'upload'):
            self.add_asset(Path(args[3]).name)
            return ''
        self.assertEqual(args[0], 'api')
        endpoint = args[1]
        if '/git/matching-refs/' in endpoint:
            value = [] if self.commit is None else [{'ref': 'refs/tags/' + TAG,
                                                    'object': {'sha': self.commit, 'type': 'commit'}}]
        elif endpoint.endswith('/releases?per_page=100'):
            value = [[*self.others, *([copy.deepcopy(self.release)] if self.release else [])]]
        elif '/releases/assets/' in endpoint:
            asset = next(a for a in self.release['assets'] if str(a['id']) == endpoint.rsplit('/', 1)[1])
            return self.payloads[asset['name']]
        elif endpoint.endswith('/releases/latest'):
            if self.latest is None:
                raise subprocess.CalledProcessError(1, ['gh'], stderr=b'HTTP 404')
            value = copy.deepcopy(self.latest)
        elif '/releases/' in endpoint:
            identifier = int(endpoint.rsplit('/', 1)[1])
            target = next(r for r in [self.release, *self.others] if r['id'] == identifier)
            if '--method' in args:
                if 'draft=false' in args:
                    target['draft'] = False
                    self.commit = SHA
                if 'make_latest=true' in args:
                    self.latest = target
            value = copy.deepcopy(target)
        else:
            raise AssertionError(args)
        return json.dumps(value)

    def publish(self):
        return publisher.publish(REPO, SHA, TAG, self.assets, self.notes)

    def test_new_draft_upload_and_publish(self):
        self.assertIn(TAG, self.publish())
        self.assertEqual(len(self.release['assets']), 6)
        self.assertFalse(self.release['draft'])
        self.assertTrue(any('make_latest=false' in c for c in self.calls))
        self.assertEqual(self.latest['id'], self.release['id'])
        self.assertFalse(any('--clobber' in c for c in self.calls))

    def test_partial_draft_resumes_only_missing(self):
        existing = next(iter(self.files))
        self.make_release(names=[existing])
        self.publish()
        uploads = [c for c in self.calls if c[:2] == ('release', 'upload')]
        self.assertEqual(len(uploads), 5)
        self.assertNotIn(existing, [Path(c[3]).name for c in uploads])

    def test_published_rerun_uses_remote_manifest_and_never_mutates(self):
        self.make_release(draft=False, names=self.files)
        self.commit = SHA
        self.latest = self.release
        next(p for n, p in self.files.items() if n.endswith('.apk')).write_bytes(b'rebuilt bytes')
        self.write_manifest()
        self.publish()
        self.assertFalse(any(c[0] == 'release' or '--method' in c for c in self.calls))

    def test_wrong_tag_fails_before_mutation(self):
        self.commit = 'b' * 40
        with self.assertRaisesRegex(ValueError, 'different commit'):
            self.publish()
        self.assertFalse(any(c[0] == 'release' for c in self.calls))

    def test_changed_draft_asset_fails_without_overwrite(self):
        self.make_release(names=self.files)
        self.release['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with self.assertRaisesRegex(ValueError, 'refusing overwrite'):
            self.publish()
        self.assertFalse(any(c[0] == 'release' for c in self.calls))

    def test_published_missing_asset_is_not_repaired(self):
        self.make_release(draft=False, names=list(self.files)[:-1])
        self.commit = SHA
        with self.assertRaisesRegex(ValueError, 'invalid asset set'):
            self.publish()
        self.assertFalse(any(c[0] == 'release' for c in self.calls))

    def test_older_release_does_not_become_latest(self):
        self.others = [{'id': 99, 'tag_name': 'v0.3.26', 'draft': False, 'prerelease': False}]
        self.latest = self.others[0]
        self.publish()
        self.assertTrue(any('make_latest=false' in c for c in self.calls))
        self.assertEqual(self.latest['id'], 99)

    def test_concurrent_newer_publication_repairs_stale_latest_write(self):
        original = self.fake_gh
        inserted = False
        def interleaved(*args, **kwargs):
            nonlocal inserted
            if 'make_latest=true' in args and not inserted:
                # A newer run publishes between this run's read and stale PATCH.
                self.others = [{'id': 99, 'tag_name': 'v0.3.26',
                                'draft': False, 'prerelease': False}]
                self.latest = self.others[0]
                inserted = True
            return original(*args, **kwargs)
        with patch.object(publisher, 'gh', side_effect=interleaved):
            self.publish()
        self.assertEqual(self.latest['id'], 99)
        writes = [c[1] for c in self.calls if 'make_latest=true' in c]
        self.assertEqual(writes, [f'repos/{REPO}/releases/42', f'repos/{REPO}/releases/99'])

    def test_published_retry_repairs_latest_metadata_only(self):
        self.make_release(draft=False, names=self.files)
        self.commit = SHA
        self.others = [{'id': 99, 'tag_name': 'v0.3.24',
                        'draft': False, 'prerelease': False}]
        self.latest = self.others[0]
        self.publish()
        self.assertEqual(self.latest['id'], 42)
        self.assertFalse(any(c[0] == 'release' for c in self.calls))
        writes = [c for c in self.calls if '--method' in c]
        self.assertEqual(len(writes), 1)
        self.assertIn('make_latest=true', writes[0])
        self.assertNotIn('draft=false', writes[0])

    def test_api_failure_is_not_interpreted_as_absent(self):
        with patch.object(publisher, 'gh', side_effect=subprocess.CalledProcessError(1, ['gh'])):
            with self.assertRaises(subprocess.CalledProcessError):
                self.publish()
        self.assertIsNone(self.release)

    def test_digest_fallback_downloads_asset(self):
        self.make_release(names=self.files)
        self.release['assets'][0].pop('digest')
        self.publish()
        self.assertTrue(any('/releases/assets/' in c[1] for c in self.calls if c[0] == 'api'))

    def test_upload_failure_leaves_draft_and_retry_resumes(self):
        original = self.fake_gh
        def interrupted(*args, **kwargs):
            if args[:2] == ('release', 'upload') and len(self.release['assets']) == 2:
                raise subprocess.CalledProcessError(1, ['gh', 'release', 'upload'])
            return original(*args, **kwargs)
        with patch.object(publisher, 'gh', side_effect=interrupted):
            with self.assertRaises(subprocess.CalledProcessError):
                self.publish()
        self.assertTrue(self.release['draft'])
        self.assertEqual(len(self.release['assets']), 2)
        self.calls.clear()
        self.publish()
        self.assertEqual(len([c for c in self.calls if c[:2] == ('release', 'upload')]), 4)

    def test_unexpected_remote_asset_fails(self):
        self.make_release(names=self.files)
        self.release['assets'].append({'id': 999, 'name': 'surprise.txt', 'digest': 'sha256:' + '0' * 64})
        with self.assertRaisesRegex(ValueError, 'Unexpected'):
            self.publish()

    def test_annotated_tag_is_peeled(self):
        original = self.fake_gh
        def annotated(*args, **kwargs):
            if args[0] == 'api' and '/git/matching-refs/' in args[1]:
                return json.dumps([{'ref': 'refs/tags/' + TAG,
                                    'object': {'sha': 'b' * 40, 'type': 'tag'}}])
            if args[0] == 'api' and '/git/tags/' in args[1]:
                return json.dumps({'object': {'sha': SHA, 'type': 'commit'}})
            return original(*args, **kwargs)
        with patch.object(publisher, 'gh', side_effect=annotated):
            self.publish()
        self.assertFalse(self.release['draft'])

    def test_local_corruption_fails_before_network(self):
        (self.assets / next(n for n in self.files if n.endswith('.apk'))).write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.publish()
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
