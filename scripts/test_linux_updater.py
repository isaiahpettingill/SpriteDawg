"""Offline installer tests. Never installs to the user's home or contacts GitHub."""
import hashlib
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).parent / 'install-spritedawg.sh'
updater = types.ModuleType('updater')
exec(compile(SCRIPT.read_text().split("<<'PYTHON'\n", 1)[1].rsplit('\nPYTHON', 1)[0], str(SCRIPT), 'exec'), updater.__dict__)
TAG = 'v0.3.99'
NAME = f'spritedawg-{TAG}-linux-x64.tar.gz'
INFO = {'tag': TAG, 'arch': 'x64', 'asset': NAME, 'assets': {NAME: 'archive', 'SHA256SUMS': 'manifest'}}


def archive_bytes(extra=(), arch='x64'):
    executable = bytearray(20)
    executable[:6] = b'\x7fELF\x02\x01'
    executable[18:20] = (62 if arch == 'x64' else 183).to_bytes(2, 'little')
    entries = [('./spritedawg', bytes(executable), None),
               ('./release-version.txt', (TAG + '\n').encode(), None),
               ('./update-spritedawg.sh', b'#!/bin/bash\n', None),
               ('./share/icons/hicolor/scalable/apps/' + updater.APP_ID + '.svg', b'<svg/>', None),
               ('./share/mime/packages/' + updater.APP_ID + '.xml', b'<mime-info/>', None),
               *extra]
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w:gz') as tar:
        for name, data, kind in entries:
            member = tarfile.TarInfo(name)
            member.size = len(data)
            member.mode = 0o755
            if kind is not None:
                member.type = kind
                member.linkname = '../../outside'
            tar.addfile(member, io.BytesIO(data))
    return stream.getvalue()


class LinuxUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='updater tests ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'data with spaces $cash %percent'
        self.archive = archive_bytes()
        self.manifest = (hashlib.sha256(self.archive).hexdigest() + '  ' + NAME + '\n').encode()
        self.network = patch.object(updater, 'fetch', side_effect=self.fetch)
        self.network.start()
        self.addCleanup(self.network.stop)
        self.cache = patch.object(updater.shutil, 'which', return_value=None)
        self.cache.start()
        self.addCleanup(self.cache.stop)

    def fetch(self, url, destination=None, limit=0):
        if url == 'manifest':
            return self.manifest
        self.assertEqual(url, 'archive')
        destination.write_bytes(self.archive)
        return b''

    def test_install_and_repeat_keep_old_version_and_registration(self):
        result = updater.install(INFO, self.home)
        self.assertTrue(result.is_file())
        old = (self.home / 'spritedawg/current').resolve()
        updater.install(INFO, self.home)
        self.assertNotEqual(old, (self.home / 'spritedawg/current').resolve())
        self.assertTrue((old / 'spritedawg').is_file())
        desktop = (self.home / 'applications' / (updater.APP_ID + '.desktop')).read_text()
        self.assertIn('%%percent', desktop)
        self.assertIn('\\\\$cash', desktop)
        self.assertIn(' %F\n', desktop)
        self.assertIn('image/x-aseprite;', desktop)
        self.assertIn('Terminal=false', desktop)
        self.assertEqual(len(list((self.home / 'spritedawg/versions').iterdir())), 2)

    def test_tamper_does_not_change_old_install_or_desktop(self):
        updater.install(INFO, self.home)
        current = (self.home / 'spritedawg/current').resolve()
        desktop = (self.home / 'applications' / (updater.APP_ID + '.desktop')).read_bytes()
        self.archive += b'tamper'
        with self.assertRaisesRegex(ValueError, 'checksum'):
            updater.install(INFO, self.home)
        self.assertEqual(current, (self.home / 'spritedawg/current').resolve())
        self.assertEqual(desktop, (self.home / 'applications' / (updater.APP_ID + '.desktop')).read_bytes())

    def test_registration_failure_rolls_back_all_files(self):
        updater.install(INFO, self.home)
        current = (self.home / 'spritedawg/current').resolve()
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
        with patch.object(updater, 'atomic_bytes', side_effect=failing):
            with self.assertRaisesRegex(OSError, 'disk full'):
                updater.install(INFO, self.home)
        self.assertEqual(current, (self.home / 'spritedawg/current').resolve())
        self.assertEqual(desktop.read_text(), 'old desktop')
        self.assertEqual(len(list((self.home / 'spritedawg/versions').iterdir())), 1)

    def test_reject_downgrade(self):
        updater.install(INFO, self.home)
        (self.home / 'spritedawg/current/release-version.txt').write_text('v9.0.0')
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            updater.install(INFO, self.home)

    def test_reject_wrong_architecture_before_registration(self):
        self.archive = archive_bytes(arch='arm64')
        self.manifest = (hashlib.sha256(self.archive).hexdigest() + '  ' + NAME + '\n').encode()
        with self.assertRaisesRegex(ValueError, 'architecture'):
            updater.install(INFO, self.home)
        self.assertFalse((self.home / 'spritedawg/current').exists())

    def test_unsafe_archives_rejected_before_writes(self):
        for name, kind in [('../escape', None), ('/tmp/escape', None), ('./spritedawg', None),
                           ('link', tarfile.SYMTYPE), ('link', tarfile.LNKTYPE),
                           ('device', tarfile.CHRTYPE), ('a\\b', None)]:
            with self.subTest(name=name, kind=kind):
                file = Path(self.temp.name) / 'bad.tar.gz'
                file.write_bytes(archive_bytes([(name, b'x', kind)]))
                destination = Path(self.temp.name) / 'unpack'
                destination.mkdir(exist_ok=True)
                with self.assertRaises(ValueError):
                    updater.unpack(file, destination)
                self.assertEqual(list(destination.iterdir()), [])

    def test_archive_size_limit(self):
        file = Path(self.temp.name) / 'big.tar.gz'
        file.write_bytes(self.archive)
        target = Path(self.temp.name) / 'unpack'
        target.mkdir()
        with patch.object(updater, 'MAX_UNPACKED', 2), self.assertRaisesRegex(ValueError, 'limits'):
            updater.unpack(file, target)
        self.assertEqual(list(target.iterdir()), [])

    def test_checksum_requires_unique_exact_filename(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            updater.checksum(self.manifest * 2, NAME)
        with self.assertRaisesRegex(ValueError, 'Missing'):
            updater.checksum(self.manifest, 'other.tar.gz')
        with self.assertRaisesRegex(ValueError, 'Malformed'):
            updater.checksum(b'../escape', NAME)

    def test_only_fixed_https_hosts(self):
        for url in ['http://github.com/x', 'https://evil.com/x', 'https://github.com.evil/x',
                    'https://user:pass@github.com/x', 'https://github.com:444/x']:
            with self.assertRaises(ValueError):
                updater.validate_url(url)
        self.assertEqual(updater.validate_url('https://release-assets.githubusercontent.com/x'),
                         'https://release-assets.githubusercontent.com/x')

    def test_release_api_exact_assets_stable_only(self):
        payload = {'tag_name': TAG, 'draft': False, 'prerelease': False, 'assets': [
            {'name': name, 'state': 'uploaded', 'browser_download_url':
             f'https://github.com/{updater.REPO}/releases/download/{TAG}/{name}'}
            for name in [NAME, 'SHA256SUMS']]}
        with patch.object(updater, 'fetch', return_value=json.dumps(payload).encode()):
            self.assertEqual(updater.release(arch='x64')['tag'], TAG)
        for mutation in ['draft', 'prerelease']:
            payload[mutation] = True
            with patch.object(updater, 'fetch', return_value=json.dumps(payload).encode()), self.assertRaises(ValueError):
                updater.release(arch='x64')
            payload[mutation] = False
        payload['assets'][0]['browser_download_url'] = 'https://github.com/evil/x'
        with patch.object(updater, 'fetch', return_value=json.dumps(payload).encode()), self.assertRaises(ValueError):
            updater.release(arch='x64')

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
        self.assertEqual(updater.desktop_quote('/path/quote"'), '"/path/quote\\\\\""')

    def test_no_downloaded_scripts_are_executed(self):
        # Installation is file publication and native database refresh only.
        with patch.object(updater.subprocess, 'run') as run:
            updater.install(INFO, self.home)
            run.assert_not_called()

if __name__ == '__main__':
    unittest.main()
