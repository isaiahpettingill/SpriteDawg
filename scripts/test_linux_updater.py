"""Offline self-replacement tests. No real app is executed, no home/network access."""
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).parent / 'install-spritedawg.sh'
updater = types.ModuleType('updater')
exec(compile(SCRIPT.read_text().split("<<'PYTHON'\n", 1)[1].rsplit('\nPYTHON', 1)[0], str(SCRIPT), 'exec'), updater.__dict__)
TAG = 'v0.3.99'
NAME = f'spritedawg-{TAG}-linux-x64.AppImage'
INFO = {'tag': TAG, 'arch': 'x64', 'asset': NAME, 'assets': {NAME: 'image', 'SHA256SUMS': 'manifest'}}


def image_bytes(arch='x64', payload=b'new payload'):
    executable = bytearray(20)
    executable[:6] = b'\x7fELF\x02\x01'
    executable[8:11] = b'AI\x02'
    executable[18:20] = (62 if arch == 'x64' else 183).to_bytes(2, 'little')
    return bytes(executable) + payload


class LinuxUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='updater tests ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'data with spaces $cash %percent'
        self.image = image_bytes()
        self.manifest = self.make_manifest()
        self.network = patch.object(updater, 'fetch', side_effect=self.fetch)
        self.network.start()
        self.addCleanup(self.network.stop)
        self.cache = patch.object(updater.shutil, 'which', return_value=None)
        self.cache.start()
        self.addCleanup(self.cache.stop)

    def make_manifest(self):
        return (hashlib.sha256(self.image).hexdigest() + '  ' + NAME + '\n').encode()

    def fetch(self, url, destination=None, limit=0):
        if url == 'manifest':
            return self.manifest
        self.assertEqual(url, 'image')
        destination.write_bytes(self.image)
        return b''

    def portable(self):
        path = Path(self.temp.name) / 'Sprite Dawg $cash %percent.AppImage'
        path.write_bytes(image_bytes(payload=b'old payload'))
        path.chmod(0o755)
        return path

    def update(self, target, version='v0.3.98'):
        return updater.install(INFO, self.home, target, version)

    def test_fresh_install_with_group_writable_umask_is_private(self):
        previous = os.umask(0o002)
        try:
            target = updater.install(INFO, self.home)
        finally:
            os.umask(previous)
        self.assertEqual(target.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(target.read_bytes(), self.image)

    def test_self_replaces_same_path_and_retains_old_running_inode(self):
        target = self.portable()
        with target.open('rb') as running:
            inode = target.stat().st_ino
            self.assertEqual(self.update(target), target)
            self.assertEqual(target.read_bytes(), self.image)
            self.assertNotEqual(inode, target.stat().st_ino)
            self.assertEqual(running.read(), image_bytes(payload=b'old payload'))
        self.assertFalse(self.home.exists())
        self.assertEqual(list(target.parent.glob('.spritedawg-update-*')), [])
        self.assertTrue(os.access(target, os.X_OK))

    def test_hardlinks_or_interrupted_backup_do_not_modify_other_paths(self):
        target = self.portable()
        other = target.with_name('retained-old-copy')
        os.link(target, other)
        self.update(target)
        self.assertEqual(target.read_bytes(), self.image)
        self.assertEqual(other.read_bytes(), image_bytes(payload=b'old payload'))

    def test_fresh_install_repeat_and_legacy_migration_preserve_all_data(self):
        legacy = self.home / 'spritedawg/versions/old'
        legacy.mkdir(parents=True)
        (legacy / 'release-version.txt').write_text('v0.3.98')
        (legacy / 'spritedawg').write_text('old executable')
        (self.home / 'spritedawg/current').symlink_to('versions/old')
        drafts = self.home / 'org.pocketpixel.SpriteDawg/drafts'
        drafts.mkdir(parents=True)
        (drafts / 'drawing').write_bytes(b'drawing preferences draft')
        target = updater.install(INFO, self.home)
        self.assertEqual(target.name, 'SpriteDawg.AppImage')
        updater.install(INFO, self.home)
        self.assertEqual(list(legacy.parent.iterdir()), [legacy])
        self.assertEqual((legacy / 'spritedawg').read_text(), 'old executable')
        self.assertEqual((drafts / 'drawing').read_bytes(), b'drawing preferences draft')
        desktop = (self.home / 'applications' / (updater.APP_ID + '.desktop')).read_text()
        self.assertIn('%%percent', desktop)
        self.assertIn('\\\\$cash', desktop)
        self.assertIn(' %F\n', desktop)
        self.assertIn('image/x-aseprite;', desktop)
        self.assertIn('Terminal=false', desktop)
        self.assertIn('StartupWMClass=' + updater.APP_ID, desktop)
        self.assertIn('Icon=' + str(self.home), desktop)

    @unittest.skipUnless(shutil.which('desktop-file-validate'), 'desktop validator unavailable')
    def test_desktop_quoting_passes_standard_validator(self):
        file = Path(self.temp.name) / 'test.desktop'
        file.write_text(updater.desktop_text(Path('/tmp/spaces $cash %percent/"quote`tick\\slash'), Path('/tmp/icon.svg')))
        subprocess.run(['desktop-file-validate', str(file)], check=True, capture_output=True)

    def test_metadata_is_original_icon_and_aseprite_mime_not_theme_collision(self):
        repository = SCRIPT.parent.parent
        self.assertEqual(updater.ICON, (repository / 'art/spritedawg.svg').read_text())
        self.assertEqual(updater.MIME, (repository / 'linux/packaging/org.pocketpixel.SpriteDawg.xml').read_text())
        self.assertIn('*.aseprite', updater.MIME)
        self.assertIn('*.ase', updater.MIME)

    def test_checksum_failure_leaves_target_and_registration_unchanged(self):
        target = updater.install(INFO, self.home)
        original = target.read_bytes()
        self.image += b'tamper'
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.update(target)
        self.assertEqual(target.read_bytes(), original)
        self.assertFalse(list(target.parent.glob('.spritedawg-update-*')))

    def test_download_failure_and_disk_full_do_not_replace_old_file(self):
        target = self.portable()
        for error in (TimeoutError('interrupted'), OSError(errno.ENOSPC, 'disk full')):
            with self.subTest(error=error):
                with patch.object(updater, 'fetch', side_effect=error), self.assertRaises(type(error)):
                    self.update(target)
                self.assertEqual(target.read_bytes(), image_bytes(payload=b'old payload'))

    def test_registration_symlink_parent_cannot_write_outside_app_paths(self):
        self.home.mkdir(parents=True)
        outside = Path(self.temp.name) / 'unrelated'
        outside.mkdir()
        (self.home / 'icons').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlinked'):
            updater.install(INFO, self.home)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse((self.home / 'spritedawg/SpriteDawg.AppImage').exists())

    def test_publish_failure_rolls_back_metadata_and_binary(self):
        target = updater.install(INFO, self.home)
        old = target.read_bytes()
        self.image = image_bytes(payload=b'replacement')
        self.manifest = self.make_manifest()
        with patch.object(updater, 'sync_directory', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                self.update(target)
        self.assertEqual(target.read_bytes(), old)

    def test_registration_failure_rolls_back_all_files(self):
        target = updater.install(INFO, self.home)
        desktop = self.home / 'applications' / (updater.APP_ID + '.desktop')
        desktop.write_text('old desktop')
        original = updater.atomic_bytes
        calls = 0
        def failing(path, data):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('disk full')
            return original(path, data)
        with patch.object(updater, 'atomic_bytes', side_effect=failing), self.assertRaises(OSError):
            updater.install(INFO, self.home)
        self.assertEqual(desktop.read_text(), 'old desktop')
        self.assertEqual(target.read_bytes(), self.image)

    def test_wrong_architecture_and_non_appimage_never_replace_old_file(self):
        for data in (image_bytes(arch='arm64'), b'not an AppImage', image_bytes().replace(b'AI\x02', b'AI\x01')):
            target = self.portable()
            self.image = data
            self.manifest = self.make_manifest()
            with self.assertRaisesRegex(ValueError, 'architecture'):
                self.update(target)
            self.assertEqual(target.read_bytes(), image_bytes(payload=b'old payload'))

    def test_reject_downgrade_even_from_an_old_still_running_instance(self):
        target = self.portable()
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            self.update(target, 'v9.0.0')
        version = target.with_name('.' + target.name + '.version')
        version.write_text('v9.0.0')
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            self.update(target)

    def test_symlink_readonly_and_unowned_targets_refused(self):
        target = self.portable()
        link = target.with_name('symlink.AppImage')
        link.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            self.update(link)
        target.chmod(0o555)
        with self.assertRaisesRegex(ValueError, 'writable'):
            self.update(target)
        target.chmod(0o755)
        with patch.object(updater.os, 'getuid', return_value=999999), self.assertRaisesRegex(ValueError, 'writable'):
            self.update(target)
        target.parent.chmod(0o555)
        try:
            with self.assertRaisesRegex(ValueError, 'writable'):
                self.update(target)
        finally:
            target.parent.chmod(0o700)

    def test_concurrent_updates_refused(self):
        target = self.portable()
        lock = target.with_name('.' + target.name + '.update.lock')
        with lock.open('w') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, 'in progress'):
                self.update(target)

    def test_target_changed_during_download_is_not_overwritten(self):
        target = self.portable()
        original_fetch = self.fetch
        def changing(*args, **kwargs):
            result = original_fetch(*args, **kwargs)
            if args[0] == 'image':
                target.write_bytes(image_bytes(payload=b'another update'))
            return result
        with patch.object(updater, 'fetch', side_effect=changing), self.assertRaisesRegex(ValueError, 'changed'):
            self.update(target)
        self.assertEqual(target.read_bytes(), image_bytes(payload=b'another update'))

    def test_checksum_requires_unique_exact_filename(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            updater.checksum(self.manifest * 2, NAME)
        with self.assertRaisesRegex(ValueError, 'Missing'):
            updater.checksum(self.manifest, 'other.AppImage')
        with self.assertRaisesRegex(ValueError, 'Malformed'):
            updater.checksum(b'../escape', NAME)

    def test_only_fixed_https_hosts(self):
        for url in ['http://github.com/x', 'https://evil.com/x', 'https://github.com.evil/x',
                    'https://user:pass@github.com/x', 'https://github.com:444/x']:
            with self.assertRaises(ValueError):
                updater.validate_url(url)

    def test_release_selects_exact_appimage_both_architectures_no_tar_fallback(self):
        for arch in ('x64', 'arm64'):
            name = f'spritedawg-{TAG}-linux-{arch}.AppImage'
            payload = {'tag_name': TAG, 'draft': False, 'prerelease': False, 'assets': [
                {'name': item, 'state': 'uploaded', 'browser_download_url':
                 f'https://github.com/{updater.REPO}/releases/download/{TAG}/{item}'}
                for item in [name, 'SHA256SUMS']]}
            with patch.object(updater, 'fetch', return_value=json.dumps(payload).encode()):
                self.assertEqual(updater.release(arch=arch)['asset'], name)
            payload['assets'][0]['name'] = name.replace('.AppImage', '.tar.gz')
            with patch.object(updater, 'fetch', return_value=json.dumps(payload).encode()), self.assertRaises(ValueError):
                updater.release(arch=arch)

    def test_release_rejects_wrong_version_unpublished_and_hostile_urls(self):
        base = {'tag_name': TAG, 'draft': False, 'prerelease': False, 'assets': [
            {'name': item, 'state': 'uploaded', 'browser_download_url':
             f'https://github.com/{updater.REPO}/releases/download/{TAG}/{item}'}
            for item in [NAME, 'SHA256SUMS']]}
        mutations = [
            lambda data: data.update(tag_name='v0.3.98'),
            lambda data: data.update(draft=True),
            lambda data: data.update(prerelease=True),
            lambda data: data['assets'][0].update(state='new'),
            lambda data: data['assets'][0].update(browser_download_url='https://github.com/other/asset'),
            lambda data: data['assets'].append(data['assets'][0]),
        ]
        for mutation in mutations:
            payload = json.loads(json.dumps(base))
            mutation(payload)
            with patch.object(updater, 'fetch', return_value=json.dumps(payload).encode()):
                with self.assertRaises(ValueError):
                    updater.release(TAG, 'x64')

    def test_version_and_platform_validation(self):
        for value in ['v1.2.3-rc1', 'v01.2.3', '1.2.3', 'v1.2.3;exit', '../x', None]:
            with self.assertRaises(ValueError):
                updater.version(value)
        self.assertEqual(updater.architecture('aarch64'), 'arm64')
        with self.assertRaises(ValueError):
            updater.architecture('armv7l')

    def test_desktop_control_characters_rejected(self):
        with self.assertRaises(ValueError):
            updater.desktop_quote('/home/user\nExec=evil')

    def test_no_downloaded_scripts_or_appimages_are_executed(self):
        with patch.object(updater.subprocess, 'run') as run:
            updater.install(INFO, self.home)
            self.update(self.portable())
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
